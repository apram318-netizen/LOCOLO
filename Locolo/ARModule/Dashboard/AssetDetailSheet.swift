//
//  AssetDetailSheet.swift
//  Locolo
//
//  ok so this whole file is basically my asset detail page.
//  I forced it to always be dark mode because honestly the UI
//  just looks better dark and I cannot deal with light mode mismatch with the scene kit view.
//
//

import SwiftUI
import CoreLocation


struct AssetDetailSheet: View {
    /// Mutable so post-buy / list / cancel can refresh ownership & sale flags.
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

    // I just override the whole colour scheme.
    // I tried mixing light/dark earlier and it looked ugly + too bright.
    private let isDark = true

    @State private var showARView = false
    @State private var showOffers = false
    @State private var showCreateOffer = false
    @State private var showMarketplace = false
    @State private var activeListing: AssetListing?

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
    @State private var distanceText: String = "--"
    @State private var distanceMeters: Double?
    @State private var isAboutExpanded: Bool = false
    @State private var resolvedLocationName: String = "Unknown"
    @State private var isWishlisted: Bool = false
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var showComments = false
    @State private var showSendToChat = false
    @State private var showSaveToBoard = false
    @State private var shareToast: String?
    @State private var assetTags: [TagItem] = []

    private var isHyped: Bool { engagement.isHyped(asset.id) }
    private var hypeCount: Int { engagement.hypeCount(for: asset) }
    private var creator: ARCreator? { creators.creator(asset.userId) }
    
    var body: some View {
        NavigationStack {
            ZStack {
                
                // Background always full black. Less sensory chaos.
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // TOP ~60% → SceneKit preview
                    // earlier I tried 50% but felt too cramped,
                    // so I increased a bit.
                    AssetSceneView(asset: asset)
                        .frame(height: UIScreen.main.bounds.height * 0.60)
                        .background(Color.black)
                        .padding(.bottom, -20)  // I push it down so fog blends with card
                        .clipped()
                        .overlay(
                            // This little gradient helps avoid harsh line cut 
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.0),
                                    Color.black.opacity(0.35),
                                    Color.black.opacity(0.95)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 80),
                            alignment: .bottom
                        )
                    
                    // bottom card
                    bottomCard
                        .frame(height: UIScreen.main.bounds.height * 0.50)
                }
            }
            
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        // kept this simple, I was using a fancy custom back button before
                        // but honestly this one is faster and clean.
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    moreMenu
                }
            }
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
            // Instagram-style "send this asset in a message" — pick a person,
            // the asset is delivered as an E2E-encrypted rich card.
            .sheet(isPresented: $showSaveToBoard) {
                SaveToBoardSheet(asset: asset)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSendToChat) {
                ARNewMessageSheet { creator in
                    guard let me = userVM.currentUser else { return }
                    Task {
                        let ok = await AssetShareService.shared.shareAsset(asset.id, to: creator.id, from: me)
                        await MainActor.run {
                            shareToast = ok ? "Sent to \(creator.displayName)" : "Couldn't send — try again"
                            ARHaptics.success()
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = shareToast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Capsule().fill(.black.opacity(0.8)))
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            withAnimation { shareToast = nil }
                        }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shareToast)
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
                _ = await (engagementPrime, creatorLoad, listingLoad, reactions, poll, remixParent)
            }
            .sheet(isPresented: $showMarketplace) {
                MarketplaceSheet(asset: asset) {
                    Task { await refreshAfterTrade() }
                }
            }
        }
    }
}

extension AssetDetailSheet {
    
    // I check if the asset belongs to current user
    private var effectiveOwnerId: UUID { asset.effectiveOwnerId }

    private var isCurrentUserOwner: Bool {
        userVM.currentUser?.id == effectiveOwnerId
    }

    private var marketplaceButtonTitle: String {
        if let listing = activeListing {
            if isCurrentUserOwner {
                return "Listed · \(currency(listing.price))"
            }
            return "Buy · \(currency(listing.price))"
        }
        return "Marketplace"
    }
    
    // AR button only appears if you're close to the asset
    // I put 150m because earlier 100m felt too strict.
    // Any placeable USDZ (or panorama) qualifies — the old
    // interactionType == "ar" gate could never be true because creation
    // never writes that value.
    private var shouldShowARButton: Bool {
        guard asset.fileType.lowercased() == "usdz" || asset.panoramaUrl != nil,
              let meters = distanceMeters else { return false }
        return meters <= 150
    }
    
