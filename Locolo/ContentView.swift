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
            // ONLY session restore gates the launch screen. Everything else used
            // to run serially here — Firebase sign-in (which waits on an edge
            // function round trip), residency reconciliation (potentially
            // thousands of RPC calls) and key publishing — so cold start took as
            // long as the slowest of them. They're all fire-and-forget now.
            await userVM.restoreSession()

            withAnimation { isRestoring = false }

            // --- background warm-up, never blocks first paint ---
            Task.detached(priority: .utility) {
                await signInFirebaseIfNeeded()
            }

            guard let id = SupabaseManager.shared.currentUserId else { return }

            LocationManager.shared.startTracking()

            Task.detached(priority: .utility) {
                // Heavy: reads location history and resolves loops. Deferred so
                // it can never delay the UI.
                await LocationUploader.shared.reconcileIfNeeded()
            }

            if let uid = UUID(uuidString: id) {
                Task.detached(priority: .utility) {
                    // Publish this device's chat public key so peers can encrypt
                    // to us (E2E chat, WS6). Idempotent — only writes if changed.
                    await KeyDirectory.shared.publishMyKey(userId: uid)
                }
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
            var request = try await EdgeFunctions.request("firebase-custom-token", body: [String: String]())
            // The function is a 503 stub until the service account is set, and
            // URLSession's default timeout is 60s — cap it so the anonymous
            // fallback happens quickly instead of hanging the chat session.
            request.timeoutInterval = 8
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



