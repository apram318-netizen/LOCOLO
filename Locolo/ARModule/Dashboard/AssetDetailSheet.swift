//
//  AssetDetailSheet.swift
//  Locolo
//
//  The asset page.
//
//  V3 layout (feedback: "the sheet only fits up to the Marketplace button and
//  Make Offer is unreachable"): the old design stacked a 60%-of-screen 3D view
//  on top of a 50%-of-screen card — 110% of a sheet that's shorter than the
//  screen, so the bottom actions were clipped. Now:
//    * ONE scroll view: hero preview (≈44% of the sheet) → details → memories.
//    * The primary actions live in a PINNED bottom bar (safeAreaInset), so
//      Buy / Make offer / View in AR / Directions are always reachable at any
//      detent, Dynamic Type size or device height (HIG: keep the primary
//      action visible; don't make people scroll to commit).
//    * Every share button opens the Instagram-style ARShareSheet.
//

import SwiftUI
import CoreLocation

struct AssetDetailSheet: View {
    /// Mutable so post-buy / list / cancel / settings can refresh the row.
    @State private var asset: DigitalAsset
    /// Open the creator's public profile (WS4). The sheet can't push the nav
    /// stack itself, so the presenter passes a closure that dismisses + pushes.
    var onOpenCreator: (() -> Void)? = nil
    /// Open any user's profile (comment authors). Same dismiss + push contract.
    var onOpenProfile: ((UUID) -> Void)? = nil
    /// After dismissing, open Create with this asset as remix parent.
    var onRemix: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var wishlistVM: WishlistViewModel
    @ObservedObject private var engagement = EngagementStore.shared
    @ObservedObject private var creators = CreatorCache.shared
    @ObservedObject private var polls = PollStore.shared
    @ObservedObject private var remixes = RemixStore.shared
    @ObservedObject private var memories = MemoryStore.shared

    init(
        asset: DigitalAsset,
        onOpenCreator: (() -> Void)? = nil,
        onOpenProfile: ((UUID) -> Void)? = nil,
        onRemix: (() -> Void)? = nil
    ) {
        _asset = State(initialValue: asset)
        self.onOpenCreator = onOpenCreator
        self.onOpenProfile = onOpenProfile
        self.onRemix = onRemix
    }

    @State private var showARView = false
    @State private var showOffers = false
    @State private var showCreateOffer = false
    @State private var showMarketplace = false
    @State private var showManage = false
    @State private var showNavigation = false
    @State private var activeListing: AssetListing?
    @ObservedObject private var features = AppFeatures.shared
    @State private var distanceMeters: Double?
    @State private var isAboutExpanded = false
    @State private var resolvedLocationName = "Locating…"
    @State private var isWishlisted = false
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var showComments = false
    @State private var sharePayload: ARSharePayload?
    @State private var showSaveToBoard = false
    @State private var toast: String?
    @State private var assetTags: [TagItem] = []
    @State private var openMemory: MemoryViewerItem?

