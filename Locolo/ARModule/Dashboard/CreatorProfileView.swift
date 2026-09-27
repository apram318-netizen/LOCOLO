//
//  CreatorProfileView.swift
//  Locolo
//
//  Public creator profile (WS4): identity header, follower/following counts,
//  Follow / Message actions, and a grid of the creator's placed AR assets.
//

import SwiftUI
import MapKit

struct CreatorProfileView: View {
    let userId: UUID

    @StateObject private var vm: CreatorProfileViewModel
    @EnvironmentObject private var dashboardState: ARDashboardState
    @EnvironmentObject private var userVM: UserViewModel
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var safety = SafetyService.shared

    @State private var selectedAsset: DigitalAsset?
    @State private var activeChat: ActiveChat?
    @State private var isOpeningChat = false
    @State private var showReport = false
    @State private var confirmBlock = false

    private var isBlocked: Bool { safety.isBlocked(userId) }

    /// Mirrors the server's da_select policy so private/friends assets stay
    /// hidden even before the RLS migration is applied.
    private var visibleAssets: [DigitalAsset] {
        guard !isBlocked else { return [] }
        return safety.visible(vm.assets).filter { asset in
            switch asset.normalizedVisibility {
            case "private": return vm.isSelf
            case "friends": return vm.isSelf || vm.isFollowing
            default:        return true
            }
        }
    }

    private var visiblePins: [AssetPlacementPin] {
        let ids = Set(visibleAssets.map(\.id))
        return vm.pins.filter { ids.contains($0.id) }
    }

    /// Identifiable wrapper so the chat sheet can be driven by .sheet(item:).
    private struct ActiveChat: Identifiable {
        let id: String   // conversation id
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(userId: UUID) {
        self.userId = userId
        _vm = StateObject(wrappedValue: CreatorProfileViewModel(userId: userId))
    }

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        header(scrollToAssets: {
                            withAnimation(.easeInOut) { proxy.scrollTo("assets", anchor: .top) }
                        })
                        if let error = vm.errorMessage {
                            errorBanner(error)
                        }
                        if isBlocked {
                            blockedState
                        } else {
                            if vm.canFollow || vm.isSelf { actionRow }
                            if !visiblePins.isEmpty { placementMap }
                            assetGrid.id("assets")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .refreshable { await vm.load() }
            }

            if vm.isLoading && vm.user == nil {
                ProgressView().tint(.purple).scaleEffect(1.3)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ARGlassHeader(title: vm.creator?.displayName ?? "Profile",
                          subtitle: vm.user.map { "@\($0.username)" }) {
                if !vm.isSelf && userVM.currentUser != nil {
                    safetyMenu
                }
            }
            .overlay(alignment: .leading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .padding(9)
                        .background(Circle().fill(ARDesign.headerButtonCircle))
                }
                .padding(.leading, 16)
                .accessibilityLabel("Back")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .sheet(item: $selectedAsset) { AssetDetailSheet(asset: $0) }
        .sheet(isPresented: $showReport) {
            ReportSheet(assetId: nil, userId: userId,
                        subjectName: vm.creator?.displayName ?? "this creator")
        }
        .confirmationDialog("Block \(vm.creator?.displayName ?? "this creator")?",
                            isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { setBlocked(true) }
        } message: {
            Text("You won't see their assets anywhere in Locolo. You can unblock them any time.")
        }
        .sheet(item: $activeChat) { chat in
            // E2E chat with this creator (WS6). peerId passed explicitly so the
            // key derives immediately without a participants fetch.
            if let me = userVM.currentUser {
                NavigationStack {
                    ARChatScreen(conversationId: chat.id, peerId: userId,
                                 title: vm.creator?.displayName ?? "Chat",
                                 currentUserId: me.id.uuidString,
                                 currentUserName: me.name ?? me.username)
                }
            }
        }
    }

    // MARK: - Safety

