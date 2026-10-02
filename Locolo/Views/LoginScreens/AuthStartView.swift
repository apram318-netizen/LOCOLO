//
//  AuthStartView.swift
//  Locolo
//
//  The whole signed-out experience: one NavigationStack, value-based routes.
//  Every screen keeps its OWN error/info state and clears the shared
//  `UserViewModel` banners on appear — previously the sign-in error leaked
//  onto the sign-up screen because every screen read the same errorMessage.
//
//  Sign-in options: Apple, Google (Supabase OAuth, no SDK) and email.
//  Once `userVM.isAuthenticated` flips, ContentView swaps in the app, so no
//  screen here navigates "to main" itself.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

enum AuthRoute: Hashable {
    case signIn
    case signUp
    case verifySignup(email: String)
    case forgotPassword
    case verifyReset(email: String)
    case newPassword
}

struct AuthStartView: View {
    @EnvironmentObject var userVM: UserViewModel
    @State private var path: [AuthRoute] = []

    @State private var error: String?
    @State private var busy: SocialProvider?
    @State private var appleNonce = ""

    enum SocialProvider { case apple, google }

    var body: some View {
        NavigationStack(path: $path) {
            AuthScaffold {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)
                    brand
                    Spacer(minLength: 40)

                    VStack(spacing: 12) {
                        SignInWithAppleButton(.continue) { request in
                            appleNonce = AuthNonce.random()
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = AuthNonce.sha256(appleNonce)
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(busy != nil)
                        .overlay { if busy == .apple { busyOverlay } }

                        Button(action: google) {
                            HStack(spacing: 10) {
                                GoogleGlyph().frame(width: 18, height: 18)
                                Text("Continue with Google")
                            }
                        }
                        .buttonStyle(AuthSecondaryButtonStyle())
                        .disabled(busy != nil)
                        .overlay { if busy == .google { busyOverlay } }

                        Button { path.append(.signUp) } label: {
                            Label("Sign up with email", systemImage: "envelope.fill")
                        }
                        .buttonStyle(AuthSecondaryButtonStyle())

                        AuthMessage(error: error, info: nil)
                            .padding(.top, 4)

                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundStyle(.white.opacity(0.6))
                            Button("Sign in") { path.append(.signIn) }
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                        .font(.subheadline)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)

                    Text("By continuing you agree to Locolo's Terms and Privacy Policy.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                }
            }
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .signIn: SignInView(path: $path)
                case .signUp: SignUpView(path: $path)
                case .verifySignup(let email): EmailCodeView(email: email, purpose: .signup, path: $path)
                case .forgotPassword: ForgotPasswordEmailView(path: $path)
                case .verifyReset(let email): EmailCodeView(email: email, purpose: .reset, path: $path)
                case .newPassword: NewPasswordView()
                }
            }
            .onAppear {
                userVM.clearAuthMessages()
                error = nil
            }
        }
        .tint(.white)
    }

    private var brand: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AuthTheme.accent)
                    .frame(width: 92, height: 92)
                    .blur(radius: 24)
                    .opacity(0.8)
                Image(systemName: "arkit")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("Locolo")
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(AuthTheme.accent)
            Text("Leave art in the real world.\nFind what others left behind.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private var busyOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.black.opacity(0.45))
            .overlay(ProgressView().tint(.white))
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let err):
            // 1001 = the user cancelled the Apple sheet.
            if (err as NSError).code != ASAuthorizationError.canceled.rawValue {
                error = "Apple sign-in didn't complete. Please try again."
            }
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                error = "Apple didn't return a sign-in token. Please try again."
                return
            }
            busy = .apple
            error = nil
            Task {
                let ok = await userVM.signInWithApple(idToken: token, nonce: appleNonce,
                                                      fullName: credential.fullName)
                busy = nil
                if !ok { error = userVM.errorMessage }
            }
        }
    }

    private func google() {
        busy = .google
        error = nil
        Task {
            let ok = await userVM.signInWithGoogle()
            busy = nil
            if !ok { error = userVM.errorMessage }
        }
    }
}

// MARK: - Sign in