    private var isHyped: Bool { engagement.isHyped(asset.id) }
    private var hypeCount: Int { engagement.hypeCount(for: asset) }
    private var creator: ARCreator? { creators.creator(asset.userId) }
    private var assetMemories: [AssetMemory] { memories.byAsset[asset.id] ?? [] }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero(height: max(280, geo.size.height * 0.46))
                        VStack(alignment: .leading, spacing: 16) {
                            titleBlock
                            creatorRow
                            engagementRow
                            statsGrid
                            aboutSection
                            memoriesSection
                            if isCurrentUserOwner { ownerCard }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .background(Color(hex: "0E0A1A").ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.colorScheme, .dark)
            .sheet(isPresented: $showReport, onDismiss: {
                // A reported asset is hidden for this user — close its page too.
                if SafetyService.shared.isHidden(asset) { dismiss() }
            }) {
                ReportSheet(assetId: asset.id, userId: asset.userId,
                            subjectName: asset.name ?? "this asset")
            }
            .confirmationDialog("Block this creator?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block", role: .destructive) { blockCreator() }
            } message: {
                Text("You won't see their assets anywhere in Locolo. You can unblock them in Settings.")
            }
            .sheet(isPresented: $showComments) {
                CommentsSheet(asset: asset,
                              onOpenProfile: onOpenProfile == nil && onOpenCreator == nil
                                  ? nil : openProfileFromComments)
            }
            .sheet(isPresented: $showSaveToBoard) {
                SaveToBoardSheet(asset: asset)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $sharePayload) { payload in
                ARShareSheet(payload: payload) { message in showToast(message) }
            }
            .sheet(isPresented: $showMarketplace) {
                MarketplaceSheet(asset: asset) {
                    Task { await refreshAfterTrade() }
                }
            }
            .sheet(isPresented: $showOffers) {
                OfferListView(assetId: asset.id, ownerId: effectiveOwnerId)
            }
            .sheet(isPresented: $showCreateOffer) {
                CreateOfferView(assetId: asset.id)
            }
            .sheet(isPresented: $showManage, onDismiss: { Task { await refreshAsset() } }) {
                AssetManageSheet(asset: asset) { updated in asset = updated }
            }
            .fullScreenCover(isPresented: $showNavigation) {
                AssetNavigationView(asset: asset)
            }
            .fullScreenCover(item: $openMemory) { item in
                MemoryViewer(memories: item.memories, startIndex: item.start, onOpenAsset: nil)
            }
            .fullScreenCover(isPresented: $showARView) {
                // The real AR viewer — places this and other nearby assets
                // around the user (geo-anchored, GPS fallback). Memories are
                // captured from its shutter.
                ZStack(alignment: .topLeading) {
                    ARDisplayView(focusAssetId: asset.id)
                    Button { showARView = false } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    .padding(.top, 54)
                    .padding(.leading, 20)
                    .accessibilityLabel("Close AR view")
                }
                .ignoresSafeArea()
                .onDisappear { Task { await memories.load(asset: asset.id) } }
            }
            .overlay(alignment: .top) { toastView }
            .onAppear {
                computeDistance()
                reverseGeocodeAssetLocation()
                isWishlisted = wishlistVM.items.contains { $0.id == asset.id }
            }
            .task {
                async let engagementPrime: Void = engagement.prime([asset])
                async let creatorLoad: Void = creators.load([asset.userId])
                async let listingLoad: Void = loadActiveListing()
                async let reactions: Void = ReactionStore.shared.prime([asset])
                async let poll: Void = polls.load(for: asset.id)
                async let remixParent: UUID? = remixes.loadParent(of: asset.id)
                async let memoryLoad: [AssetMemory] = memories.load(asset: asset.id)
                _ = await (engagementPrime, creatorLoad, listingLoad, reactions, poll, remixParent, memoryLoad)
                assetTags = await TagStore.shared.tags(for: asset.id)
            }
        }
    }
}

// MARK: - Hero

