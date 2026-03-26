//
//  VerticalPlacePostView.swift
//  Locolo
//
//  Created by Apramjot Singh on 10/10/2025.
//

import SwiftUI
import CoreLocation

struct VerticalPlacePostView: View {
    let post: Post
    let place: Place
    let isPreview: Bool
    @StateObject private var echoVM: EchoViewModel

    @EnvironmentObject var createPostVM: CreatePostViewModel
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var locationVM: LocationViewModel

    // MARK: ViewModels
    @StateObject private var vmPlace = PlaceViewModel()
    @StateObject private var hypeVM: HypeViewModel

    // MARK: View State
    @State private var showPlaceDetails = false
    @State private var showPlaceOverview = false
    @State private var selectedPost: Post?
    @State private var showEchoSheet = false

    // MARK: Navigation State
    @State private var navigateToProfile = false
    @State private var targetUserId: UUID?
    @State private var isSelfProfile = false

    // MARK: - Init
    init(post: Post, place: Place, isPreview: Bool, currentUserId: UUID) {
        self.post = post
        self.place = place
        self.isPreview = isPreview
        _hypeVM = StateObject(wrappedValue: HypeViewModel(post: post, currentUserId: currentUserId))
        _echoVM = StateObject(wrappedValue: EchoViewModel(post: post))
    }

    // MARK: Body
    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header Section
            // Header
            headerSection
                .padding(.top, 12)
                .padding(.horizontal)

            // MARK: Navigation Link
            // Hidden NavigationLink for profile
            NavigationLink(destination: destinationView, isActive: $navigateToProfile) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .opacity(0)

