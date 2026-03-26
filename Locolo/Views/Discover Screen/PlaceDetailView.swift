//
//  PlaceDetailView.swift
//  Locolo
//
//  Created by Apramjot Singh on 3/10/2025.
//


import SwiftUI
import Foundation


struct PlaceDetailView: View {
    let place: DiscoverPlace

    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var createPostVM: CreatePostViewModel
    @EnvironmentObject var locationVM: LocationViewModel

    @StateObject private var vm = PlaceDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                
                AsyncImage(url: URL(string: place.image)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(height: 200)
                .clipped()
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 8) {
                    Text(place.name)
                        .font(.title).bold()

                    Text(place.type)
                        .font(.headline).foregroundColor(.secondary)

                    Label("\(place.hypes) hypes", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)

                    Divider()

                    Text(place.description)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal)

                // MARK: Posts Section
                if vm.isLoading {
                    ProgressView("Loading posts…").padding()
                } else if let error = vm.errorMessage {
                    Text(error).foregroundColor(.red).padding()
                } else if vm.posts.isEmpty {
                    Text("No posts yet for this place.")
                        .foregroundColor(.gray)
                        .padding()
                } else {

                    Divider()
                    Text("Posts from this spot 📍")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 20) {

                        ForEach(vm.posts) { post in
                            
                            FeedCell(
                                post: post,
                                selectedPost: .constant(nil),
                                currentUserId: userVM.currentUser?.id ?? UUID()
                            )
                            
                        }

                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top)
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.loadPosts(for: place.id)
        }
    }
}
