//
//  ContentView.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/9/2025.
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    
    
    @EnvironmentObject var userVM: UserViewModel
    @State private var isRestoring = true
    private let placesRepo = PlacesRepository()
    private let locationRepo = LocationsRepository()
    
    var body: some View {
        Group {
            if isRestoring {
                LaunchScreen()
                    .transition(.opacity)
            }
            else if userVM.isAuthenticated {
                // Standalone AR-only app (WS0): the AR module is the whole
                // experience once signed in. MainView / the legacy tab shell
                // stays in the repo but is no longer on the boot path.
                ARAppRootView()
            } else {
                AuthStartView()
            }
        }
        .task {
            await userVM.restoreSession()
            await signInFirebaseIfNeeded()
            
            //  Ensure Supabase ID is ready before reconciling
            if let id = SupabaseManager.shared.currentUserId {
                
                LocationManager.shared.startTracking()

                print(" Restored Supabase session for \(id)")

                await LocationUploader.shared.reconcileIfNeeded()

                // Publish this device's chat public key so peers can encrypt
                // to us (E2E chat, WS6). Idempotent — only writes if changed.
                if let uid = UUID(uuidString: id) {
                    await KeyDirectory.shared.publishMyKey(userId: uid)
                }

            } else {
                print(" Skipping reconciliation — Supabase ID not ready yet")
            }
            
            withAnimation {
                isRestoring = false
            }
        }
    }
    
    private func signInFirebaseIfNeeded() async {
        if Auth.auth().currentUser == nil {
            do {
                let _ = try await Auth.auth().signInAnonymously()
                print(" Signed in to Firebase anonymously.")
            } catch {
                print(" Firebase anonymous sign-in failed:", error)
            }
        } else {

            print(" Firebase already signed in:", Auth.auth().currentUser?.uid ?? "")
        }
    }


}


// MARK: - Launch screen

/// Polished first-impression splash: soft brand glow behind a breathing
/// LOCOLO wordmark, a tagline, and a slim progress indicator.
private struct LaunchScreen: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()

            // Soft radial brand glow.
            RadialGradient(
                colors: [Color.purple.opacity(0.28), Color.pink.opacity(0.10), .clear],
                center: .center, startRadius: 8, endRadius: 320
            )
            .ignoresSafeArea()
            .blur(radius: 12)

            VStack(spacing: 14) {
                LocoloWordmark(size: 46)
                    .scaleEffect(appear ? 1.0 : 0.94)
                    .opacity(appear ? 1 : 0.6)

                Text("Your world, in AR")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.purple)
                    .padding(.top, 10)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                appear = true
            }
        }
    }
}