extension AssetDetailSheet {
    private func hero(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            AssetSceneView(asset: asset)
                .frame(height: height)
                .overlay(alignment: .bottom) {
                    // Melt the stage into the page colour.
                    LinearGradient(colors: [.clear, Color(hex: "0E0A1A")], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                        .allowsHitTesting(false)
                }

            HStack {
                circleButton("chevron.down", label: "Close") { dismiss() }
                Spacer()
                circleButton(isWishlisted ? "bookmark.fill" : "bookmark",
                             label: isWishlisted ? "Remove from saved" : "Save") { toggleWishlist() }
                circleButton("paperplane", label: "Share") { sharePayload = .asset(asset) }
                moreMenu
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    if let distance = distanceLabel {
                        pill(distance, icon: "location.fill", tint: .pink)
                    }
                    if let category = asset.categoryLabel {
                        pill(category, icon: "cube.transparent")
                    }
                    Spacer()
                    pill("Drag to rotate", icon: "hand.draw")
                        .opacity(0.8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .frame(height: height)
        }
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func pill(_ text: String, icon: String, tint: Color = .white) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint == .white ? Color.black.opacity(0.35) : tint.opacity(0.85)))
            .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Content

extension AssetDetailSheet {
    private var effectiveOwnerId: UUID { asset.effectiveOwnerId }

    private var isCurrentUserOwner: Bool {
        userVM.currentUser?.id == effectiveOwnerId
    }

    private var isCreator: Bool { userVM.currentUser?.id == asset.userId }

    private var distanceLabel: String? {
        guard let m = distanceMeters else { return nil }
        return m < 1000 ? "\(Int(m)) m away" : String(format: "%.1f km away", m / 1000)
    }

    /// AR only makes sense on site. 150 m covers GPS error in dense cities.
    private var canOpenInAR: Bool {
        guard asset.fileType.lowercased() == "usdz" || asset.panoramaUrl != nil,
              let meters = distanceMeters else { return false }
        return meters <= 150
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(asset.name ?? "Untitled drop")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(resolvedLocationName).lineLimit(1)
                Text("·")
                Text(asset.createdAt.formatted(.relative(presentation: .named)))
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var creatorRow: some View {
        HStack(spacing: 10) {
            Button { openCreator() } label: {
                HStack(spacing: 10) {
                    ARAvatarView(url: creator?.avatarUrl, name: creator?.displayName ?? "?", size: 42)
                        .padding(2)
                        .overlay(Circle().strokeBorder(AppColors.purplePinkGradient, lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(creator?.displayName ?? "Creator")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if creator?.isVerified == true { ARVerifiedBadge(size: 12) }
                        }
                        Text(asset.ownerId != nil && asset.ownerId != asset.userId
                             ? "Creator · now owned by a collector"
                             : "@\(creator?.username ?? "creator")")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpenCreator == nil && onOpenProfile == nil)
            .accessibilityLabel("View \(creator?.displayName ?? "creator")'s profile")

            Spacer()

            if !isCreator {
                ARFollowButton(userId: asset.userId, style: .compact)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var engagementRow: some View {
        HStack(spacing: 10) {
            Button {
                ARHaptics.tick()
                Task { await engagement.toggleHype(asset) }
            } label: {
                capsule(icon: isHyped ? "bolt.fill" : "bolt", text: hypeCount.compactFormatted,
                        tint: isHyped ? .yellow : .white.opacity(0.85), active: isHyped)
                    .symbolEffect(.bounce, value: isHyped)
            }
            .accessibilityLabel(isHyped ? "Remove hype, \(hypeCount) hypes" : "Hype this asset, \(hypeCount) hypes")

            if engagement.commentsAvailable {
                Button { showComments = true } label: {
                    capsule(icon: "bubble.right", text: engagement.commentCount(for: asset.id).compactFormatted)
                }
                .accessibilityLabel("Comments, \(engagement.commentCount(for: asset.id))")
            }

            Button { sharePayload = .asset(asset) } label: {
                capsule(icon: "paperplane", text: "Share")
            }

            Spacer()

            ReactionBarView(assetId: asset.id, compact: true)
        }
        .buttonStyle(.plain)
    }

    private func capsule(icon: String, text: String, tint: Color = .white.opacity(0.85), active: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.numericText())
        }
        .foregroundColor(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(active ? 0.16 : 0.08)))
    }

    private var statsGrid: some View {
        let cells: [(String, String, String)] = [
            ("eye", asset.viewCount.compactFormatted, "Explorers"),
            ("photo.stack", "\(assetMemories.count)", "Memories"),
            ("dollarsign.circle", asset.currentValue.map { String(format: "$%.0f", $0) } ?? "—", "Value"),
            ("hand.raised", asset.acceptsOffers == true ? "\(asset.activeOffers ?? 0)" : "Off", "Offers"),
        ]
        return HStack(spacing: 8) {
            ForEach(cells, id: \.2) { icon, value, label in
                VStack(spacing: 4) {
                    Image(systemName: icon).font(.caption).foregroundStyle(.white.opacity(0.5))
                    Text(value)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(label).font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let desc = asset.description, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(isAboutExpanded ? nil : 3)
                    if desc.count > 140 {
                        Button(isAboutExpanded ? "Less" : "More") {
                            withAnimation { isAboutExpanded.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            if !assetTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(assetTags) { tag in
                            Text("#\(tag.slug)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                    }
                }
            }
            if remixes.parentOf[asset.id] != nil {
                Label("Remixed from another drop", systemImage: "wand.and.stars")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            if let poll = polls.pollsByAsset[asset.id] {
                AssetPollCard(poll: poll)
            }
        }
    }

    // MARK: Memories (snap-story style row)

    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Memories")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(assetMemories.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if !assetMemories.isEmpty {
                    Button("Watch all") { openMemory = MemoryViewerItem(memories: assetMemories, start: 0) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    addMemoryBubble
                    ForEach(Array(assetMemories.enumerated()), id: \.element.id) { index, memory in
                        Button {
                            openMemory = MemoryViewerItem(memories: assetMemories, start: index)
                        } label: {
                            MemoryBubble(memory: memory)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            if !memories.available {
                Text("Memories turn on after the next server update.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var addMemoryBubble: some View {
        Button {
            if canOpenInAR { showARView = true } else { showNavigation = true }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(.white.opacity(0.4))
                    Image(systemName: canOpenInAR ? "camera.fill" : "location.north.line.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .frame(width: 76, height: 104)
                Text(canOpenInAR ? "Capture" : "Go there")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(canOpenInAR ? "Capture a memory in AR" : "Get directions to capture a memory")
    }

    private var ownerCard: some View {
        Button { showManage = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.purplePinkGradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage this asset")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Growth charts, offers, visibility, thumbnail")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pinned action bar

extension AssetDetailSheet {
    private var primaryTitle: String {
        if let listing = activeListing {
            return isCurrentUserOwner ? "Listed · \(currency(listing.price))" : "Buy · \(currency(listing.price))"
        }
        if isCurrentUserOwner {
            return asset.acceptsOffers == true ? "View offers (\(asset.activeOffers ?? 0))" : "Sell"
        }
        return asset.acceptsOffers == true ? "Make offer" : "Marketplace"
    }

    /// With the marketplace off, the slot only carries offers.
    private var showsPrimaryAction: Bool {
        features.marketplaceEnabled || asset.acceptsOffers == true
    }

    private func primaryAction() {
        if activeListing != nil { showMarketplace = true; return }
        if isCurrentUserOwner {
            if asset.acceptsOffers == true { showOffers = true } else { showMarketplace = true }
        } else if asset.acceptsOffers == true {
            showCreateOffer = true
        } else {
            showMarketplace = true
        }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.08))
            HStack(spacing: 10) {
                Button {
                    if canOpenInAR { showARView = true } else { showNavigation = true }
                } label: {
                    Label(canOpenInAR ? "View in AR" : "Directions",
                          systemImage: canOpenInAR ? "arkit" : "location.north.line.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.12)))
                }
                .disabled(asset.latitude == nil)

                if showsPrimaryAction {
                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColors.purplePinkGradient))
                }
                }

                // Secondary marketplace entry stays one tap away when the
                // primary slot is taken by offers.
                if features.marketplaceEnabled && asset.acceptsOffers == true && activeListing == nil {
                    Button { showMarketplace = true } label: {
                        Image(systemName: "storefront")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.12)))
                    }
                    .accessibilityLabel("Marketplace")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
        .background(Color(hex: "0E0A1A").opacity(0.7))
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Capsule().fill(.black.opacity(0.85)))
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    withAnimation { self.toast = nil }
                }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = message }
    }
}

// MARK: - Menu & actions

extension AssetDetailSheet {
    private var moreMenu: some View {
        Menu {
            Button { sharePayload = .asset(asset) } label: {
                Label("Send to friends", systemImage: "paperplane")
            }
            Button { showSaveToBoard = true } label: {
                Label("Save to board", systemImage: "square.stack.3d.up")
            }
            if RemixStore.shared.available {
                Button {
                    RemixStore.shared.beginRemix(of: asset)
                    onRemix?()
                    dismiss()
                } label: {
                    Label("Remix this", systemImage: "wand.and.stars")
                }
            }
            if asset.latitude != nil {
                Button { showNavigation = true } label: {
                    Label("Directions", systemImage: "location.north.line")
                }
            }
            if isCurrentUserOwner || isCreator {
                Button { showManage = true } label: {
                    Label("Manage asset", systemImage: "slider.horizontal.3")
                }
            }
            if !isCurrentUserOwner {
                Divider()
                if SafetyExtrasStore.shared.available {
                    Button {
                        Task { await SafetyExtrasStore.shared.toggleMute(asset.userId) }
                    } label: {
                        Label(
                            SafetyExtrasStore.shared.isMuted(asset.userId) ? "Unmute creator" : "Mute creator",
                            systemImage: "bell.slash"
                        )
                    }
                }
                Button { showReport = true } label: {
                    Label("Report asset", systemImage: "flag")
                }
                Button(role: .destructive) { confirmBlock = true } label: {
                    Label("Block creator", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("More actions")
    }

    private func blockCreator() {
        guard let me = userVM.currentUser?.id else { return }
        ARHaptics.success()
        Task {
            await SafetyService.shared.block(asset.userId, by: me)
            dismiss()
        }
    }

    private func openCreator() {
        if let onOpenCreator {
            dismiss()
            onOpenCreator()
        } else if let onOpenProfile {
            dismiss()
            onOpenProfile(asset.userId)
        }
    }

    private func openProfileFromComments(_ id: UUID) {
        if let onOpenProfile {
            dismiss()
            onOpenProfile(id)
        } else if id == asset.userId {
            openCreator()
        }
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.0f", value)
    }

    private func loadActiveListing() async {
        guard features.marketplaceEnabled else { activeListing = nil; return }
        activeListing = try? await MarketplaceRepository.shared.activeListing(for: asset.id)
    }

    private func refreshAsset() async {
        if let fresh = await DigitalAssetRepository().fetchAsset(id: asset.id) {
            asset = fresh
        }
    }

    /// After buy / list / cancel / bid settle — refresh listing + asset row
    /// so owner_id / is_for_sale / price reflect the trade.
    private func refreshAfterTrade() async {
        async let listing: Void = loadActiveListing()
        if let fresh = await DigitalAssetRepository().fetchAsset(id: asset.id) {
            asset = fresh
            await engagement.prime([fresh])
        }
        _ = await listing
    }

    private func toggleWishlist() {
        guard let me = userVM.currentUser?.id else { return }
        ARHaptics.tick()
        let was = isWishlisted
        isWishlisted.toggle()
        showToast(was ? "Removed from saved" : "Saved")
        Task {
            if was {
                await wishlistVM.removeFromWishlist(userId: me, assetId: asset.id)
            } else {
                await wishlistVM.addToWishlist(userId: me, assetId: asset.id, asset: asset)
            }
        }
    }
}

// MARK: - Location

extension AssetDetailSheet {
    private func computeDistance() {
        distanceMeters = asset.distanceMeters
    }

    private func reverseGeocodeAssetLocation() {
        if let place = asset.displayLocation {
            resolvedLocationName = place
            return
        }
        guard let lat = asset.latitude, let lon = asset.longitude else {
            resolvedLocationName = "Somewhere in the world"
            return
        }
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)) { placemarks, _ in
            let place = placemarks?.first
            let name = place?.subLocality ?? place?.locality ?? place?.administrativeArea ?? place?.country
            DispatchQueue.main.async {
                resolvedLocationName = name ?? "Somewhere in the world"
            }
        }
    }
}

// MARK: - Matte Offer Button (kept for MarketplaceSheet / offer screens)
struct MatteOfferButton: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    Color.white.opacity(0.06).blur(radius: 2)
                    LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                        .blur(radius: 8)
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(LinearGradient(colors: [Color.purple.opacity(0.6), Color.pink.opacity(0.4)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1.1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
