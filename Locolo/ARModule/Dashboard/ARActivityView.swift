//
//  ARActivityView.swift
//  Locolo
//
//  Notifications-style activity inbox: follows, hypes, comments and mentions,
//  offers (and answers to yours), new drops from people you follow,
//  discoveries and milestones. Grouped into New / Earlier; opening the screen
//  marks everything seen when you leave it.
//

import SwiftUI
import UserNotifications

struct ARActivityView: View {
    @EnvironmentObject private var dashboardState: ARDashboardState
    @ObservedObject private var store = ActivityStore.shared
    @ObservedObject private var creators = CreatorCache.shared
    @ObservedObject private var safety = SafetyService.shared

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case follows = "Follows"
        case hypes = "Hypes"
        case comments = "Comments"
        case social = "Social"
        case sales = "Sales"
        case offers = "Offers"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all: return "bell"
            case .follows: return "person.badge.plus"
            case .hypes: return "bolt"
            case .comments: return "bubble.right"
            case .social: return "sparkles"
            case .sales: return "cart"
            case .offers: return "tag"
            }
        }

        func matches(_ kind: SocialActivity.Kind) -> Bool {
            switch (self, kind) {
            case (.all, _):
                return true
            case (.follows, .follow):
                return true
            case (.hypes, .hype), (.hypes, .milestone), (.hypes, .reaction):
                return true
            case (.comments, .comment), (.comments, .mention):
                return true
            case (.social, .repost), (.social, .collect), (.social, .remix),
                 (.social, .newPost), (.social, .discovery), (.social, .storyView),
                 (.social, .questComplete), (.social, .levelUp), (.social, .eventReminder):
                return true
            case (.sales, .sale), (.sales, .outbid):
                return true
            case (.offers, .offer), (.offers, .offerUpdate):
                return true
            default:
                return false
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var openingAssetId: UUID?
    @State private var selectedAsset: DigitalAsset?
    private let assetRepo = DigitalAssetRepository()

    private var filtered: [SocialActivity] {
        store.visibleItems.filter { filter.matches($0.kind) }
    }
    private var newItems: [SocialActivity] { filtered.filter(store.isNew) }
    private var earlierItems: [SocialActivity] { filtered.filter { !store.isNew($0) } }

    var body: some View {
        List {
            Section {
                filterChips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !store.hasLoaded && store.items.isEmpty {
                ForEach(0..<6, id: \.self) { _ in
                    ARRowSkeleton()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else if filtered.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                if !newItems.isEmpty {
                    Section { rows(newItems) } header: { sectionHeader("New") }
                }
                if !earlierItems.isEmpty {
                    Section { rows(earlierItems) } header: { sectionHeader("Earlier") }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(ARDesign.screenBackground.ignoresSafeArea())
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await store.refresh() }
        .task { await store.refresh(force: false) }
        .onAppear {
            store.isViewing = true
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["activity-summary"])
        }
        .onDisappear {
            store.isViewing = false
            store.markAllSeen()
        }
        .sheet(item: $selectedAsset) { asset in
            AssetDetailSheet(
                asset: asset,
                onOpenCreator: { dashboardState.path.append(.profile(userId: asset.userId)) },
                onOpenProfile: { dashboardState.path.append(.profile(userId: $0)) }
            )
        }
    }

    // MARK: Pieces

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { f in
                    ARFilterChip(title: f.rawValue, icon: f.icon, isActive: filter == f) {
                        ARHaptics.tick()
                        withAnimation(ARDesign.spring) { filter = f }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.bold())
            .foregroundColor(.primary)
            .textCase(nil)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        ARInlineEmptyState(
            icon: filter == .all ? "bell.badge" : filter.icon,
            title: filter == .all ? "No activity yet" : "No \(filter.rawValue.lowercased()) yet",
            subtitle: "When people follow you, hype, comment on, discover or make offers for your creations — or someone you follow drops something new — you'll see it here.",
            actionTitle: "Create something",
            action: { dashboardState.path.append(.create) }
        )
    }

    private func rows(_ items: [SocialActivity]) -> some View {
        ForEach(items) { item in
            ActivityRow(
                item: item,
                actor: item.actorId.flatMap { creators.creator($0) },
                isNew: store.isNew(item),
                isOpening: openingAssetId == item.asset?.id && item.asset != nil,
                onOpenActor: {
                    if let actor = item.actorId {
                        dashboardState.path.append(.profile(userId: actor))
                    } else {
                        openAsset(item.asset)
                    }
                },
                onOpenAsset: { openAsset(item.asset) }
            )
            .listRowBackground(store.isNew(item) ? Color.purple.opacity(0.07) : Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if store.source == .server {
                    Button(role: .destructive) {
                        withAnimation { store.remove(item) }
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func openAsset(_ ref: ActivityAssetRef?) {
        guard let ref, openingAssetId == nil else { return }
        openingAssetId = ref.id
        Task {
            defer { openingAssetId = nil }
            if let asset = await assetRepo.fetchAsset(id: ref.id) {
                selectedAsset = asset
            }
        }
    }
}

// MARK: - Row

private struct ActivityRow: View {
    let item: SocialActivity
    let actor: ARCreator?
    let isNew: Bool
    let isOpening: Bool
    let onOpenActor: () -> Void
    let onOpenAsset: () -> Void

    private var name: String { actor?.displayName ?? "Someone" }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenActor) {
                avatar
                    .overlay(alignment: .bottomTrailing) { kindBadge }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.actorId == nil ? "Open \(item.asset?.name ?? "creation")" : "Open \(name)'s profile")

            message
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if case .follow = item.kind { onOpenActor() } else { onOpenAsset() }
                }

            trailing
        }
    }

    /// Milestones have no actor, so they show a trophy tile instead of a face.
    @ViewBuilder
    private var avatar: some View {
        if item.actorId == nil {
            ZStack {
                Circle().fill(AppColors.purplePinkGradient)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 46, height: 46)
        } else {
            ARAvatarView(url: actor?.avatarUrl, name: name, size: 46)
        }
    }

    private var kindBadge: some View {
        let (icon, colors): (String, [Color]) = {
            switch item.kind {
            case .follow:      return ("person.fill.badge.plus", [.purple, .pink])
            case .hype:        return ("bolt.fill", [.yellow, .orange])
            case .comment:     return ("bubble.right.fill", [.blue, .cyan])
            case .mention:     return ("at", [.blue, .indigo])
            case .offer:       return ("tag.fill", [.green, .mint])
            case .offerUpdate(let accepted, _):
                return accepted ? ("checkmark", [.green, .mint]) : ("xmark", [.gray, .secondary])
            case .newPost:     return ("sparkles", [.pink, .purple])
            case .discovery:   return ("location.north.fill", [.teal, .blue])
            case .milestone:   return ("flame.fill", [.orange, .red])
            case .repost:      return ("arrow.2.squarepath", [.cyan, .blue])
            case .collect:     return ("square.stack.3d.up.fill", [.indigo, .purple])
            case .reaction:    return ("face.smiling.fill", [.pink, .orange])
            case .remix:       return ("wand.and.stars", [.purple, .blue])
            case .questComplete, .levelUp:
                               return ("trophy.fill", [.yellow, .orange])
            case .sale:        return ("dollarsign.circle.fill", [.green, .mint])
            case .outbid:      return ("arrow.down.circle.fill", [.orange, .red])
            case .eventReminder: return ("calendar", [.teal, .cyan])
            case .storyView:   return ("circle.dashed", [.pink, .purple])
            }
        }()
        return Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().strokeBorder(ARDesign.screenBackground, lineWidth: 2))
            .offset(x: 3, y: 3)
    }

    private var message: some View {
        let assetName = item.asset?.name ?? "your creation"
        var text = item.actorId == nil ? Text("") : Text(name).bold()
        if actor?.isVerified == true { text = text + Text(" \(Image(systemName: "checkmark.seal.fill"))").foregroundColor(.blue) }
        switch item.kind {
        case .mention(let body):
            text = text + Text(" mentioned you on ") + Text(item.asset?.name ?? "a creation").bold() + Text(": ")
                + Text("“\(body)”").foregroundColor(.secondary)
        case .offerUpdate(let accepted, let amount):
            text = text + Text(accepted ? " accepted your " : " declined your ")
            if let amount { text = text + Text(amount, format: .currency(code: "USD")).bold() + Text(" ") }
            text = text + Text("offer for ") + Text(item.asset?.name ?? "a creation").bold()
                + Text(accepted ? ". 🎉" : ".")
        case .newPost:
            text = text + Text(" dropped a new creation: ") + Text(item.asset?.name ?? "Untitled").bold()
                + Text(". Go find it in AR.")
        case .discovery:
            text = text + Text(" discovered ") + Text(assetName).bold() + Text(" in AR.")
        case .milestone(let metric, let count):
            text = metric == "views"
                ? Text("\(count.compactFormatted) explorers").bold() + Text(" have found ") + Text(assetName).bold() + Text(" 👀")
                : Text(assetName).bold() + Text(" just hit ") + Text("\(count.compactFormatted) hypes").bold() + Text(" 🔥")
        case .follow:
            text = text + Text(" started following you.")
        case .hype:
            text = text + Text(" hyped ") + Text(assetName).bold() + Text(".")
        case .comment(let body):
            text = text + Text(" commented on ") + Text(assetName).bold() + Text(": ")
                + Text("“\(body)”").foregroundColor(.secondary)
        case .offer(let amount, let status):
            text = text + Text(" offered ") + Text(amount, format: .currency(code: "USD")).bold()
                + Text(" for ") + Text(assetName).bold()
                + Text(status.lowercased() == "pending" ? "." : " · \(status.capitalized).")
        case .repost:
            text = text + Text(" reposted ") + Text(assetName).bold() + Text(".")
        case .collect:
            text = text + Text(" saved ") + Text(assetName).bold() + Text(" to a board.")
        case .reaction(let emoji):
            text = text + Text(" reacted \(emoji) to ") + Text(assetName).bold() + Text(".")
        case .remix:
            text = text + Text(" remixed ") + Text(assetName).bold() + Text(".")
        case .questComplete:
            text = Text("Quest complete — keep exploring.")
        case .levelUp:
            text = Text("You leveled up in your Passport.")
        case .sale:
            text = text + Text(" bought ") + Text(assetName).bold() + Text(".")
        case .outbid:
            text = Text("You were outbid on ") + Text(assetName).bold() + Text(".")
        case .eventReminder:
            text = Text("An AR event is starting soon.")
        case .storyView:
            text = text + Text(" viewed your story.")
        }
        if let date = item.date {
            text = text + Text("  \(date.shortRelative)").foregroundColor(.secondary)
        }
        return text
            .font(.subheadline)
            .foregroundColor(.primary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trailing: some View {
        if case .follow = item.kind, let actorId = item.actorId {
            ARFollowButton(userId: actorId, style: .compact, followTitle: "Follow back")
        } else {
            Button(action: onOpenAsset) {
                ZStack {
                    AsyncImage(url: item.asset?.thumbUrl.flatMap(URL.init(string:))) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            AppColors.purplePinkGradient.opacity(0.35)
                            Image(systemName: "cube.transparent")
                                .foregroundColor(.white)
                        }
                    }
                    if isOpening {
                        Color.black.opacity(0.4)
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.asset?.name ?? "creation")")
        }
    }
}
