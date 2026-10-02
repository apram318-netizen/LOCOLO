//
//  UsersViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 19/9/2025.
//

import Combine
import Foundation
import Supabase

@MainActor
class UserViewModel: ObservableObject {
    
    static let shared = UserViewModel()
    
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String?
    /// Non-error feedback ("code sent", "reset link on its way"). Kept separate
    /// so success never renders in red as an error.
    @Published var infoMessage: String?
    @Published var isEmailVerified: Bool = false
    
    
    @Published var otherUser: User?
    @Published var isLoadingOtherUser = false
    
    let client = SupabaseManager.shared.client
    private let userRepository = UsersRepository()
    
    private var timerCancellable: AnyCancellable?
    
    // MARK: - Verification Polling
    /// Starts a timer to poll for email verification status every few seconds.
    /// Discussion: Useful right after signup to auto-detect when the user verifies their email.
    func startVerificationPolling() {
        timerCancellable = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.fetchEmailVerificationStatus()
                }
            }
    }
    
    /// Stops the verification polling timer.
    func stopVerificationPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    // MARK: - Email Verification Status
    /// Checks the current session for email verification status.
    /// Returns `true` if the user’s email is confirmed.
    func fetchEmailVerificationStatus() async -> Bool {
        do {
            let session = try await client.auth.session
            let verified = session.user.emailConfirmedAt != nil
            
            await checkEmailVerification()
            return verified
        } catch {
            print(" Error checking email verification: \(error.localizedDescription)")
            await MainActor.run {
                self.isEmailVerified = false
            }
            return false
        }
    }
    
    
    
    /// Refreshes and updates the `isEmailVerified` flag for the logged-in user.
    func checkEmailVerification() async {
        do {
            let userResponse = try await client.auth.user()
            let verified = userResponse.emailConfirmedAt != nil
            
            await MainActor.run {
                self.isEmailVerified = verified
            }
        } catch {
            self.errorMessage = "Failed to fetch user: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Sign Up
    /// Registers a new user with email, password, and username.
    /// Also inserts a matching user record in Supabase `users` table.
    func signUp(email: String, password: String, username: String) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        errorMessage = nil

        // Validate up front so the user gets a precise message instead of a
        // server error after a round trip.
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            errorMessage = "Please enter a valid email address."
            return false
        }
        guard password.count >= 8 else {
            errorMessage = "Use at least 8 characters for your password."
            return false
        }
        guard normalizedName.count >= 3,
              normalizedName.range(of: "^[a-z0-9._]+$", options: .regularExpression) != nil else {
            errorMessage = "Usernames are 3+ characters, using letters, numbers, . or _"
            return false
        }

        do {
            // Username rides along as auth metadata so the handle_new_user
            // trigger (safety migration) can create the profile row even
            // when RLS refuses the client insert below (no session until the
            // email is confirmed).
            let authRes = try await client.auth.signUp(
                email: normalizedEmail,
                password: password,
                data: ["username": .string(normalizedName)]
            )

             let supaUser = authRes.user
            // Insert user row in your table immediately
            let newUser = User(
                id: UUID(uuidString: supaUser.id.uuidString)!,
                username: normalizedName,
                email: normalizedEmail,
                name: nil,
                bio: nil,
                avatarUrl: nil,
                coverUrl: nil,
                joinedAt: Date(),
                verifiedFlags: nil,
                stats: ["followers": 0, "following": 0, "posts": 0]
            )

            do {
                try await userRepository.createUser(newUser)
            } catch let error as PostgrestError where error.code == "23505" || error.code == "42501" {
                // 23505: the trigger already created the row.
                // 42501: RLS refused the pre-confirmation insert; the trigger owns it.
                print("Profile row left to handle_new_user:", error.message)
            }

            return true
        } catch {
            await MainActor.run {
                self.errorMessage = AuthErrorMapper.message(for: error, context: .signUp)
            }
            return false
        }
    }


    /// Confirms the sign-up code and signs the user straight in.
    /// - Parameter codeSentAt: when the code was (re)sent, so a wrong code isn't
    ///   reported as "expired" (Supabase returns the same error for both).
    func verifySignupOTP(email: String, otp: String, codeSentAt: Date? = nil) async -> Bool {
        errorMessage = nil
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = otp.filter(\.isNumber)
        guard code.count == 6 else {
            errorMessage = "Enter the 6-digit code from the email."
            return false
        }
        do {
            let response = try await client.auth.verifyOTP(email: normalized, token: code, type: .signup)
            guard let session = response.session else {
                errorMessage = "Your email is verified. Sign in to continue."
                return false
            }
            return await completeSignIn(authUser: session.user)
        } catch {
            errorMessage = AuthErrorMapper.message(for: error, context: .otp, codeSentAt: codeSentAt)
            return false
        }
    }

    /// Sends a fresh sign-up code. Supabase rate-limits this (default 60 s).
    func resendSignupCode(email: String) async -> Bool {
        errorMessage = nil
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            try await client.auth.resend(email: normalized, type: .signup)
            infoMessage = "New code sent to \(normalized)."
            return true
        } catch {
            errorMessage = AuthErrorMapper.message(for: error, context: .resend)
            return false
        }
    }

    // MARK: - Profile bootstrap

    /// Loads the profile for a freshly authenticated user, creating it if it's
    /// missing (accounts made before the handle_new_user trigger existed, or
    /// Apple/Google sign-ins whose trigger run raced the first fetch).
    /// Never strands a signed-in user behind a "still being set up" error.
    func completeSignIn(authUser: Auth.User, preferredName: String? = nil) async -> Bool {
        let userId = authUser.id
        var profile = try? await userRepository.getUser(by: userId)
        if profile == nil {
            profile = await createMissingProfile(authUser: authUser, preferredName: preferredName)
        }
        let user = profile ?? User(
            id: userId,
            username: Self.baseHandle(for: authUser),
            email: authUser.email ?? "",
            name: preferredName, bio: nil, avatarUrl: nil, coverUrl: nil,
            joinedAt: Date(), verifiedFlags: nil,
            stats: ["followers": 0, "following": 0, "posts": 0]
        )
        currentUser = user
        SupabaseManager.shared.currentUserId = user.id.uuidString.lowercased()
        isAuthenticated = true
        errorMessage = nil
        return true
    }

    private func createMissingProfile(authUser: Auth.User, preferredName: String?) async -> User? {
        struct Insert: Encodable {
            let user_id: UUID
            let username: String
            let email: String?
            let name: String?
            let joined_at: Date
            let stats: [String: Int]
        }
        let base = Self.baseHandle(for: authUser)
        let candidates = [base, base + "_" + String(authUser.id.uuidString.lowercased().prefix(5))]
        for handle in candidates {
            do {
                try await client.from("users")
                    .insert(Insert(user_id: authUser.id, username: handle,
                                   email: authUser.email?.lowercased(), name: preferredName,
                                   joined_at: Date(),
                                   stats: ["followers": 0, "following": 0, "posts": 0]),
                            returning: .minimal)
                    .execute()
                break
            } catch let error as PostgrestError where error.code == "23505" {
                // Either the row now exists (trigger won the race) or the
                // handle is taken — re-check, then try the suffixed handle.
                if let existing = try? await userRepository.getUser(by: authUser.id) { return existing }
                continue
            } catch {
                LocoloLog.auth.error("Profile bootstrap failed: \(error.localizedDescription, privacy: .public)")
                break
            }
        }
        return try? await userRepository.getUser(by: authUser.id)
    }

    /// A valid `[a-z0-9._]` handle from sign-up metadata, else the email prefix.
    private static func baseHandle(for authUser: Auth.User) -> String {
        let fromMeta: String? = {
            if case let .string(name)? = authUser.userMetadata["username"] { return name }
            return nil
        }()
        let raw = (fromMeta?.isEmpty == false ? fromMeta! : nil)
            ?? authUser.email?.split(separator: "@").first.map(String.init)
            ?? "explorer"
        let cleaned = raw.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
            .filter(\.isASCII)
        return cleaned.count >= 3 ? String(cleaned.prefix(30)) : "explorer_" + String(authUser.id.uuidString.lowercased().prefix(6))
    }

    // MARK: - Apple / Google

    /// Exchanges an Apple identity token for a Supabase session.
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async -> Bool {
        errorMessage = nil
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            let name = fullName.flatMap { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            return await completeSignIn(authUser: session.user,
                                        preferredName: (name?.isEmpty == false) ? name : nil)
        } catch {
            errorMessage = AuthErrorMapper.message(for: error, context: .social)
            return false
        }
    }

    /// Google via Supabase OAuth in an ASWebAuthenticationSession (no SDK).
    /// Requires the Google provider enabled in Supabase and
    /// `locolo://login-callback` in Auth → URL Configuration → Redirect URLs.
    func signInWithGoogle() async -> Bool {
        errorMessage = nil
        do {
            let session = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "locolo://login-callback")
            ) { webSession in
                webSession.prefersEphemeralWebBrowserSession = false
            }
            return await completeSignIn(authUser: session.user)
        } catch {
            // Closing the Google sheet isn't an error worth showing.
            if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
               (error as NSError).code == 1 { return false }
            errorMessage = AuthErrorMapper.message(for: error, context: .social)
            return false
        }
    }

    // MARK: - Login
    /// Logs a user in using email and password.
    /// Loads user profile details after successful authentication.
    /// Signs in and loads the profile. Normalizes the email, retries once on a
    /// transient transport failure, and surfaces a human error message.
    /// - Returns: whether sign-in succeeded.
    @discardableResult
    func login(email: String, password: String) async -> Bool {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        errorMessage = nil

        guard !normalized.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return false
        }

        do {
            let session: Session
            do {
                session = try await client.auth.signIn(email: normalized, password: password)
            } catch where AuthErrorMapper.isRetryable(error) {
                // One silent retry: a dropped connection shouldn't read as
                // "wrong password" to the user.
                session = try await client.auth.signIn(email: normalized, password: password)
            }

            // Missing profile rows are created on the spot — the user should
            // just land in the app, never on a "still being set up" error.
            return await completeSignIn(authUser: session.user)
        } catch {
            errorMessage = AuthErrorMapper.message(for: error, context: .signIn)
            return false
        }
    }
    
    
    
    // MARK: - Logout
    /// Logs out the user and clears local session data.
    ///
    /// Local state is always cleared, even if the server call fails: after
    /// account deletion the session is already invalid, and leaving the user
    /// "signed in" to a deleted account is worse than a stale refresh token.
    func logout() async {
        do {
            try await client.auth.signOut()
        } catch {
            print(" Supabase signOut failed, clearing local session anyway:", error.localizedDescription)
            try? await client.auth.signOut(scope: .local)
        }

        currentUser = nil
        SupabaseManager.shared.currentUserId = nil
        isAuthenticated = false

        LocationManager.shared.stopTracking()
        CacheStore.shared.clearAllCache()
        MediaCache.shared.clear()
        clearAllUserDefaults()

        print(" FULL LOGOUT CLEANUP COMPLETE")
    }

    
    func clearAllUserDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        print("UserDefaults cleared")
    }
    
    // MARK: - Restore Session
    /// Attempts to restore an existing authenticated session on app launch.
    /// Discussion: Useful for keeping users logged in between app restarts.
    func restoreSession() async {
        do {
            let session = try await client.auth.session
            let userIdString = session.user.id.uuidString
            guard let userId = UUID(uuidString: userIdString) else { return }

            if let user = try await userRepository.getUser(by: userId) {
                currentUser = user
                SupabaseManager.shared.currentUserId = user.id.uuidString.lowercased()
                isAuthenticated = true
            } else {
                _ = await completeSignIn(authUser: session.user)
            }
        } catch {
            // No valid session or network error — stay logged out.
        }
    }
    
    
    
    // MARK: - Reset Password
    /// Sends a password reset email to the specified address.
    /// Sends a password-reset email.
    ///
    /// Previously this looked the address up with `getUser(byUsername:)` — an
    /// email passed to a *username* lookup, so it almost always returned nil and
    /// reported "No account exists for that email" even for real accounts.
    /// It also leaked which emails are registered; we now always report success.
    func resetPassword(email: String) async {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        errorMessage = nil

        do {
            try await client.auth.resetPasswordForEmail(normalized)
            infoMessage = "If an account exists for \(normalized), a reset link is on its way."
        } catch {
            errorMessage = AuthErrorMapper.message(for: error, context: .reset)
        }
    }
    
    
    
    // MARK: - Update Profile
    /// Updates the user profile data in Supabase.
    /// Discussion: Reflects immediately in the `currentUser` property.
    func updateProfile(_ user: User) async {
        do {
            try await userRepository.updateUser(user.id, data: user)
            currentUser = user
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    
    
    // MARK: - Send Verification Email
    /// Sends a verification email manually (mainly for fallback flows).
    func sendVerificationEmail(email: String, username: String) async {
        do {
            let tempPass = UUID().uuidString.prefix(12)
            let _ = try await client.auth.signUp(email: email, password: String(tempPass))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    
    
    // MARK: - Check Verification State
    /// Returns whether the current session user’s email has been verified.
    func checkEmailVerified() async -> Bool {
        do {
            let session = try await client.auth.session
            return session.user.emailConfirmedAt != nil
        } catch {
            return false
        }
    }
    
    
    
    // MARK: - OTP Auth
    /// Sends a one-time password to the user’s email.
    func sendEmailOTP(email: String) async {
        do {
            try await client.auth.signInWithOTP(email: email)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    
    
    /// Verifies a one-time password sent to the user’s email.
    func verifyEmailOTP(email: String, otp: String, codeSentAt: Date? = nil) async -> Bool {
        errorMessage = nil
        let code = otp.filter(\.isNumber)
        guard code.count == 6 else {
            errorMessage = "Enter the 6-digit code from the email."
            return false
        }
        do {
            let _ = try await client.auth.verifyOTP(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                token: code,
                type: .email
            )
            return true
        } catch {
            errorMessage = AuthErrorMapper.message(for: error, context: .otp, codeSentAt: codeSentAt)
            return false
        }
    }
    
    
    func loadOtherUser(by id: UUID) async {
        isLoadingOtherUser = true
        defer { isLoadingOtherUser = false }
        
        do {
            if let user = try await userRepository.getUser(by: id) {
                self.otherUser = user
            } else {
                print(" User not found for id \(id)")
                self.otherUser = nil
            }
        } catch {
            print(" Error fetching user \(id):", error.localizedDescription)
            self.otherUser = nil
        }
    }

    func clearOtherUser() {
        otherUser = nil
    }
    
    func doesUserExist(email: String) async -> Bool {
        // Preferred: a boolean-only RPC (safety migration) — anon can't read
        // the users table once RLS is on. Falls back to the legacy query
        // until that migration is applied.
        struct Params: Encodable { let p_email: String }
        if let exists: Bool = try? await client
            .rpc("email_registered", params: Params(p_email: email.lowercased()))
            .execute()
            .value {
            return exists
        }
        do {
            let users: [ExistingUserLookup] = try await client
                .from("users")
                .select("user_id")
                .eq("email", value: email.lowercased())
                .limit(1)
                .execute()
                .value

            return !users.isEmpty

        } catch {
            print("Error checking user existence:", error.localizedDescription)
            return false
        }
    }

    /// Starts the forgot-password flow.
    ///
    /// Always advances to the OTP screen and reports the same message whether or
    /// not the address is registered — replying "No account found" here lets
    /// anyone test which emails have Locolo accounts. Supabase simply won't
    /// deliver a code for an unknown address.
    func startResetPassword(email: String) async -> Bool {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        errorMessage = nil
        infoMessage = nil

        guard normalized.contains("@"), normalized.contains(".") else {
            errorMessage = "Please enter a valid email address."
            return false
        }

        do {
            // shouldCreateUser: false — the default would silently create an
            // account for any address typed into "Forgot password".
            try await client.auth.signInWithOTP(email: normalized, shouldCreateUser: false)
            infoMessage = "If an account exists for that email, we've sent a code."
            return true
        } catch {
            // Unknown addresses fail with "signups not allowed" — report the
            // same success so the screen can't be used to probe for accounts.
            if AuthErrorMapper.isOffline(error) || AuthErrorMapper.isRateLimited(error) {
                errorMessage = AuthErrorMapper.message(for: error, context: .reset)
                return false
            }
            infoMessage = "If an account exists for that email, we've sent a code."
            return true
        }
    }

    
    // MARK: FUNCTION: getUser (by email)
    func getUser(byEmail email: String) async throws -> User? {
        let normalized = email.lowercased()
        
        
        let response: [User] = try await client
            .from("users")
            .select(User.publicColumns)
            .eq("email", value: normalized)
            .limit(1)
            .execute()
            .value
        
        if let user = response.first {
            
            return user
        }
        return nil
    }
    
    func updatePassword(to newPassword: String) async -> Bool {
        errorMessage = nil
        do {
            let response = try await client.auth.update(
                user: UserAttributes(password: newPassword)
            )
            // The reset code signed the user in — go straight into the app.
            return await completeSignIn(authUser: response)
        } catch {
            self.errorMessage = AuthErrorMapper.message(for: error, context: .generic)
            return false
        }
    }

    /// Clears banners when an auth screen appears, so one screen's error never
    /// shows up on the next (the old shared-errorMessage bug).
    func clearAuthMessages() {
        errorMessage = nil
        infoMessage = nil
    }
    
    func finishUserRegistration(email: String, username: String) async {
        do {
            let session = try await client.auth.session
            let idString = session.user.id.uuidString
            guard let userId = UUID(uuidString: idString) else { return }

            let user = User(
                id: userId,
                username: username,
                email: email,
                name: nil,
                bio: nil,
                avatarUrl: nil,
                coverUrl: nil,
                joinedAt: Date(),
                verifiedFlags: nil,
                stats: ["followers": 0, "following": 0, "posts": 0]
            )

            try await userRepository.createUser(user)
            currentUser = user
            isAuthenticated = true

        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    

}

struct ExistingUserLookup: Decodable {
    let id: UUID?
}

// Research resources
/// https://youtu.be/-7FZq7J2m4c?si=su3hw_pQEWHojkVY
/// https://supabase.com/docs/guides/auth/passwords
/// https://supabase.com/docs/guides/auth/auth-email-passwordless
/// https://github.com/supabase/auth/issues/1517#issuecomment-976200828 THis healped me a lot to understand but during implementation I was facing heavy bugs with this implementations so I decided to check email verification againsta the supabase stored users table.
///
// This file handles everything about the user in the app.
//It manages signing up, logging in, logging out, and restoring the user session.
//It also checks email verification, sends OTP codes, resets passwords, and loads user data from Supabase.
//The view model keeps track of the current user and updates the app when anything changes.
