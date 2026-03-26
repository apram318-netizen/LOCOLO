//
//  HomeView.swift
//  Locolo
//
//  Created by Apramjot Singh on 15/10/2025.
//


import SwiftUI

struct HomeView: View {
    @State private var showMessages = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                //  Top Bar
                HStack {
                    Text("Home")
                        .font(.title2.bold())
                    Spacer()
                    Button(action: {
                        // Settings
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                    }
                    .padding(.horizontal, 6)

                    Button(action: {
                        // Notifications
                    }) {
                        Image(systemName: "bell.fill")
                            .font(.title3)
                    }
                    .padding(.horizontal, 6)

                    Button(action: {
                        showMessages = true
                    }) {
                        Image(systemName: "envelope.fill")
                            .font(.title3)
                    }
                    .padding(.horizontal, 6)
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [.purple.opacity(0.4), .blue.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                Spacer()
            }
            .background(
                LinearGradient(
                    colors: [.black, .purple.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationDestination(isPresented: $showMessages) {
                MessagesScreen()
            }
        }
    }
}


struct TopBarView: View {
    var title: String
    var onSettingsTap: (() -> Void)?
    var onNotificationsTap: (() -> Void)?
    var onMessagesTap: (() -> Void)?
    
    var body: some View {
        HStack {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: { onSettingsTap?() }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
            }
            .padding(.horizontal, 6)
            
            Button(action: { onNotificationsTap?() }) {
                Image(systemName: "bell.fill")
                    .font(.title3)
            }
            .padding(.horizontal, 6)
            
            Button(action: { onMessagesTap?() }) {
                Image(systemName: "envelope.fill")
                    .font(.title3)
            }
            .padding(.horizontal, 6)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.4), .blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
