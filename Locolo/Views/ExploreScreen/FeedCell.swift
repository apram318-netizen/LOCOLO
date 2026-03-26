//
//  FeedCell.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import SwiftUI

struct FeedCell: View {
    let post: Post

    @EnvironmentObject var userVM: UserViewModel
    // MARK: ViewModels
    @StateObject private var vmPlace = PlaceViewModel()
    @StateObject private var hypeVM: HypeViewModel
    @StateObject private var echoVM: EchoViewModel

    // MARK: View State
    @State private var place: Place?
    @Binding var selectedPost: Post?
    @State private var showEchoSheet = false
    @State private var navigateToProfile = false
    @State private var targetUserId: UUID?
    @State private var isSelfProfile = false

    init(post: Post, selectedPost: Binding<Post?>, currentUserId: UUID) {
        self.post = post
        _selectedPost = selectedPost
        _hypeVM = StateObject(wrappedValue: HypeViewModel(post: post, currentUserId: currentUserId))
        _echoVM = StateObject(wrappedValue: EchoViewModel(post: post))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: Header Section
            // MARK: - Header (Profile Navigation)
            HStack {
                Button {
                    if post.authorId == userVM.currentUser?.id {
                        isSelfProfile = true
                    } else {
                        targetUserId = post.authorId
                        isSelfProfile = false
                    }
                    navigateToProfile = true
                } label: {
                    AsyncImage(url: post.author?.avatarUrl) { phase in
                        switch phase {
                        case .empty:
                            Circle().fill(Color.gray.opacity(0.3))
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: "person.crop.circle.fill")
                                .resizable().scaledToFill()
                                .foregroundColor(.gray)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // Username
                        Button {
                            if post.authorId == userVM.currentUser?.id {
                                isSelfProfile = true
                            } else {
                                targetUserId = post.authorId
                                isSelfProfile = false
                            }
                            navigateToProfile = true
                        } label: {
                            Text(post.author?.username ?? "")
                                .bold()
                                .foregroundColor(AppColors.primaryText)
                        }
                        .buttonStyle(.plain)

                        //  Status tag restored
                        if let tag = post.author?.loopTimeCounters?.first?.status {
                            Text(tag.capitalized)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.blueCyanMutedGradient.opacity(0.25))
                                .cornerRadius(6)
                        }
                    }

                    Text(place?.name ?? "")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                Text(relativeTime(for: post.createdAt))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            // Hidden navigation destination for profile
            NavigationLink(destination: destinationView, isActive: $navigateToProfile) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .opacity(0)

            // MARK: - Media (Fixed Tap Issue) just now. Tried using the allow hit testing and image clipping and everything I can think of.. SOmething worked
            AsyncImage(url: post.media) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 200)
                        .cornerRadius(12)
                        .allowsHitTesting(false)
                case .success(let image):
                    image.resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipped()
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                default:
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 200)
                            .cornerRadius(12)
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                    .allowsHitTesting(false)
                }
            }

            // MARK: - Caption
            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.body)
            }

            // MARK: - Hype + Echo Actions
            HStack(spacing: 16) {
                Button(action: { hypeVM.toggleHype() }) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundColor(hypeVM.isHypedByUser ? .yellow : .gray)
                }
                Text("\(hypeVM.hypes.count)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Button(action: {
                    selectedPost = post
                    showEchoSheet = true
                }) {
                    Image(systemName: "bubble.right")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
        .onAppear {
            hypeVM.loadHypes()
            if let placeId = post.placeId {
                Task {
                    if let fetched = await vmPlace.getPlace(by: placeId) {
                        self.place = fetched
                    }
                }
            }
        }
        .sheet(isPresented: $showEchoSheet) {
            EchoSheet(post: post, vm: echoVM)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .onAppear {
                    Task { await echoVM.loadEchoes(for: post) }
                }
        }
    }

    // MARK: - Destination Logic
    @ViewBuilder
    private var destinationView: some View {
        if isSelfProfile {
            ProfileView().environmentObject(userVM)
        } else if let id = targetUserId {
            UserProfileView(userId: id).environmentObject(userVM)
        }
    }

    // MARK: - Time Formatter
    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