struct SignInView: View {
    @EnvironmentObject var userVM: UserViewModel
    @Binding var path: [AuthRoute]

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case email, password }

    var body: some View {
        AuthScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AuthHeader(title: "Welcome back", subtitle: "Sign in to pick up where you left off.")

                    AuthField(icon: "envelope", placeholder: "Email", text: $email,
                              keyboard: .emailAddress, content: .emailAddress)
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }

                    AuthField(icon: "lock", placeholder: "Password", text: $password,
                              isSecure: true, content: .password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)

                    HStack {
                        Spacer()
                        Button("Forgot password?") { path.append(.forgotPassword) }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    AuthMessage(error: error, info: nil)

                    Button(action: submit) {
                        if isLoading { ProgressView().tint(.black) } else { Text("Sign in") }
                    }
                    .buttonStyle(AuthPrimaryButtonStyle())
                    .disabled(isLoading)

                    HStack(spacing: 4) {
                        Spacer()
                        Text("New to Locolo?").foregroundStyle(.white.opacity(0.6))
                        Button("Create an account") {
                            path.removeAll { $0 == .signIn }
                            path.append(.signUp)
                        }
                        .fontWeight(.bold)
                        Spacer()
                    }
                    .font(.subheadline)
                }
                .padding(24)
            }
        }
        .onAppear {
            userVM.clearAuthMessages()
            error = nil
            focus = .email
        }
        .onChange(of: email) { error = nil }
        .onChange(of: password) { error = nil }
    }

    private func submit() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        Task {
            let ok = await userVM.login(email: email, password: password)
            isLoading = false
            if !ok {
                error = userVM.errorMessage
                // Unverified account: offer the code screen instead of a dead end.
                if error?.contains("verify your email") == true {
                    let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    _ = await userVM.resendSignupCode(email: normalized)
                    path.append(.verifySignup(email: normalized))
                }
            }
        }
    }
}

// MARK: - Sign up

struct SignUpView: View {
    @EnvironmentObject var userVM: UserViewModel
    @Binding var path: [AuthRoute]

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case username, email, password }

    private var usernameHint: String? {
        let u = username.lowercased()
        guard !u.isEmpty else { return nil }
        if u.count < 3 { return "At least 3 characters" }
        if u.range(of: "^[a-z0-9._]+$", options: .regularExpression) == nil {
            return "Letters, numbers, . and _ only"
        }
        return nil
    }

    var body: some View {
        AuthScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AuthHeader(title: "Create your account",
                               subtitle: "We'll email you a 6-digit code to confirm it's you.")

                    VStack(alignment: .leading, spacing: 6) {
                        AuthField(icon: "at", placeholder: "Username", text: $username, content: .username)
                            .focused($focus, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focus = .email }
                        if let hint = usernameHint {
                            Text(hint).font(.caption).foregroundStyle(.orange)
                        }
                    }

                    AuthField(icon: "envelope", placeholder: "Email", text: $email,
                              keyboard: .emailAddress, content: .emailAddress)
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }

                    VStack(alignment: .leading, spacing: 6) {
                        AuthField(icon: "lock", placeholder: "Password (8+ characters)", text: $password,
                                  isSecure: true, content: .newPassword)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                        PasswordStrengthBar(password: password)
                    }

                    AuthMessage(error: error, info: nil)

                    Button(action: submit) {
                        if isLoading { ProgressView().tint(.black) } else { Text("Send code") }
                    }
                    .buttonStyle(AuthPrimaryButtonStyle())
                    .disabled(isLoading)
                }
                .padding(24)
            }
        }
        .onAppear {
            userVM.clearAuthMessages()
            error = nil
        }
        .onChange(of: email) { error = nil }
        .onChange(of: username) { error = nil }
    }

    private func submit() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        Task {
            let ok = await userVM.signUp(email: email, password: password, username: username)
            isLoading = false
            if ok {
                path.append(.verifySignup(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()))
            } else {
                error = userVM.errorMessage
            }
        }
    }
}

// MARK: - Code entry (sign-up confirmation + password reset)

struct EmailCodeView: View {
    enum Purpose { case signup, reset }

    @EnvironmentObject var userVM: UserViewModel
    let email: String
    let purpose: Purpose
    @Binding var path: [AuthRoute]

    @State private var code = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var info: String?
    @State private var sentAt = Date()
    @State private var cooldown = 60
    @State private var shake = 0

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        AuthScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    AuthHeader(title: purpose == .signup ? "Check your email" : "Enter reset code",
                               subtitle: "We sent a 6-digit code to \(email). It can take a minute — check spam too.")

                    OTPCodeField(code: $code, hasError: error != nil)
                        .modifier(ShakeEffect(animatableData: CGFloat(shake)))
                        .onChange(of: code) { _, new in
                            error = nil
                            if new.count == 6 { verify() }
                        }

                    AuthMessage(error: error, info: info)

                    Button(action: verify) {
                        if isLoading { ProgressView().tint(.black) } else { Text("Verify") }
                    }
                    .buttonStyle(AuthPrimaryButtonStyle())
                    .disabled(isLoading || code.count < 6)

