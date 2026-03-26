//
//  PreviewScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 22/9/2025.
//

import SwiftUI
import PhotosUI
import CoreLocation

struct PreviewScreen: View {
    
    @EnvironmentObject var createPostVM: CreatePostViewModel
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var loopVM: LoopViewModel
    
    @State private var isPosting = false
    @State private var showSuccessAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Preview Post")
                    .font(.largeTitle.bold())
                    .padding(.top)
                // MARK: Post Preview Section
                // Shows either place post preview or regular post preview based on selection
                Group {
                    if let selectedPlace = createPostVM.selectedPlace {
                        
                        if let previewPost = createPreviewPost(forPlace: selectedPlace) {
                            VerticalPlacePostView(
                                post: previewPost,
                                place: selectedPlace,
                                isPreview: true, currentUserId: userVM.currentUser?.id ?? UUID()
                            )
                            .padding(.horizontal)
                        } else {
                            emptyState
                        }
                    } else {
                        
                        if let previewPost = createPreviewPost() {
                            PostPreviewCell(createPostVM: createPostVM)
                                .padding(.horizontal)
                        } else {
                            emptyState
                        }
                    }
                }
                
                Divider().padding(.vertical, 10)
                // MARK: Post Action Button
                // Shows progress indicator during upload or post button when ready
                if createPostVM.isUploading || isPosting {
                    ProgressView("Posting...")
                        .padding()
                } else {
                    Button {
                        Task { await publishPost() }
                    } label: {
                        Text("Post Now 🚀")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(colors: [.pink, .purple],
                                               startPoint: .leading,
                                               endPoint: .trailing)
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                
                if let error = createPostVM.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 50)
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Posted Successfully!", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {
                createPostVM.reset()
            }
        }
    }
}

// MARK: Helper Builders
extension PreviewScreen {
    // MARK: Preview Post Creation
    // Creates a preview Post object without location attachment for display
    private func createPreviewPost() -> Post? {
        guard let currentUser = userVM.currentUser else { return nil }
        
        return Post(
            id: UUID(),
            loopId: UUID(uuidString: loopVM.activeLoop?.id ?? "") ?? UUID(),
            authorId: currentUser.id,
            caption: createPostVM.description,
            media: createPostVM.uploadedMemoryURLs.first,
            placeMedia: nil,
            realMemoryMedia: createPostVM.uploadedDigitalMemoryURL,
            tags: createPostVM.tags,
            placeId: nil,
            visibility: "public",
            isDeleted: false,
            createdAt: Date(),
            updatedAt: nil,
            author: nil,
            place: nil,
            eventId: nil,
            eventContext: nil
        )
    }
    // MARK: Place Post Preview Creation
    // Creates a preview Post object with location attachment for display
    private func createPreviewPost(forPlace place: Place) -> Post? {
        guard let currentUser = userVM.currentUser else { return nil }
        
        return Post(
            id: UUID(),
            loopId: UUID(uuidString: loopVM.activeLoop?.id ?? "") ?? UUID(),
            authorId: currentUser.id,
            caption: createPostVM.description,
            media: createPostVM.uploadedMemoryURLs.first,
            placeMedia: createPostVM.uploadedPlaceURL,
            realMemoryMedia: createPostVM.uploadedDigitalMemoryURL,
            tags: createPostVM.tags,
            placeId: place.id,
            visibility: "public",
            isDeleted: false,
            createdAt: Date(),
            updatedAt: nil,
            author: Post.Author(
                            username: currentUser.username,
                            avatarUrl: currentUser.avatarUrl, loopTimeCounters: nil ),
            place: place,
            eventId: nil,
            eventContext: nil
        )
    }
    // MARK: Empty State View
    // Fallback view shown when there is nothing to preview
    private var emptyState: some View {
        VStack {
            Image(systemName: "eye.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text("Nothing to preview yet ")
                .foregroundColor(.secondary)
        }
        .padding(.top, 40)
    }
    // MARK: Publishing Logic
    // Calls view model publish method and shows success alert when complete
    private func publishPost() async {
        isPosting = true
        await createPostVM.publish()
        await MainActor.run {
            isPosting = false
            if createPostVM.isPosted && createPostVM.errorMessage == nil {
                showSuccessAlert = true
            }
        }
    }
}



struct PostPreviewCell: View {
    @ObservedObject var createPostVM: CreatePostViewModel
    @EnvironmentObject var userVM: UserViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: Header Section
            // Shows user avatar, username, and timestamp
            HStack {
                // User Avatar
                if let avatarURL = userVM.currentUser?.avatarUrl {
                    AsyncImage(url: avatarURL) { image in
                        image.resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 40)
                    }
                } else {
                    Circle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 40)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(userVM.currentUser?.username ?? "You")
                        .bold()
                    if let place = createPostVM.selectedPlace {
                        Text(place.name)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                Text("Now")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            // MARK: Memory Images Section
            // TabView carousel displaying all memory images if any exist
            if !createPostVM.memoryImages.isEmpty {
                TabView {
                    ForEach(createPostVM.memoryImages, id: \.self) { image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipped()
                            .cornerRadius(14)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                .frame(height: 220)
            }
            // MARK: Caption Section
            // Displays post caption text if available
            if !createPostVM.description.isEmpty {
                Text(createPostVM.description)
                    .font(.body)
                    .padding(.top, 4)
            }
            // MARK: Tags Section
            // Horizontal scrolling list of post tags
            if !createPostVM.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(createPostVM.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            // MARK: Place Image Section
            // Optional place image shown when post is attached to a location
            if let placeImage = createPostVM.placeImage {
                Image(uiImage: placeImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()
                    .cornerRadius(12)
            }
        }
        .padding()
    }
}



