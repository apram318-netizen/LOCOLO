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
        do {
            let authRes = try await client.auth.signUp(email: email, password: password)

             let supaUser = authRes.user
            // Insert user row in your table immediately
            let newUser = User(
                id: UUID(uuidString: supaUser.id.uuidString)!,
                username: username,
                email: email.lowercased(),
                name: nil,
                bio: nil,
                avatarUrl: nil,
                coverUrl: nil,
                joinedAt: Date(),
                verifiedFlags: nil,
                stats: ["followers": 0, "following": 0, "posts": 0]
            )

            try await userRepository.createUser(newUser)

            return true
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
            return false
        }
    }

    
    func verifySignupOTP(email: String, otp: String) async -> Bool {
        do {
            // MUST use .signup
            let _ = try await client.auth.verifyOTP(
                email: email,
                token: otp,
                type: .signup
            )

            // SUPABASE QUIRK:
            // Refresh session so email_confirmed_at updates
            let _ = try await client.auth.session

            // Load the user's profile from DB
            if let user = try await getUser(byEmail: email) {
                await MainActor.run {
                    self.currentUser = user
                    self.isAuthenticated = true
                    SupabaseManager.shared.currentUserId = user.id.uuidString.lowercased()
                }
            }

            return true

        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
            return false
        }
    }

    
    
    // MARK: - Login
    /// Logs a user in using email and password.
    /// Loads user profile details after successful authentication.
    func login(email: String, password: String) async {
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            let userIdString = session.user.id.uuidString

            guard let userId = UUID(uuidString: userIdString) else {
                throw NSError(domain: "Invalid user ID", code: -1)
            }

            guard let user = try await userRepository.getUser(by: userId) else {
                throw NSError(domain: "User profile not found. Please try again.", code: -1)
            }

            currentUser = user
            isAuthenticated = true
            SupabaseManager.shared.currentUserId = user.id.uuidString.lowercased()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    
    
    // MARK: - Logout
    /// Logs out the user and clears local session data.
    func logout() async {
        do {
            try await client.auth.signOut()

            // Clear auth state
            currentUser = nil
            SupabaseManager.shared.currentUserId = nil
            isAuthenticated = false
            
            // Clear location session
            LocationManager.shared.stopTracking()

            // Clear cached CoreData
            CacheStore.shared.clearAllCache()

            // Clear MediaCache files
            MediaCache.shared.clear()

            // Clear UserDefaults
            clearAllUserDefaults()

            print(" FULL LOGOUT CLEANUP COMPLETE")

        } catch {
            errorMessage = error.localizedDescription
        }
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

            guard let user = try await userRepository.getUser(by: userId) else {
                // Session token exists but user profile not found in DB.
                // Stay logged out without destroying the session.
                return
            }

            currentUser = user
            SupabaseManager.shared.currentUserId = user.id.uuidString.lowercased()
            isAuthenticated = true
        } catch {
            // No valid session or network error — stay logged out.
        }
    }
    
    
    
    // MARK: - Reset Password
    /// Sends a password reset email to the specified address.
    func resetPassword(email: String) async {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            guard try await userRepository.getUser(byUsername: normalized) != nil else {
                errorMessage = "No account exists for that email."
                return
            }

            try await client.auth.resetPasswordForEmail(normalized)
            errorMessage = "Password reset email sent."
        } catch {
            errorMessage = error.localizedDescription
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
    func verifyEmailOTP(email: String, otp: String) async -> Bool {
        do {
            let _ = try await client.auth.verifyOTP(
                email: email,
                token: otp,
                type: .email
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
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

    func startResetPassword(email: String) async -> Bool {
        let exists = await doesUserExist(email: email)

        guard exists else {
            await MainActor.run {
                errorMessage = "No account found with this email."
            }
            return false
        }

        await sendEmailOTP(email: email)
        return true
    }

    
    // MARK: FUNCTION: getUser (by email)
    func getUser(byEmail email: String) async throws -> User? {
        let normalized = email.lowercased()
        
        
        let response: [User] = try await client
            .from("users")
            .select()
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
        do {
            try await client.auth.update(
                user: UserAttributes(password: newPassword)
            )
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
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
