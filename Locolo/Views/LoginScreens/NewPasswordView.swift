//
//  NewPasswordView.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/11/2025.
//

import SwiftUI

struct NewPasswordView: View {
    
    @State private var pass = ""
    @State private var confirm = ""
    @State private var done = false
    @State private var localError: String?
    
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                
                Spacer()
                
                // MARK: - Heading
                VStack(spacing: 10) {
                    Text("Create New Password")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Choose a strong password to keep your account secure 🔐")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // MARK: - Input Fields
                VStack(spacing: 20) {

                    SecureField("New Password", text: $pass)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("Confirm Password", text: $confirm)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 24)
                
                // MARK: - Button
                Button {
                    Task {
                        localError = nil
                        userVM.errorMessage = nil
                        
                        guard pass.count >= 6 else {
                            localError = "Password must be at least 6 characters."
                            return
                        }
                        guard pass == confirm else {
                            localError = "Passwords do not match."
                            return
                        }
                        
                        let ok = await userVM.updatePassword(to: pass)
                        if ok { done = true }
                    }
                } label: {
                    Text("Save Password")
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
                
                // MARK: - Errors
                if let err = localError {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let globalErr = userVM.errorMessage {
                    Text(globalErr)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // MARK: - Success
                if done {
                    VStack(spacing: 8) {
                        Text("Password updated! 🎉")
                            .foregroundColor(.green)
                            .font(.system(size: 16, weight: .medium))
                        
                        Button("Back to Login") { dismiss() }
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
}
