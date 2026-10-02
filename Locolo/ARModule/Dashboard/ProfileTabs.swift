//
//  ProfileTabs.swift
//  Locolo
//
//  Instagram-style tabbed body for a creator profile (V3 feedback):
//    1. Stats    — Explorer Passport (level, XP, streak) + creator stats.
//    2. Map      — everything they've placed or own, on a map + grid.
//    3. Memories — their memories (story grid) and their posts.
//    4. Reposts  — drops they've re-dropped.
//

import SwiftUI
import MapKit
import Supabase

enum ProfileTab: String, CaseIterable, Identifiable {
    case stats, map, memories, reposts
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .stats: return "chart.bar.xaxis"
        case .map: return "map"
        case .memories: return "camera.aperture"
        case .reposts: return "arrow.2.squarepath"
        }
    }

    var title: String {
        switch self {
        case .stats: return "Passport"
        case .map: return "Map"
        case .memories: return "Memories"
        case .reposts: return "Reposts"
        }
    }
}

struct ProfileTabBar: View {
    @Binding var selection: ProfileTab
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases) { tab in
                Button {
                    ARHaptics.tick()
                    withAnimation(ARDesign.spring) { selection = tab }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: selection == tab ? .bold : .regular))
                            .foregroundStyle(selection == tab ? .primary : .secondary)
                        ZStack {
                            Rectangle().fill(.clear).frame(height: 2)
                            if selection == tab {
                                Rectangle().fill(Color.primary).frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.top, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(ARDesign.hairline).frame(height: 0.5) }
    }
}

// MARK: - 1. Stats / Passport

struct ProfileStatsTab: View {
    let userId: UUID
    let assets: [DigitalAsset]
    let followers: Int
    let following: Int

    @State private var progress: Row?
    @ObservedObject private var engagement = EngagementStore.shared
    @ObservedObject private var memories = MemoryStore.shared

    struct Row: Decodable {
        let xp: Int
        let level: Int
        let streak_days: Int
        let discoveries: Int
        let created_count: Int
    }

    private static let levelTitles = ["Wanderer", "Scout", "Pathfinder", "Trailblazer", "Cartographer", "Legend"]
    private static let levelXP = [0, 250, 750, 1500, 3000, 6000]

    var body: some View {
        VStack(spacing: 16) {
            passportCard
            statsGrid
            topAssets
        }
        .task {
            progress = try? await SupabaseManager.shared.client.from("user_progress")
                .select("xp, level, streak_days, discoveries, created_count")
                .eq("user_id", value: userId)
                .single()
                .execute()
                .value
            await memories.load(user: userId)
        }
    }