            // MARK: Caption Section
            // Caption
            if let caption = captionText, !caption.isEmpty {
                Text(caption)
                    .font(.body)
                    .foregroundColor(AppColors.primaryText)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            // MARK: Media Section
            // Media
            mediaSection
                .frame(maxWidth: .infinity)
                .aspectRatio(contentMode: .fit)
                .clipped()
                .background(Color(.systemGray6))

            // MARK: Place Overlay Section
            // Place overlay
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showPlaceDetails.toggle()
                }
            } label: {
                placeOverlay
            }

            // MARK: Place Details Section
            // Expandable place details
            if showPlaceDetails {
                placeDetailsSection
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Divider()

            // MARK: Interaction Bar Section
            // Interaction bar (FeedCell logic)
            interactionBar
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .cornerRadius(24)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(24)
        .shadow(color: AppColors.cardShadow, radius: 6, y: 2)
        .padding(.horizontal)
        .onAppear {
            hypeVM.loadHypes()
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
}

// MARK: - Extensions
extension VerticalPlacePostView {

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {

            // Profile picture
            Button {
                if post.authorId == userVM.currentUser?.id {
                    isSelfProfile = true
                } else {
                    targetUserId = post.authorId
                    isSelfProfile = false
                }
                navigateToProfile = true
            } label: {
                AsyncImage(url: authorAvatar) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Circle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Username button
                    Button {
                        if post.authorId == userVM.currentUser?.id {
                            isSelfProfile = true
                        } else {
                            targetUserId = post.authorId
                            isSelfProfile = false
                        }
                        navigateToProfile = true
                    } label: {
                        Text(authorName)
                            .font(.headline)
                            .foregroundColor(AppColors.primaryText)
                    }
                    .buttonStyle(.plain)

                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                    }

                    if let tag = post.author?.loopTimeCounters?.first?.status {
                        Text(tag.capitalized)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.blueCyanMutedGradient.opacity(0.25))
                            .cornerRadius(6)
                    }
                }

                HStack(spacing: 6) {
                    Text("@\(authorUsername)")
                        .foregroundColor(AppColors.secondaryText)
                    Text("• \(relativeTime(for: post.createdAt))")
                        .foregroundColor(AppColors.secondaryText)
                        .font(.caption2)
                }
            }

            Spacer()
        }
    }

    // MARK: - Profile Destination
    @ViewBuilder
    private var destinationView: some View {
        if isSelfProfile {
            ProfileView()
                .environmentObject(userVM)
        } else if let id = targetUserId {
            UserProfileView(userId: id)
                .environmentObject(userVM)
        } else {
            EmptyView()
        }
    }

    // MARK: - Media
    private var mediaSection: some View {
        Group {
            if isPreview {
                if !createPostVM.memoryImages.isEmpty {
                    TabView {
                        ForEach(createPostVM.memoryImages, id: \.self) { image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .clipped()
                                .contentShape(Rectangle())
                                .allowsHitTesting(false)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                } else {
                    placeholderView
                }
            } else {
                if let mediaUrl = post.media {
                    AsyncImage(url: mediaUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .scaledToFill()
                                .clipped()
                                .contentShape(Rectangle())
                                .allowsHitTesting(false)
                        default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
            }
        }
    }

    // MARK: - Place Overlay
    private var placeOverlay: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: place.placeImageUrl ?? "")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Color.gray.opacity(0.2)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.6), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.cyan)
                    Text(place.name)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                HStack(spacing: 6) {
                    Text(place.categoryId != nil ? "Coffee Shop" : "Spot")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.blue.opacity(0.6)))

                    if let distance = distanceText() {
                        Text("• \(distance)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            Spacer()
            Image(systemName: showPlaceDetails ? "chevron.up" : "chevron.down")
                .foregroundColor(.white)
                .font(.headline)
        }
        .padding()
        .background(
            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.4)],
                           startPoint: .bottom, endPoint: .top)
        )
    }

    // MARK: - Place Details (unchanged)
    private var placeDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let desc = place.description,
               !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("About this spot", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(AppColors.primaryText)
            }

            HStack {
                VStack(alignment: .leading) {
                    Label("Distance", systemImage: "location.north.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let distance = distanceText() {
                        Text(distance)
                            .font(.subheadline.bold())
                    }
                }
                Spacer()
                VStack(alignment: .leading) {
                    Label("Vibe", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Cyberpunk")
                        .font(.subheadline.bold())
                }
            }

            if let address = place.location?.address {
                VStack(alignment: .leading) {
                    Label("Address", systemImage: "map.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(address)
                        .font(.subheadline)
                }
            }

            Button {
                showPlaceOverview = true
            } label: {
                Label("View Full Place Details", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppColors.blueCyanMutedGradient)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .navigationDestination(isPresented: $showPlaceOverview) {
                PlaceOverviewScreen(place: place)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding(.horizontal)
    }

    // MARK: - Interaction Bar
    private var interactionBar: some View {
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

            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers
    private var captionText: String? {
        isPreview ? createPostVM.description : post.caption
    }
    private var authorAvatar: URL? {
        isPreview ? userVM.currentUser?.avatarUrl : post.author?.avatarUrl
    }
    private var authorName: String {
        isPreview ? (userVM.currentUser?.username ?? "You") : (post.author?.username ?? "User")
    }
    private var authorUsername: String {
        isPreview ? (userVM.currentUser?.username ?? "you") : (post.author?.username ?? "user")
    }
    private var isVerified: Bool { true }

    private var placeholderView: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundColor(.gray)
        }
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func distanceText() -> String? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "latestUserLocation") as? [String: Any],
              let lat = dict["lat"] as? Double,
              let lon = dict["lon"] as? Double,
              let placeLat = place.location?.latitude,
              let placeLon = place.location?.longitude else { return nil }

        let userLoc = CLLocation(latitude: lat, longitude: lon)
        let placeLoc = CLLocation(latitude: placeLat, longitude: placeLon)
        let distance = userLoc.distance(from: placeLoc)
        return distance > 1000
            ? String(format: "%.1f km", distance / 1000)
            : String(format: "%.0f m", distance)
    }
}

