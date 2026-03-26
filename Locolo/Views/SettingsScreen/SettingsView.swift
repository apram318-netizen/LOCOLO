//
//  SettingsView.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/11/2025.
//


import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) private var dismiss
    
    // MARK: View State
    @State private var showLogoutConfirm = false
    @State private var isLoggingOut = false
    
    var body: some View {
        NavigationStack {
            // MARK: Settings List
            List {
                
                // MARK: - PROFILE
                Section(header: Text("Profile")) {
                    NavigationLink {
                        EditProfileView()
                    } label: {
                        Label("Edit Profile", systemImage: "person.crop.circle")
                    }
                    
                }
                
                
                // MARK: - PRIVACY
                Section(header: Text("About")) {
                    NavigationLink {
                        LicensesAndAttributionsView()
                    } label: {
                        Label("Licenses & Attributions", systemImage: "doc.text")
                    }
                }
                
                
                // MARK: - LOGOUT
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log Out")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Log out?", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Log Out", role: .destructive) { performLogout() }
            } message: {
                Text("You will be signed out of Locolo.")
            }
        }
    }
    
    
    // MARK: - LOGOUT HANDLER
    private func performLogout() {
        isLoggingOut = true
        Task {
            await userVM.logout()
            isLoggingOut = false
        }
    }
}


