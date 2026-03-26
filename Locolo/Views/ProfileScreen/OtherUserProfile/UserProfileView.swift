//
//  UserProfileView.swift
//  Locolo
//
//  Created by Apramjot Singh on 13/11/2025.
//


import SwiftUI
import MapKit

// MARK: - Chat Sheet Item
// Wrapper struct for presenting ChatView in a sheet
struct ChatSheetItem: Identifiable {
    let id: String
    let viewModel: ChatViewModel
}

struct UserProfileView: View {
    let userId: UUID

    @EnvironmentObject var userVM: UserViewModel
    @StateObject private var vm = ProfileViewModel()

    @State private var viewedUser: User?
    @State private var isLoadingUser = true
    @State private var selectedTab = 0
    @State private var postGridMode = true
    @State private var placesListMode = true

    // follow state placeholder (wire to your follow API when ready)
    @State private var isFollowing = false
    @State private var isWorking = false
    
    // MARK: Chat Navigation State
    // State for presenting ChatView in a sheet using wrapper
    @State private var chatSheetItem: ChatSheetItem?
    @State private var isStartingConversation = false

    var body: some View {
        Group {
            if isLoadingUser {
                ProgressView("Loading profile…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let user = viewedUser {
                VStack(spacing: 20) {

                    // MARK: - Header (no Edit/Settings here)
                    headerView(for: user)

                    // MARK: - Tabs
                    Picker("", selection: $selectedTab) {
                        Text("Posts").tag(0)
                        Text("Places").tag(1)
                        Text("Art").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    // MARK: - Content
                    ZStack {
                        if selectedTab == 0 {
                            if vm.isLoading {
                                ProgressView("Loading posts…")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollView(.vertical, showsIndicators: false) {
                                    PostsTab(posts: vm.posts, gridMode: $postGridMode)
                                        .padding(.bottom, 100)
                                }
                            }
                        } else if selectedTab == 1 {
                            if vm.isLoading && vm.places.isEmpty {
                                ProgressView("Loading places…")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollView(.vertical, showsIndicators: false) {
                                    PlacesTab(places: vm.places, listMode: $placesListMode)
                                        .padding(.bottom, 100)
                                }
                            }
                        } else {
                            if vm.isLoading && vm.assets.isEmpty {
                                ProgressView("Loading artworks…")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollView(.vertical, showsIndicators: false) {
                                    ArtTab(assets: vm.assets)
                                        .padding(.bottom, 100)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
                .task {
                    // load the content for this userId
                    await vm.loadPosts(for: user.id)
                    await vm.loadPlaces(for: user.id)
                    await vm.loadUserCollection(userId: user.id)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.exclam")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("This profile isn't available.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // fetch the user once when the view appears
            await loadViewedUser()
        }
        // MARK: Chat Sheet Presentation
        // Presents ChatView in a sheet using presentation  item to avoid timing issues
        .sheet(item: $chatSheetItem) { item in
            if let currentUser = userVM.currentUser {
                NavigationStack {
                    ChatView(
                        vm: item.viewModel,
                        currentUserId: currentUser.id.uuidString.lowercased(),
                        currentUserName: currentUser.name ?? currentUser.username
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                chatSheetItem = nil
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header
    private func headerView(for user: User) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: user.avatarUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.purple, lineWidth: 2))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(user.name ?? user.username)
                        .font(.title3.bold())
                    if let verified = user.verifiedFlags?["blue"], verified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Text("@\(user.username)")
                    .foregroundStyle(.gray)

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statView(value: vm.posts.count, label: "Posts")
                    statView(value: user.stats?["followers"] ?? 0, label: "Followers")
                    statView(value: user.stats?["following"] ?? 0, label: "Following")
                }

                // Actions (Follow / Message)
                HStack(spacing: 10) {
                    Button {
                        guard !isWorking else { return }
                        isWorking = true
                        // TODO: hook up to follow/unfollow endpoint.
                        // For now we just toggle locally.
                        isFollowing.toggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isWorking = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: isFollowing ? "checkmark" : "plus")
                            Text(isFollowing ? "Following" : "Follow")
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isFollowing ? Color.gray.opacity(0.15) : Color.blue.opacity(0.9))
                        .foregroundColor(isFollowing ? .primary : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Button {
                        handleMessageTap(for: user)
                    } label: {
                        HStack {
                            if isStartingConversation {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Message")
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .disabled(isStartingConversation)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 25)
    }

    private func statView(value: Int, label: String) -> some View {
        VStack {
            Text("\(value)").bold()
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }

    
    // MARK: - Data
    private func loadViewedUser() async {
        if viewedUser != nil { return }
        isLoadingUser = true
        
        do {
            // This just triggers loading logic in userVM, no return value
            try await userVM.loadOtherUser(by: userId)
            
            // After it finishes, get the actual user
            if let fetched = userVM.otherUser {
                await MainActor.run {
                    self.viewedUser = fetched
                    self.isLoadingUser = false
                }
            } else {
                await MainActor.run { self.isLoadingUser = false }
            }
        } catch {
            await MainActor.run { self.isLoadingUser = false }
            print(" Failed to load viewed user: \(error)")
        }
    }
    
    // MARK: - Chat Navigation
    // Starts conversation and presents ChatView in a sheet
    private func handleMessageTap(for user: User) {
        guard let currentUser = userVM.currentUser, !isStartingConversation else { return }
        
        let otherUserId = user.id.uuidString.lowercased()
        let currentUserId = currentUser.id.uuidString.lowercased()
        
        isStartingConversation = true
        
        Task {
            let conversationVM = ConversationListViewModel(userId: currentUserId)
            if let convoId = await conversationVM.startConversation(with: otherUserId) {
                await MainActor.run {
                    // Creating a  ChatViewModel and wraping it in a ChatSheetItem
                    let viewModel = ChatViewModel(conversationId: convoId, userId: currentUserId)
                    chatSheetItem = ChatSheetItem(id: convoId, viewModel: viewModel)
                    isStartingConversation = false
                }
            } else {
                await MainActor.run {
                    isStartingConversation = false
                    print(" Failed to start conversation with user: \(user.username)")
                }
            }
        }
    }
}
