//
//  ForgotPasswordEmailView.swift
//  Locolo
//
//  Step 1 of password reset: email → 6-digit code (EmailCodeView .reset)
//  → NewPasswordView. Never creates accounts and never reveals whether an
//  address is registered.
//

import SwiftUI

struct ForgotPasswordEmailView: View {
    @EnvironmentObject var userVM: UserViewModel
    @Binding var path: [AuthRoute]

    @State private var email = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        AuthScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AuthHeader(title: "Reset password",
                               subtitle: "Enter your account email and we'll send you a 6-digit code.")
                    AuthField(icon: "envelope", placeholder: "Email", text: $email,
                              keyboard: .emailAddress, content: .emailAddress)
                        .submitLabel(.send)
                        .onSubmit(send)
                    AuthMessage(error: error, info: nil)
                    Button(action: send) {
                        if isSending { ProgressView().tint(.black) } else { Text("Send code") }
                    }
                    .buttonStyle(AuthPrimaryButtonStyle())
                    .disabled(isSending)
                }
                .padding(24)
            }
        }
        .onAppear {
            userVM.clearAuthMessages()
            error = nil
        }
        .onChange(of: email) { error = nil }
    }

    private func send() {
        guard !isSending else { return }
        isSending = true
        error = nil
        Task {
            let ok = await userVM.startResetPassword(email: email)
            isSending = false
            if ok {
                path.append(.verifyReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()))
            } else {
                error = userVM.errorMessage
            }
        }
    }
}
