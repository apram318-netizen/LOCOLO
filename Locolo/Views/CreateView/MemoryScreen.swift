//
//  MemoryScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 22/9/2025.
//


import SwiftUI
import PhotosUI
import CoreLocation

struct MemoryScreen: View {
    // MARK: Memory State
    @State private var memoryText: String = ""
    @State private var isAtLocation: Bool = true  // TODO(LOCOLO): Implement CoreLocation check to verify user is at place
    @State private var privacyDelay: String = "Now"
    
    let onNext: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Header Section
                Text("Drop a memory ✨")
                    .font(.title2).bold()
                
                // MARK: Live Photo Section
                if isAtLocation {
                    Text("Looks like you’re right here! Snap a live pic to earn the 🔥 tag.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        // TODO(LOCOLO): Implement live camera capture for freshdrop tag | Status: Uncompleted
                    }) {
                        Label("Take Live Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                
                // MARK: Memory Text Input
                TextEditor(text: $memoryText)
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
                    .padding(.top)
                
                // MARK: Privacy Settings Section
                Text("When should this place go public?")
                    .font(.headline)
                
                Picker("Privacy Delay", selection: $privacyDelay) {
                    Text("Now").tag("Now")
                    Text("In 1 Hour").tag("1h")
                    Text("In 1 Day").tag("1d")
                    Text("Keep Private").tag("private")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Spacer()
                
                // MARK: Next Button
                Button(action: {
                    // TODO(LOCOLO): Save memory text and privacy settings to draft state | Status: Uncompleted
                    onNext()
                }) {
                    Text("Next 🚀")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("Memory & Privacy")
    }
}
