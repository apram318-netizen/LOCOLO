//
//  LoopCreationView.swift
//  Locolo
//
//  Created by Apramjot Singh on 6/11/2025.
//

import SwiftUI
import MapKit
import PhotosUI

struct LoopCreationView: View {
    @EnvironmentObject var loopVM: LoopViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var isSearchFocused: Bool
    @State private var showDetailsScreen = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                if loopVM.selectedCreationType != nil {
                    Button("Back") {
                        withAnimation { loopVM.selectedCreationType = nil }
                    }
                    .foregroundColor(.gray)
                }

                Spacer()
                Text("Create New Loop")
                    .font(.headline)
                Spacer()

                if loopVM.selectedCreationType != nil {
                    Button("Next") {
                        showDetailsScreen = true
                    }
                    .bold()
                    .disabled(loopVM.loopBoundaryPolygon == nil)
                    .foregroundColor(loopVM.loopBoundaryPolygon == nil ? .gray : .blue)
                } else {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // MARK: Step 1 - Choose Type
            if loopVM.selectedCreationType == nil {
                VStack(spacing: 24) {
                    Text("Select Loop Type")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.top, 60)

                    Button {
                        loopVM.selectedCreationType = .university
                    } label: {
                        Text("🎓 University Loop")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(12)
                    }

                    Button {
                        loopVM.selectedCreationType = .regional
                    } label: {
                        Text("📍 Regional Loop")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 40)
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            } else {
                // MARK: Step 2 - Search + Map
                VStack(alignment: .leading, spacing: 12) {
                    // Loop Type Indicator
                    HStack {
                        Text(loopVM.selectedCreationType == .university ? "🎓 University Loop" : "📍 Regional Loop")
                            .font(.headline)
                        Spacer()
                    }

                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField(loopVM.selectedCreationType == .university ? "Search universities..." : "Search regions...",
                                  text: $loopVM.locationSearchQuery)
                            .focused($isSearchFocused)
                            .onChange(of: loopVM.locationSearchQuery) { _ in
                                loopVM.searchLocations()
                            }
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // MARK: Search Results Dropdown (Dynamic Height)
                if !loopVM.locationResults.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(loopVM.locationResults, id: \.self) { item in
                                Button {
                                    loopVM.selectLocation(item)
                                    if let name = item.name {
                                        Task { await loopVM.fetchLoopBoundary(for: name) }
                                    }
                                    hideKeyboard()
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name ?? "Unknown")
                                            .font(.body)
                                        Text(item.placemark.title ?? "")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Divider()
                            }
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(radius: 3)
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: min(CGFloat(loopVM.locationResults.count) * 52, 260)) // adaptive height
                }

                // MARK: Map (Full height)
                CustomMapView(region: $loopVM.mapRegion, overlay: loopVM.loopBoundaryPolygon)
                    .ignoresSafeArea(edges: .bottom)
                    .frame(maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showDetailsScreen) {
            LoopDetailsView()
                .environmentObject(loopVM)
        }
        .onDisappear { loopVM.resetCreationState() }
        .animation(.easeInOut, value: loopVM.selectedCreationType)
    }

    // Helper to dismiss keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        isSearchFocused = false
    }
}



// MARK: - Step 2: Details Screen

struct LoopDetailsView: View {
    @EnvironmentObject var loopVM: LoopViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Cover image
                VStack {
                    if let image = loopVM.newLoopCoverImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .cornerRadius(12)
                            .clipped()
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    loopVM.newLoopCoverImage = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.4))
                                        .clipShape(Circle())
                                        .padding(8)
                                }
                            }
                    } else {
                        // Built-in PhotosPicker button
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            VStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text("Add Cover Image")
                                    .font(.callout)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .onChange(of: selectedItem) { newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    loopVM.newLoopCoverImage = uiImage
                                }
                            }
                        }
                    }
                }

                // Name
                TextField("Loop name", text: $loopVM.newLoopName)
                    .textFieldStyle(.roundedBorder)

                // Description
                TextField("Description (optional)", text: $loopVM.newLoopDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                // Create button
                Button {
                    Task { await loopVM.submitLoopCreation() }
                } label: {
                    HStack {
                        if loopVM.isSavingLoop { ProgressView() }
                        Text(loopVM.isSavingLoop ? "Creating..." : "Create Loop")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(loopVM.isSavingLoop ||
                                (loopVM.newLoopName.trimmingCharacters(in: .whitespaces).isEmpty &&
                                 loopVM.newLoopCoverImage == nil)
                                ? Color.gray.opacity(0.4)
                                : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(loopVM.isSavingLoop ||
                          (loopVM.newLoopName.trimmingCharacters(in: .whitespaces).isEmpty &&
                           loopVM.newLoopCoverImage == nil))
            }
            .padding()
            .navigationTitle("Loop Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