                    HStack {
                        Spacer()
                        if cooldown > 0 {
                            Text("Resend code in \(cooldown)s")
                                .foregroundStyle(.white.opacity(0.5))
                        } else {
                            Button("Didn't get it? Resend code", action: resend)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                }
                .padding(24)
            }
        }
        .onAppear {
            userVM.clearAuthMessages()
        }
        .onReceive(ticker) { _ in
            if cooldown > 0 { cooldown -= 1 }
        }
    }

    private func verify() {
        guard !isLoading, code.count == 6 else { return }
        isLoading = true
        error = nil
        info = nil
        Task {
            let ok: Bool
            switch purpose {
            case .signup:
                ok = await userVM.verifySignupOTP(email: email, otp: code, codeSentAt: sentAt)
            case .reset:
                ok = await userVM.verifyEmailOTP(email: email, otp: code, codeSentAt: sentAt)
                if ok { path.append(.newPassword) }
            }
            isLoading = false
            if !ok {
                error = userVM.errorMessage
                withAnimation(.default) { shake += 1 }
                code = ""
                ARHaptics.warning()
            }
        }
    }

    private func resend() {
        error = nil
        info = nil
        Task {
            let ok: Bool
            switch purpose {
            case .signup: ok = await userVM.resendSignupCode(email: email)
            case .reset: ok = await userVM.startResetPassword(email: email)
            }
            if ok {
                sentAt = Date()
                cooldown = 60
                code = ""
                info = "A new code is on its way. Older codes no longer work."
            } else {
                error = userVM.errorMessage
            }
        }
    }
}

// MARK: - Shared building blocks

enum AuthTheme {
    static var accent: LinearGradient {
        LinearGradient(colors: [Color(red: 0.55, green: 0.42, blue: 1.0),
                                Color(red: 1.0, green: 0.38, blue: 0.68),
                                Color(red: 0.25, green: 0.74, blue: 1.0)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

struct AuthScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.12),
                                    Color(red: 0.09, green: 0.05, blue: 0.20),
                                    Color(red: 0.02, green: 0.02, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle()
                .fill(Color.purple.opacity(0.35))
                .frame(width: 320)
                .blur(radius: 120)
                .offset(x: -140, y: -300)
                .ignoresSafeArea()
            Circle()
                .fill(Color.pink.opacity(0.22))
                .frame(width: 280)
                .blur(radius: 120)
                .offset(x: 160, y: 320)
                .ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct AuthHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct AuthField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType? = nil

    @State private var reveal = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)
            Group {
                if isSecure && !reveal {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                }
            }
            .textContentType(content)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(.white)
            if isSecure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel(reveal ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

struct AuthMessage: View {
    let error: String?
    let info: String?

    var body: some View {
        Group {
            if let error, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
            } else if let info, !info.isEmpty {
                Label(info, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.footnote.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: error)
    }
}

struct AuthPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AuthSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.18)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Six boxes over one hidden field — supports paste and iOS's
/// "From Messages/Mail" one-time-code autofill.
struct OTPCodeField: View {
    @Binding var code: String
    var hasError = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.02)
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { code = digits }
                }
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    let chars = Array(code)
                    let char = i < chars.count ? String(chars[i]) : ""
                    let active = focused && i == min(chars.count, 5)
                    Text(char)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(hasError ? Color.red.opacity(0.8)
                                              : (active ? Color.white : Color.white.opacity(0.15)),
                                              lineWidth: active || hasError ? 2 : 1)
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
        .accessibilityElement()
        .accessibilityLabel("Verification code, \(code.count) of 6 digits entered")
    }
}

struct PasswordStrengthBar: View {
    let password: String

    private var score: Int {
        var s = 0
        if password.count >= 8 { s += 1 }
        if password.count >= 12 { s += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { s += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil,
           password.rangeOfCharacter(from: .lowercaseLetters) != nil { s += 1 }
        if password.rangeOfCharacter(from: .punctuationCharacters.union(.symbols)) != nil { s += 1 }
        return min(s, 4)
    }

    var body: some View {
        if !password.isEmpty {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i < score ? color : Color.white.opacity(0.12))
                        .frame(height: 4)
                }
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    private var color: Color { [Color.red, .orange, .yellow, .green, .green][score] }
    private var label: String { ["Too short", "Weak", "Okay", "Good", "Strong"][score] }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Google's multicolour "G", drawn so we don't ship a bitmap.
struct GoogleGlyph: View {
    var body: some View {
        ZStack {
            Circle().trim(from: 0.0, to: 0.25).stroke(Color(red: 0.26, green: 0.52, blue: 0.96), lineWidth: 3.5)
            Circle().trim(from: 0.25, to: 0.5).stroke(Color(red: 0.20, green: 0.66, blue: 0.33), lineWidth: 3.5)
            Circle().trim(from: 0.5, to: 0.72).stroke(Color(red: 0.98, green: 0.74, blue: 0.02), lineWidth: 3.5)
            Circle().trim(from: 0.72, to: 0.97).stroke(Color(red: 0.92, green: 0.26, blue: 0.21), lineWidth: 3.5)
            Rectangle().fill(Color(red: 0.26, green: 0.52, blue: 0.96)).frame(width: 9, height: 3.5).offset(x: 4.5)
        }
        .padding(2)
    }
}

enum AuthNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    AuthStartView()
        .environmentObject(UserViewModel())
}
