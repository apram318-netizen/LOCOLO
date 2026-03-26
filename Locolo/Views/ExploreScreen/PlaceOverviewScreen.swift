//
//  PlaceOverviewScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 10/10/2025.
//

import SwiftUI

struct PlaceOverviewScreen: View {
    let place: Place

    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var placeVM: PlaceViewModel
    @EnvironmentObject var createPostVM: CreatePostViewModel
    
    @State private var selectedPost: Post?

    @StateObject private var vm = PlaceDetailViewModel()

    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Header Image
                    AsyncImage(url: URL(string: place.placeImageUrl ?? "")) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(height: 260)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.6), .clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name)
                                .font(.largeTitle.bold())
                                .foregroundColor(.white)
                            if let cat = place.categoryId {
                                Text("Category: \(cat.uuidString.prefix(8))…")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding()
                    }

                    // MARK: - Description
                    if let desc = place.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("About this place", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(desc)
                                .font(.body)
                                .foregroundColor(AppColors.primaryText)
                        }
                        .padding(.horizontal)
                    }

                    Divider().padding(.vertical, 8)

                    // MARK: - Posts from this place
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Posts from this spot 📍")
                            .font(.headline)
                            .padding(.horizontal)

                        if vm.isLoading {
                            ProgressView("Loading posts…")
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if let error = vm.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .padding()
                        } else if vm.posts.isEmpty {
                            Text("No posts yet from this place.")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            LazyVStack(spacing: 24) {
                                ForEach(vm.posts) { post in
                                    
                                    FeedCell(
                                        post: post,
                                        selectedPost: $selectedPost,
                                        currentUserId: userVM.currentUser?.id ?? UUID()
                                    )
                                    .environmentObject(userVM)
                                    
                                }
                            }
                            .padding(.bottom, 40)
                        }
                    }
                }
                .padding(.top)
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.loadPosts(for: place.id)
        }
    }
}

