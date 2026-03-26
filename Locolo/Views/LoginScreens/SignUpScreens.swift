//
//  SignUpScreens.swift
//  Locolo
//
//  Created by Apramjot Singh on 19/9/2025.
//

import SwiftUI

// A local inline error cleaner used by all signup screens.
// (Not inside ViewModel — does not touch backend logic)
private func cleanError(_ raw: String?) -> String? {
    guard let raw = raw else { return nil }
    let lower = raw.lowercased()

    if lower.contains("duplicate key") || lower.contains("already exists") {
        return "This email is already registered. Please sign in instead."
    }
    if lower.contains("invalid login") {
        return "Incorrect email or password."
    }
    if lower.contains("weak password") {
        return "Password is too weak. Please choose a stronger one."
    }
    if lower.contains("invalid email") {
        return "Please enter a valid email address."
    }
    if lower.contains("expired") {
        return "This code has expired. Request a new one."
    }
    if lower.contains("otp") || lower.contains("token is invalid") {
        return "Invalid OTP. Please try again."
    }
    if lower.contains("network") {
        return "No internet connection. Please try again."
    }
    if lower.contains("failed host lookup") {
        return "Cannot reach server. Check your connection."
    }

    return raw
}



struct SignUpUsernameView: View {
    @State private var username: String = ""
    @State private var dob = Date()
    @State private var navigateNext = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                Text("Create Account")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.pink, .purple],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Choose a username", text: $username)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .autocapitalization(.none)
                    
                    DatePicker("Date of Birth", selection: $dob, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                
                NavigationLink(
                    destination: SignUpEmailView(username: username),
                    isActive: $navigateNext
                ) {
                    Button("Next") { navigateNext = true }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.pink, .purple],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                        .cornerRadius(12)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding()
        }
    }
}


struct SignUpEmailView: View {
    @EnvironmentObject var userVM: UserViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var goToOTP = false
    @State private var isLoading = false
    
    let username: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Text("Create Account")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )

                VStack(spacing: 20) {
                    TextField("Email Address", text: $email)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)

                    SecureField("Password", text: $password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)

                // Error (cleaned)
                if let msg = cleanError(userVM.errorMessage) {
                    Text(msg)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                if isLoading {
                    ProgressView()
                } else {
                    Button("Sign Up") {
                        Task {
                            isLoading = true
                            let ok = await userVM.signUp(
                                email: email,
                                password: password,
                                username: username
                            )
                            isLoading = false
                            if ok { goToOTP = true }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(colors: [.blue, .purple],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                }

                NavigationLink("",
                    destination: SignUpOTPVerifyView(
                        email: email,
                        username: username,
                        password: password
                    ),
                    isActive: $goToOTP
                )
                .hidden()

                Spacer()
            }
            .padding()
        }
    }
}



struct SignUpPasswordView: View {
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var bio: String = ""
    @State private var avatarImage: UIImage?
    @EnvironmentObject var userVM: UserViewModel
    @State private var isLoading = false
    @State private var navigateToMain = false
    
    let email: String
    let username: String
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Text("Secure Your Account")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .blue],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )

                VStack(spacing: 20) {
                    SecureField("Password", text: $password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                    SecureField("Confirm Password", text: $confirmPassword)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                    TextField("Bio (optional)", text: $bio)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)

                if let msg = cleanError(userVM.errorMessage) {
                    Text(msg)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                if isLoading {
                    ProgressView()
                } else {
                    Button("Finish") {
                        Task {
                            isLoading = true
                            await userVM.signUp(
                                email: email,
                                password: password,
                                username: username
                            )
                            isLoading = false
                            if userVM.isAuthenticated { navigateToMain = true }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(colors: [.green, .blue],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .cornerRadius(12)
                    .foregroundColor(.white)
                }

                NavigationLink("",
                    destination: AuthStartView(),
                    isActive: $navigateToMain
                )
                .hidden()

                Spacer()
            }
            .padding()
        }
    }
}



struct SignUpOTPVerifyView: View {
    @EnvironmentObject var userVM: UserViewModel

    let email: String
    let username: String
    let password: String

    @State private var otp = ""
    @State private var isLoading = false
    @State private var navigateToMain = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()

                Text("Verify Your Email")
                    .font(.largeTitle.bold())

                Text("Enter the 6-digit code sent to \(email)")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                TextField("123456", text: $otp)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                // Cleaned error
                if let msg = cleanError(userVM.errorMessage) {
                    Text(msg)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                if isLoading {
                    ProgressView()
                } else {
                    Button("Verify & Continue") {
                        Task {
                            isLoading = true
                            let ok = await userVM.verifySignupOTP(email: email, otp: otp)
                            isLoading = false
                            if ok { navigateToMain = true }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(colors: [.purple, .pink],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .font(.headline)
                }

                NavigationLink("",
                               destination: MainView(),
                               isActive: $navigateToMain)
                    .hidden()

                Spacer()
            }
            .padding()
        }
    }
}
