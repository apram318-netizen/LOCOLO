//
//  OTPVerifyView.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/11/2025.
//

import SwiftUI

struct OTPVerifyView: View {
    
    let email: String
    
    @State private var otp = ""
    @State private var goToNewPassword = false
    @State private var localError: String?
    
    @EnvironmentObject var userVM: UserViewModel
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                
                Spacer()
                
                // MARK: - Heading
                VStack(spacing: 10) {
                    Text("Verify Code")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Enter the 6-digit code sent to \(email)")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // MARK: - OTP Field
                TextField("Enter OTP", text: $otp)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 24)
                
                // MARK: - Error Messages
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
                
                // MARK: - Verify Button
                Button {
                    Task {
                        localError = nil
                        userVM.errorMessage = nil
                        
                        guard otp.count == 6 else {
                            localError = "Please enter the 6-digit code."
                            return
                        }
                        
                        let ok = await userVM.verifyEmailOTP(email: email, otp: otp)
                        if ok {
                            goToNewPassword = true
                        }
                    }
                } label: {
                    Text("Verify")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .padding(.horizontal, 24)
                
                NavigationLink("", destination: NewPasswordView(), isActive: $goToNewPassword)
                    .hidden()
                
                Spacer()
            }
            .padding()
        }
    }
}