    // MARK: - Bottom Card
    private var bottomCard: some View {
        ZStack {
            
            // Always dark gradient.
            // I lowered opacity because earlier it was too shiny
            // and hurting my eyes at night.
            RoundedRectangle(cornerRadius: 26)
                .fill(AppColors.cardGradientDark)
                .opacity(0.92)
                .background(.ultraThinMaterial.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .shadow(color: Color.black.opacity(0.8), radius: 20, x: 0, y: -4)
            
            // scroll content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    topRow
                    titleSection
                    creatorRow
                    hypeOnlySection
                    aboutSection
                    priceSection
                    buttonSection
                }
                .padding(22)
            }
        }
        .padding(.horizontal, 20)
    }
    
    
    // MARK: - TOP ROW
    private var topRow: some View {
        HStack(alignment: .top) {
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // Location + distance
                    Label(resolvedLocationName, systemImage: "mappin.and.ellipse")
                        .foregroundColor(.white.opacity(0.85))
                        .font(.subheadline.weight(.semibold))
                    
                    if distanceText != "--" {
                        Text(distanceText)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.pink.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                
                // type badge
                Text(asset.fileType.uppercased())
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                
                // creation date
                Text(asset.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                
                // wishlist button — persists via WishlistViewModel
                Button { toggleWishlist() } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.09))
                            .frame(width: 30, height: 30)
                        Image(systemName: isWishlisted ? "bookmark.fill" : "bookmark")
                            .foregroundColor(isWishlisted ? .purple : .white)
                    }
                }
                .padding(.top, 4)
                .accessibilityLabel(isWishlisted ? "Remove from saved" : "Save")
            }
        }
    }
    
    
    // MARK: - TITLE
    private var titleSection: some View {
        // title looks cleaner when it's bold white
        Text(asset.name ?? "Untitled Artwork")
            .font(.title2.bold())
            .foregroundColor(.white)
    }
    
    
    // MARK: - CREATOR
    private var creatorRow: some View {
        HStack(spacing: 10) {
            Button { openCreator() } label: {
                HStack(spacing: 10) {
                    ARAvatarView(url: creator?.avatarUrl, name: creator?.displayName ?? "?", size: 38)
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
                        if let handle = creator?.username {
                            Text("@\(handle)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpenCreator == nil && onOpenProfile == nil)
            .accessibilityLabel("View \(creator?.displayName ?? "creator")'s profile")

            Spacer()

            ARFollowButton(userId: asset.userId, style: .compact)
                .environment(\.colorScheme, .dark)
        }
        .padding(.vertical, 10)
    }

    // MARK: - ENGAGEMENT
    private var hypeOnlySection: some View {
        HStack(spacing: 10) {
            // Interactive hype toggle — persists via asset_hype + atomic RPC.
            Button {
                ARHaptics.tick()
                Task { await engagement.toggleHype(asset) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isHyped ? "bolt.fill" : "bolt")
                        .symbolEffect(.bounce, value: isHyped)
                    Text(hypeCount.compactFormatted)
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                }
                .foregroundColor(isHyped ? .yellow : .white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(isHyped ? 0.14 : 0.08)))
            }
            .accessibilityLabel(isHyped ? "Remove hype, \(hypeCount) hypes" : "Hype this asset, \(hypeCount) hypes")

            if engagement.commentsAvailable {
                Button { showComments = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                        Text(engagement.commentCount(for: asset.id).compactFormatted)
                            .font(.subheadline.weight(.semibold))
                            .contentTransition(.numericText())
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .accessibilityLabel("Comments, \(engagement.commentCount(for: asset.id))")
            }

            if asset.viewCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "eye")
                    Text(asset.viewCount.compactFormatted)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(asset.viewCount) explorers")
            }

            Spacer()

            ShareLink(
                item: DeepLinkRouter.assetURL(for: asset.id),
                subject: Text(asset.name ?? "AR asset on Locolo"),
                message: Text("Check out \"\(asset.name ?? "this AR asset")\" on Locolo")
            ) {
                Image(systemName: "paperplane")
                    .foregroundColor(.white.opacity(0.85))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .accessibilityLabel("Share")
        }
        .padding(.bottom, 8)
    }
    
    
    // MARK: - ABOUT
    private var aboutSection: some View {
        Group {
            if let desc = asset.description, !desc.isEmpty {
                // I kept this disclosureGroup because long descriptions
                // were ruining the layout visually.
                DisclosureGroup(isExpanded: $isAboutExpanded) {
                    Text(desc)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 4)
                } label: {
                    Text("About this artwork")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                }
            }
            if !assetTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(assetTags) { tag in
                            Text("#\(tag.slug)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                    }
                }
                .padding(.top, 6)
            }
            if remixes.parentOf[asset.id] != nil {
                Label("Remixed from another drop", systemImage: "wand.and.stars")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 4)
            }
            ReactionBarView(assetId: asset.id, compact: true)
                .padding(.top, 8)
            if let poll = polls.pollsByAsset[asset.id] {
                AssetPollCard(poll: poll)
                    .padding(.top, 8)
            }
        }
        .task {
            assetTags = await TagStore.shared.tags(for: asset.id)
        }
    }
    
    
    // MARK: - PRICE
    private var priceSection: some View {
        Group {
            if let price = asset.currentValue {
                // I tried making this bigger But looked kinda weird.
                Text("$\(price, specifier: "%.0f")")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .padding(.top, 4)
            }
        }
    }
    
    
    // MARK: - BUTTONS
    private var buttonSection: some View {
        VStack(spacing: 12) {

            Button { showMarketplace = true } label: {
                MatteOfferButton(title: marketplaceButtonTitle)
            }

            // OFFERS
            if asset.acceptsOffers == true {
                if isCurrentUserOwner {
                    
                    // Owner can see offers they got
                    Button { showOffers = true } label: {
                        MatteOfferButton(title: "View Offers")
                    }
                    .sheet(isPresented: $showOffers) {
                        OfferListView(assetId: asset.id, ownerId: effectiveOwnerId)
                    }
                    
                } else {
                    
                    // Non-owner can make offer
                    Button { showCreateOffer = true } label: {
                        MatteOfferButton(title: "Make Offer")
                    }
                    .sheet(isPresented: $showCreateOffer) {
                        CreateOfferView(assetId: asset.id)
                    }
                }
            }

            // AR VIEW button
            if shouldShowARButton {
                Button { showARView = true } label: {
                    Label("AR View", systemImage: "arkit")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppColors.blueCyanMutedGradient)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .fullScreenCover(isPresented: $showARView) {
                    // The real AR viewer — places this and other nearby assets
                    // around the user (geo-anchored, GPS fallback).
                    ZStack(alignment: .topLeading) {
                        ARDisplayView()
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
                }
            }
        }
    }
}