    private var passportCard: some View {
        let level = max(1, min(6, progress?.level ?? 1))
        let xp = progress?.xp ?? 0
        let floor = Self.levelXP[level - 1]
        let next = level < 6 ? Self.levelXP[level] : nil
        let fraction = next.map { Double(xp - floor) / Double(max(1, $0 - floor)) } ?? 1
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 8)
                Circle().trim(from: 0, to: fraction)
                    .stroke(AppColors.purplePinkGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(level)").font(.title.bold())
                    Text("LVL").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text("EXPLORER PASSPORT").font(.caption2.weight(.heavy)).kerning(1.2).foregroundStyle(.secondary)
                Text(Self.levelTitles[level - 1]).font(.title3.bold())
                Text("\(xp.compactFormatted) XP" + (next.map { " · \($0 - xp) to next" } ?? " · max level"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(progress?.streak_days ?? 0)d streak", systemImage: "flame.fill").foregroundStyle(.orange)
                    Label("\(progress?.discoveries ?? 0) found", systemImage: "binoculars.fill").foregroundStyle(.cyan)
                }
                .font(.caption.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .arGlassCard(cornerRadius: 20)
    }

    private var statsGrid: some View {
        let hypes = assets.reduce(0) { $0 + engagement.hypeCount(for: $1) }
        let explorers = assets.reduce(0) { $0 + $1.viewCount }
        let value = assets.compactMap(\.currentValue).reduce(0, +)
        let items: [(String, String, String)] = [
            ("cube.transparent", "\(assets.count)", "Drops"),
            ("bolt.fill", hypes.compactFormatted, "Hypes"),
            ("eye.fill", explorers.compactFormatted, "Explorers"),
            ("camera.aperture", "\(memories.byUser[userId]?.count ?? 0)", "Memories"),
            ("person.2.fill", followers.compactFormatted, "Followers"),
            ("dollarsign.circle.fill", value > 0 ? String(format: "$%.0f", value) : "—", "Portfolio"),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(items, id: \.2) { icon, value, label in
                VStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(AppColors.purplePinkGradient)
                    Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .arGlassCard(cornerRadius: 16)
            }
        }
    }

    @ViewBuilder
    private var topAssets: some View {
        let ranked = assets.sorted { engagement.hypeCount(for: $0) > engagement.hypeCount(for: $1) }.prefix(3)
        if !ranked.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Top drops").font(.headline)
                ForEach(Array(ranked.enumerated()), id: \.element.id) { i, asset in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
                        AssetThumbnailView(asset: asset, cornerRadius: 10).frame(width: 44, height: 44)
                        Text(asset.name ?? "Untitled").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Label(engagement.hypeCount(for: asset).compactFormatted, systemImage: "bolt.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(.yellow)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .arGlassCard(cornerRadius: 20)
        }
    }
}

// MARK: - 2. Map (placed + owned)

struct ProfileMapTab: View {
    let userId: UUID
    let placed: [DigitalAsset]
    let onSelect: (DigitalAsset) -> Void

    @State private var owned: [DigitalAsset] = []
    @State private var filter = 0   // 0 all, 1 placed, 2 owned

    private var shown: [DigitalAsset] {
        let ownedOnly = owned.filter { o in !placed.contains { $0.id == o.id } }
        switch filter {
        case 1: return placed
        case 2: return owned
        default: return placed + ownedOnly
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Show", selection: $filter) {
                Text("All").tag(0)
                Text("Placed (\(placed.count))").tag(1)
                Text("Owned (\(owned.count))").tag(2)
            }
            .pickerStyle(.segmented)

            Map(initialPosition: .automatic) {
                ForEach(shown.filter { $0.latitude != nil && $0.longitude != nil }) { asset in
                    Annotation(asset.name ?? "Asset",
                               coordinate: CLLocationCoordinate2D(latitude: asset.latitude!, longitude: asset.longitude!)) {
                        Button { onSelect(asset) } label: {
                            AssetThumbnailView(asset: asset, cornerRadius: 18)
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(
                                    asset.userId == userId ? AnyShapeStyle(AppColors.purplePinkGradient)
                                                           : AnyShapeStyle(Color.green), lineWidth: 2.5))
                                .shadow(radius: 3)
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .id(filter)   // re-fit the camera when the filter changes

            HStack(spacing: 14) {
                Label("Placed", systemImage: "circle.fill").foregroundStyle(.pink)
                Label("Owned", systemImage: "circle.fill").foregroundStyle(.green)
                Spacer()
            }
            .font(.caption2.weight(.semibold))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)],
                      spacing: 3) {
                ForEach(shown) { asset in
                    Button { onSelect(asset) } label: {
                        AssetThumbnailView(asset: asset, cornerRadius: 0)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if shown.isEmpty {
                ARInlineEmptyState(icon: "map", title: "Nothing on the map yet")
            }
        }
        .task { owned = await Self.loadOwned(userId) }
    }

    /// Assets this user bought (owner_id = them but created by someone else).
    static func loadOwned(_ userId: UUID) async -> [DigitalAsset] {
        struct Row: Decodable { let asset_id: UUID }
        guard let rows: [Row] = try? await SupabaseManager.shared.client.from("digital_assets")
            .select("asset_id").eq("owner_id", value: userId).neq("user_id", value: userId)
            .limit(30).execute().value else { return [] }
        var out: [DigitalAsset] = []
        for row in rows {
            if let a = await DigitalAssetRepository().fetchAsset(id: row.asset_id) { out.append(a) }
        }
        return SafetyService.shared.visible(out)
    }
}

// MARK: - 3. Memories + posts

struct ProfileMemoriesTab: View {
    let userId: UUID
    var onOpenProfile: ((UUID) -> Void)? = nil
    var onOpenLink: ((PostLink) -> Void)? = nil

    @ObservedObject private var memories = MemoryStore.shared
    @ObservedObject private var posts = PostStore.shared
    @State private var viewer: MemoryViewerItem?
    @State private var showPosts = false

    var body: some View {
        let mine = memories.byUser[userId] ?? []
        let theirPosts = posts.byUser[userId] ?? []
        VStack(spacing: 14) {
            Picker("", selection: $showPosts) {
                Text("Memories (\(mine.count))").tag(false)
                Text("Posts (\(theirPosts.count))").tag(true)
            }
            .pickerStyle(.segmented)

            if showPosts {
                if theirPosts.isEmpty {
                    ARInlineEmptyState(icon: "text.quote", title: "No posts yet")
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(theirPosts) { post in
                            PostCard(post: post, onOpenProfile: onOpenProfile, onOpenLink: onOpenLink)
                        }
                    }
                }
            } else if mine.isEmpty {
                ARInlineEmptyState(icon: "camera.aperture", title: "No memories yet",
                                   subtitle: memories.available ? "Memories are photos and clips captured in AR." : "Memories turn on after the next update.")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(Array(mine.enumerated()), id: \.element.id) { i, memory in
                        Button { viewer = MemoryViewerItem(memories: mine, start: i) } label: {
                            AsyncImage(url: memory.previewURL) { $0.resizable().scaledToFill() }
                                placeholder: { Color.purple.opacity(0.2) }
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .aspectRatio(9 / 16, contentMode: .fill)
                                .clipped()
                                .overlay(alignment: .topTrailing) {
                                    if memory.isVideo {
                                        Image(systemName: "play.fill").font(.caption2).foregroundStyle(.white).padding(6)
                                    }
                                }
                                .overlay(alignment: .bottomLeading) {
                                    Label(memory.likeCount.compactFormatted, systemImage: "heart.fill")
                                        .font(.caption2.weight(.bold)).foregroundStyle(.white).padding(6)
                                        .shadow(radius: 2)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            async let m: [AssetMemory] = memories.load(user: userId)
            async let p: [UserPost] = posts.load(user: userId)
            _ = await (m, p)
        }
        .fullScreenCover(item: $viewer) { MemoryViewer(memories: $0.memories, startIndex: $0.start) }
    }
}

// MARK: - 4. Reposts

struct ProfileRepostsTab: View {
    let userId: UUID
    let onSelect: (DigitalAsset) -> Void

    @State private var assets: [DigitalAsset] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                ProgressView().padding(.top, 30)
            } else if assets.isEmpty {
                ARInlineEmptyState(icon: "arrow.2.squarepath", title: "No reposts yet",
                                   subtitle: "Drops they re-drop show up here.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(assets) { asset in
                        Button { onSelect(asset) } label: {
                            AssetThumbnailView(asset: asset, cornerRadius: 16)
                                .aspectRatio(1, contentMode: .fill)
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: "arrow.2.squarepath")
                                        .font(.caption.bold()).foregroundStyle(.white)
                                        .padding(6).background(Circle().fill(.black.opacity(0.4))).padding(8)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    Text(asset.name ?? "Untitled").font(.caption.weight(.semibold))
                                        .foregroundStyle(.white).lineLimit(1).padding(8).shadow(radius: 3)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            struct Row: Decodable { let asset_id: UUID }
            let rows: [Row] = (try? await SupabaseManager.shared.client.from("reposts")
                .select("asset_id").eq("user_id", value: userId)
                .order("created_at", ascending: false).limit(40)
                .execute().value) ?? []
            var out: [DigitalAsset] = []
            for row in rows {
                if let a = await DigitalAssetRepository().fetchAsset(id: row.asset_id) { out.append(a) }
            }
            assets = SafetyService.shared.visible(out)
            loaded = true
        }
    }
}
