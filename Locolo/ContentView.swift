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
        .onOpenURL { url in
            DeepLinkRouter.shared.handle(url)
        }
        .onChange(of: userVM.isAuthenticated) { _, authenticated in
            // The Firebase chat session must follow the Supabase one: otherwise
            // the next person to sign in on this device inherits the previous
            // Firestore identity.
            if authenticated {
                Task { await signInFirebaseIfNeeded() }
            } else {
                do { try Auth.auth().signOut() }
                catch { print(" Firebase signOut failed:", error) }
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
        // Prefer Firebase custom token bound to Supabase uid (§5.8). Fall back
        // to anonymous when the edge fn isn't deployed / secret missing.
        if let token = await fetchFirebaseCustomToken() {
            do {
                _ = try await Auth.auth().signIn(withCustomToken: token)
                LocoloLog.chat.info("Firebase custom-token sign-in ok")
                return
            } catch {
                LocoloAnalytics.record(error: error, context: "firebase_custom_token")
            }
        }
        if Auth.auth().currentUser == nil {
            do {
                _ = try await Auth.auth().signInAnonymously()
                LocoloLog.chat.info("Firebase anonymous sign-in (custom token unavailable)")
            } catch {
                LocoloAnalytics.record(error: error, context: "firebase_anonymous")
            }
        }
    }

    private struct TokenResponse: Decodable {
        let token: String?
        let stub: Bool?
    }

    private func fetchFirebaseCustomToken() async -> String? {
        guard SupabaseManager.shared.currentUserId != nil else { return nil }
        do {
            let request = try await EdgeFunctions.request("firebase-custom-token", body: [String: String]())
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let parsed = try JSONDecoder().decode(TokenResponse.self, from: data)
            return parsed.token
        } catch {
            return nil
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



