//
//  PostDetailView.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/11/2025.
//


import SwiftUI

struct PostDetailView: View {
    let post: Post
    
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var placeVM: PlaceViewModel
    @EnvironmentObject var createPostVM: CreatePostViewModel
    @EnvironmentObject var locationVM: LocationViewModel
    
    // MARK: View State
    // State for FeedCell binding (not used for navigation, just required)
    @State private var selectedPost: Post? = nil
    @State private var currentUserId: UUID
    
    init(post: Post) {
        self.post = post
        // Initialize with placeholder, will be set properly on appear
        _currentUserId = State(initialValue: UUID())
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                
                // MARK: Conditional Content
                // Shows VerticalPlacePostView if place exists, otherwise FeedCell
                if let place = post.place {
                    VerticalPlacePostView(
                        post: post,
                        place: place,
                        isPreview: false,
                        currentUserId: currentUserId
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    
                } else {
                    FeedCell(
                        post: post,
                        selectedPost: $selectedPost,
                        currentUserId: currentUserId
                    )
                    .environmentObject(userVM)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Post")
        .onAppear {
            // Set current user ID when view appears
            if let userId = userVM.currentUser?.id {
                currentUserId = userId
            }
        }
    }
}