    private var safetyMenu: some View {
        Menu {
            Button {
                showReport = true
            } label: {
                Label("Report creator", systemImage: "flag")
            }
            if isBlocked {
                Button {
                    setBlocked(false)
                } label: {
                    Label("Unblock", systemImage: "hand.raised.slash")
                }
            } else {
                Button(role: .destructive) {
                    confirmBlock = true
                } label: {
                    Label("Block", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.bold())
                .foregroundColor(.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(ARDesign.headerButtonCircle))
        }
        .accessibilityLabel("More actions")
    }

    private func setBlocked(_ blocked: Bool) {
        guard let me = userVM.currentUser?.id else { return }
        ARHaptics.tick()
        Task {
            if blocked {
                await safety.block(userId, by: me)
            } else {
                await safety.unblock(userId, by: me)
            }
        }
    }

    private var blockedState: some View {
        ARInlineEmptyState(
            icon: "hand.raised.fill",
            title: "You blocked this creator",
            subtitle: "Their assets are hidden from your feeds, map, and AR view.",
            actionTitle: "Unblock",
            action: { setBlocked(false) }
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.orange)
            Text(message)
                .font(.footnote)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
            Button("Retry") { Task { await vm.load() } }
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .arGlassCard(cornerRadius: 14)
    }

    // MARK: - Messaging

    /// Find-or-create the 1:1 conversation with this creator, then open chat.
    private func startConversation() {
        guard let me = userVM.currentUser, !isOpeningChat else { return }
        isOpeningChat = true
        let myId = me.id.uuidString.lowercased()
        let peer = userId.uuidString.lowercased()
        Task {
            defer { isOpeningChat = false }
            let repo = ChatRepository()
            do {
                let convoId: String
                if let existing = try await repo.findExistingConversation(between: myId, and: peer) {
                    convoId = existing
                } else {
                    convoId = try await repo.createConversation(between: [myId, peer])
                }
                activeChat = ActiveChat(id: convoId)
            } catch {
                vm.errorMessage = "Couldn't open the conversation. Try again."
            }
        }
    }

    // MARK: - Header

    private func header(scrollToAssets: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            AsyncImage(url: vm.user?.avatarUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Circle().fill(AppColors.purplePinkGradient.opacity(0.25))
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundColor(.purple)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(ARDesign.hairline, lineWidth: 1))

            HStack(spacing: 6) {
                Text(vm.creator?.displayName ?? "AR Creator")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                if vm.creator?.isVerified == true {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Verified creator")
                }
            }

            if let bio = vm.user?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            statsRow(scrollToAssets: scrollToAssets)
        }
    }

    private func statsRow(scrollToAssets: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            statPill(count: visibleAssets.count, label: "Assets", action: scrollToAssets)
            divider
            statPill(count: vm.followers, label: "Followers") {
                dashboardState.path.append(.followList(userId: userId, followers: true))
            }
            divider
            statPill(count: vm.following, label: "Following") {
                dashboardState.path.append(.followList(userId: userId, followers: false))
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .arGlassCard(cornerRadius: 18)
    }

    private var divider: some View {
        Rectangle().fill(ARDesign.hairline).frame(width: 1, height: 32)
    }

    private func statPill(count: Int, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(count)").font(.title3.bold()).foregroundColor(.primary)
                Text(label).font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(label)")
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            if vm.canFollow {
                Button { Task { await vm.toggleFollow() } } label: {
                    Text(vm.isFollowing ? "Following" : "Follow")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if vm.isFollowing {
                                Capsule().fill(.ultraThinMaterial)
                            } else {
                                Capsule().fill(AppColors.purplePinkGradient)
                            }
                        }
                        .overlay(
                            Capsule().strokeBorder(vm.isFollowing ? ARDesign.hairline : .clear, lineWidth: 1)
                        )
                        .foregroundColor(vm.isFollowing ? .primary : .white)
                }
                .disabled(vm.isMutatingFollow)

                Button { startConversation() } label: {
                    Group {
                        if isOpeningChat {
                            ProgressView().tint(.primary)
                        } else {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(ARDesign.headerButtonCircle))
                }
                .disabled(isOpeningChat)
                .accessibilityLabel("Message")
            } else if vm.isSelf {
                Text("This is you")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
        }
    }

    // MARK: - Placement map

    private var placementMap: some View {
        VStack(alignment: .leading, spacing: 12) {
            ARSectionHeader(title: "On the Map",
                            subtitle: visiblePins.count == 1 ? "1 placement" : "\(visiblePins.count) placements",
                            icon: "map")

            Map(initialPosition: .automatic) {
                ForEach(visiblePins) { pin in
                    Annotation(pin.name ?? "Asset",
                               coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)) {
                        Button {
                            selectedAsset = visibleAssets.first { $0.id == pin.id }
                        } label: {
                            Image(systemName: "cube.fill")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .padding(7)
                                .background(Circle().fill(AppColors.purplePinkGradient))
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                .shadow(radius: 3)
                        }
                        .accessibilityLabel("Open \(pin.name ?? "asset")")
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ARDesign.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Assets

    private var assetGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ARSectionHeader(title: "Placed Assets",
                            subtitle: visibleAssets.isEmpty ? nil : "\(visibleAssets.count) in the world",
                            icon: "cube.transparent")

            if visibleAssets.isEmpty {
                emptyAssets
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visibleAssets) { asset in
                        Button { selectedAsset = asset } label: {
                            AssetThumbnailView(asset: asset, cornerRadius: 16)
                                .aspectRatio(1, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(alignment: .bottomLeading) {
                                    Text(asset.name ?? "Untitled")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                                           startPoint: .top, endPoint: .bottom)
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyAssets: some View {
        ARInlineEmptyState(
            icon: "cube.transparent",
            title: vm.isSelf ? "You haven't placed any assets yet" : "No assets placed yet",
            subtitle: vm.isSelf ? "Your AR creations will show up here." : nil,
            actionTitle: vm.isSelf ? "Create your first" : nil,
            action: vm.isSelf ? { dashboardState.path.append(.create) } : nil
        )
    }
}