// MARK: - ENGAGEMENT ACTIONS
extension AssetDetailSheet {
    private var moreMenu: some View {
        Menu {
            Button {
                showSendToChat = true
            } label: {
                Label("Send in a message", systemImage: "paperplane")
            }
            Button {
                showSaveToBoard = true
            } label: {
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
            ShareLink(
                item: DeepLinkRouter.assetURL(for: asset.id),
                subject: Text(asset.name ?? "AR asset on Locolo"),
                message: Text("Check out \"\(asset.name ?? "this AR asset")\" on Locolo")
            ) {
                Label("Share externally…", systemImage: "square.and.arrow.up")
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
                Button {
                    showReport = true
                } label: {
                    Label("Report asset", systemImage: "flag")
                }
                Button(role: .destructive) {
                    confirmBlock = true
                } label: {
                    Label("Block creator", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(.white)
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
        activeListing = try? await MarketplaceRepository.shared.activeListing(for: asset.id)
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
        Task {
            if was {
                await wishlistVM.removeFromWishlist(userId: me, assetId: asset.id)
            } else {
                await wishlistVM.addToWishlist(userId: me, assetId: asset.id, asset: asset)
            }
        }
    }
}

// MARK: - DISTANCE CALCULATION
extension AssetDetailSheet {
    private func computeDistance() {
        guard let lat = asset.latitude,
              let lon = asset.longitude else { return }
        
        let manager = LocationManager.shared
        guard let coord = manager.userLocation ?? manager.latestStoredLocation else {
            distanceText = "--"
            return
        }
        
        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let assetLoc = CLLocation(latitude: lat, longitude: lon)
        
        let meters = userLoc.distance(from: assetLoc)
        distanceMeters = meters
        
        // I kept distance formatting simple
        if meters < 100 {
            distanceText = "\(Int(meters)) m"
        } else if meters < 1000 {
            distanceText = "\(Int(meters)) m"
        } else {
            distanceText = String(format: "%.1f km", meters/1000)
        }
    }
    
    private func reverseGeocodeAssetLocation() {
        // Assets posted with an exact address don't need geocoding
        if let address = asset.address, !address.isEmpty {
            resolvedLocationName = address
            return
        }

        guard let lat = asset.latitude,
              let lon = asset.longitude else { return }

        let location = CLLocation(latitude: lat, longitude: lon)
        let geocoder = CLGeocoder()

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let place = placemarks?.first {
                // prioritise: Suburb, City, Country (you can tune this)
                let name =
                    place.locality ??
                    place.subLocality ??
                    place.administrativeArea ??
                    place.country ??
                    "Unknown"

                DispatchQueue.main.async {
                    resolvedLocationName = name
                }
            }
        }
    }
}


// MARK: - Matte Offer Button (looks clean + shiny)
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
                    // faint blur base
                    Color.white.opacity(0.06).blur(radius: 2)
                    
                    // subtle vertical gloss
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blur(radius: 8)

                    // clean border
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.purple.opacity(0.6),
                                    Color.pink.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.1
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
