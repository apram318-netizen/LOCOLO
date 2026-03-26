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
                VStack {
                    Spacer()
                    
                    Text("Locolo")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink, .blue],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                        .padding(.bottom, 16)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                        .scaleEffect(1.5)
                    
                    Text("Restoring your vibe...")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale))
                
            }
            else if userVM.isAuthenticated {
                MainView()
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



