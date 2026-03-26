//
//  FeedView.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import SwiftUI
import CoreLocation




struct FeedView: View {
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var userVM: UserViewModel

    // MARK: Navigation State
    // Shared navigation path for Feed to Conversations to Chat navigation flow
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // MARK: Top Bar Section
                // Header with app title and navigation buttons for notifications and messages
                HStack {
                    Text("Locolo")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 16) {
                        
                        Button {
                            //  Navigate to conversation list
                            path.append("notifications")
                        } label: {
                            Image(systemName: "bell")
                        }
                        
                        Button {
                            //  Navigate to conversation list
                            path.append("conversations")
                        } label: {
                            Image(systemName: "envelope")
                        }
                    }
                    .font(.title3)
                }
                .padding()
                // MARK: Loops Section
                // Shows expanded or compact view of user loops based on state
                if loopVM.expanded {
                    LoopsExpandedView()
                } else {
                    LoopsCompactView()
                }

                Spacer(minLength: 12)
                Divider()
                Spacer(minLength: 12)
                // MARK: Content Section
                // Scrollable feed displaying posts from the active loop
                if let activeLoop = loopVM.activeLoop {
                    LoopExploreContent(loopVM: loopVM, userVM: userVM)
                        .id(activeLoop.id)
                } else {
                    Text("Select a loop to explore")
                        .foregroundColor(.gray)
                        .padding()
                }
            }
            // MARK: - Navigation destinations
            .navigationDestination(for: String.self) { value in
                if value == "conversations" {
                    //  Conversation list
                    if let currentUser = userVM.currentUser {
                        ConversationListView(
                            currentUserId: currentUser.id.uuidString.lowercased(),
                            currentUserName: currentUser.name ?? "",
                            path: $path
                        )
                    } else {
                        Text("User not logged in")
                    }
                }else if value == "notifications" {
                    
                    if let currentUser = userVM.currentUser {
                        NotificationCenterScreen(
                            vm: NotificationViewModel(
                                userId: currentUser.id.uuidString.lowercased()
                            )
                        )
                    } else {
                        Text("User not logged in")
                    }
                    
                    
                }
                else {
                    //  Chat destination (value is a conversationId)
                    if let currentUser = userVM.currentUser {
                        ChatView(
                            vm: ChatViewModel(conversationId: value, userId: currentUser.id.uuidString.lowercased()),
                            currentUserId: currentUser.id.uuidString.lowercased(),
                            currentUserName: currentUser.name ?? ""
                        )
                    } else {
                        Text("User not logged in")
                    }
                }
            }
        }
    }
}

struct LoopExploreContent: View {
    var loopVM: LoopViewModel
    var userVM: UserViewModel
    
    @StateObject private var vm: ExplorePostsViewModel
    
    @EnvironmentObject var placeVM: PlaceViewModel
    
    init(loopVM: LoopViewModel, userVM: UserViewModel) {
        self.loopVM = loopVM
        self.userVM = userVM
        _vm = StateObject(wrappedValue: ExplorePostsViewModel(loopViewModel: loopVM, userViewModel: userVM))
    }
    
    var body: some View {
        // MARK: Posts Feed Section
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.posts) { post in
                        // Check for event announcement posts first
                        if let eventId = post.eventId,
                           post.eventContext == "event_announcement" {
                            // Full-width event posts (no padding)
                            EventPostWrapper(
                                post: post,
                                selectedPost: $vm.selectedPost,
                                currentUserId: userVM.currentUser?.id ?? UUID()
                            )
                            .padding(.bottom, 20)
                        } else if let place = post.place {
                            //LocationPostWrapper(post: post, placeId: placeId, userVM: userVM)
                            VerticalPlacePostView(post: post, place: place , isPreview: false, currentUserId:userVM.currentUser?.id ?? UUID() )
                                .padding(.horizontal)
                                .padding(.bottom, 20)
                        } else {
                            FeedCell(
                                post: post,
                                selectedPost: $vm.selectedPost,
                                currentUserId: userVM.currentUser?.id ?? UUID()
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                        }
                    }
                }
                
            }
            
            .onAppear {
                vm.loadPosts()
            }
        }
    }
}




struct LocationPostWrapper: View {
    let post: Post
    let placeId: UUID
    @ObservedObject var userVM: UserViewModel
    
    @StateObject private var placeVM = PlaceViewModel()
    @State private var place: Place?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let place = place {
                VerticalPlacePostView(post: post, place: place, isPreview: false, currentUserId: userVM.currentUser?.id ?? UUID())
                
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // Fallback: If fetching fails, fall back to standard post
                FeedCell(
                    post: post,
                    selectedPost: .constant(nil),
                    currentUserId: userVM.currentUser?.id ?? UUID()
                )
            }
        }
        
        .task {
            await fetchPlace()
        }
    }
    
    private func fetchPlace() async {
        guard let fetched = await placeVM.getPlace(by: placeId) else {
            isLoading = false
            return
        }
        self.place = fetched
        isLoading = false
    }
}
