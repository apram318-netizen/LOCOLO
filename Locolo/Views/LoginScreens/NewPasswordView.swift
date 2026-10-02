//
//  NewPasswordView.swift
//  Locolo
//
//  Final reset step. The verified code already signed the user in, so saving
//  the password drops them straight into the app (ContentView swaps roots).
//

import SwiftUI

struct NewPasswordView: View {
    @EnvironmentObject var userVM: UserViewModel

    @State private var pass = ""
    @State private var confirm = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        AuthScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AuthHeader(title: "New password", subtitle: "Choose something you haven't used before.")
                    VStack(alignment: .leading, spacing: 6) {
                        AuthField(icon: "lock", placeholder: "New password", text: $pass,
                                  isSecure: true, content: .newPassword)
                        PasswordStrengthBar(password: pass)
                    }
                    AuthField(icon: "lock.rotation", placeholder: "Confirm password", text: $confirm,
                              isSecure: true, content: .newPassword)
                    AuthMessage(error: error, info: nil)
                    Button(action: save) {
                        if isSaving { ProgressView().tint(.black) } else { Text("Save and continue") }
                    }
                    .buttonStyle(AuthPrimaryButtonStyle())
                    .disabled(isSaving)
                }
                .padding(24)
            }
        }
        .navigationBarBackButtonHidden(isSaving)
        .onAppear { userVM.clearAuthMessages() }
    }

    private func save() {
        error = nil
        guard pass.count >= 8 else { error = "Use at least 8 characters."; return }
        guard pass == confirm else { error = "Passwords don't match."; return }
        isSaving = true
        Task {
            let ok = await userVM.updatePassword(to: pass)
            isSaving = false
            if !ok { error = userVM.errorMessage }
        }
    }
}
