//
//  AuthStartView.swift
//  Locolo
//
//  Created by Apramjot Singh on 19/9/2025.
//


import SwiftUI

struct AuthStartView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                
                // MARK: Header Section
                VStack(spacing: 12) {
                    Text("Welcome to")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    Text("Locolo")
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink, .blue],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                    
                    Text("Your city, your vibe 🌍✨")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // MARK: Action Buttons Section
                // Buttons
                VStack(spacing: 20) {
                    NavigationLink(destination: SignInView()) {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(colors: [.blue, .purple],
                                               startPoint: .leading,
                                               endPoint: .trailing)
                            )
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    
                    NavigationLink(destination: SignUpUsernameView()) {
                        Text("Sign Up")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .foregroundColor(.primary)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    AuthStartView()
}
