//
//  ForgotPasswordEmailView.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/11/2025.
//

import SwiftUI

struct ForgotPasswordEmailView: View {
    
    @State private var email = ""
    @State private var isSending = false
    @State private var goToOTP = false
    @State private var localError: String?
    
    @EnvironmentObject var userVM: UserViewModel
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                
                Spacer()
                
                // MARK: - Header
                VStack(spacing: 10) {
                    Text("Reset Password")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Enter your email to receive a one-time password (OTP)")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // MARK: - Email Field
                TextField("Email", text: $email)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding(.horizontal, 24)
                
                // MARK: - Errors
                if let err = localError {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                if let globalError = userVM.errorMessage {
                    Text(globalError)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                // MARK: - Button
                Button {
                    Task {
                        localError = nil
                        userVM.errorMessage = nil
                        
                        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        guard !trimmed.isEmpty else {
                            localError = "Please enter an email."
                            return
                        }
                        
                        guard trimmed.contains("@") && trimmed.contains(".") else {
                            localError = "Please enter a valid email address."
                            return
                        }
                        
                        isSending = true
                        let ok = await userVM.startResetPassword(email: trimmed)
                        isSending = false
                        
                        if ok { goToOTP = true }
                    }
                } label: {
                    Text(isSending ? "Sending..." : "Send OTP")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.blue, .purple],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .padding(.horizontal, 24)
                
                NavigationLink("", destination: OTPVerifyView(email: email), isActive: $goToOTP)
                    .hidden()
                
                Spacer()
            }
            .padding()
            .onAppear {
                localError = nil
                userVM.errorMessage = nil
            }
        }
    }
}
