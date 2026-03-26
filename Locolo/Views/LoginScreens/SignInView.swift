//
//  SignInView.swift
//  Locolo
//

import SwiftUI

struct SignInView: View {
    
    @EnvironmentObject var userVM: UserViewModel
    
    @State private var usernameOrEmail: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var isLoading = false
    
    @State private var navigateToSignUp = false
    @State private var navigateToMain = false
    
    // MARK: - Local error message (cleaned)
    @State private var localError: String? = nil
    
    var body: some View {
        
        NavigationStack {
            
            VStack(spacing: 32) {
                Spacer()
                
                // MARK: - Heading
                VStack(spacing: 10) {
                    Text("Sign In")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Welcome back, we missed you 👋")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
                
                
                // MARK: - Input Fields
                VStack(spacing: 20) {
                    
                    TextField("Email", text: $usernameOrEmail)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .disableAutocorrection(true)
                    
                    
                    HStack {
                        if isPasswordVisible {
                            TextField("Password", text: $password)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("Password", text: $password)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        Button { isPasswordVisible.toggle() } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                }
                .padding(.horizontal, 24)
                
                
                // MARK: - Sign In Button
                if isLoading {
                    ProgressView()
                } else {
                    Button("Sign In") {
                        Task {
                            
                            // Client-side validation BEFORE hitting Supabase
                            if usernameOrEmail.trimmingCharacters(in: .whitespaces).isEmpty ||
                                password.isEmpty {
                                localError = "Please enter both email and password."
                                return
                            }
                            
                            isLoading = true
                            
                            await userVM.login(
                                email: usernameOrEmail,
                                password: password
                            )
                            
                            // Clean error message
                            localError = cleanError(userVM.errorMessage)
                            
                            isLoading = false
                            
                            if userVM.isAuthenticated {
                                navigateToMain = true
                            }
                        }
                    }
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
                    .padding(.horizontal, 24)
                }
                
                
                // MARK: - Navigation Trigger
                NavigationLink(destination: MainView(), isActive: $navigateToMain) {
                    EmptyView()
                }
                .hidden()
                
                
                // MARK: - Cleaned Error
                if let err = localError, !err.isEmpty {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                
                // MARK: - Extra Actions
                VStack(spacing: 8) {
                    
                    NavigationLink("Forgot password?") {
                        ForgotPasswordEmailView()
                    }
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .medium))
                    
                    
                    HStack(spacing: 6) {
                        Text("Don’t have an account?")
                            .foregroundColor(.gray)
                        
                        NavigationLink(destination: SignUpUsernameView(),
                                       isActive: $navigateToSignUp) {
                            Button("Sign Up") {
                                navigateToSignUp = true
                            }
                            .foregroundColor(.purple)
                            .fontWeight(.bold)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    SignInView()
        .environmentObject(UserViewModel())
}


// MARK: - LOCAL ERROR CLEANER
private func cleanError(_ raw: String?) -> String? {
    guard let raw = raw else { return nil }
    let lower = raw.lowercased()

    if lower.contains("invalid login") {
        return "Incorrect email or password."
    }
    if lower.contains("invalid email") {
        return "Please enter a valid email address."
    }
    if lower.contains("network") || lower.contains("failed host lookup") {
        return "No internet connection. Please try again."
    }
    if lower.contains("expired") {
        return "This code has expired. Please request a new one."
    }
    if lower.contains("otp") || lower.contains("token is invalid") {
        return "Invalid OTP. Please try again."
    }

    return raw // fallback
}
