//
//  AssetManageSheet.swift
//  Locolo
//
//  The asset's own settings / insights sheet (owner + creator):
//    * Growth — a trading-app style line chart (Robinhood / Stocks): big
//      current value, change vs. the start of the range in green/red, range
//      chips (1W 1M 3M 1Y ALL), metric chips (Value, Hypes, Explorers,
//      Memories, Comments, Offers) and press-and-drag scrubbing.
//    * Trading — accept offers on/off, marketplace shortcut.
//    * Presentation — name, description, custom thumbnail.
//    * Background alert — a sound that plays when someone walks past it with
//      Background AR on.
//    * Visibility + delete.
//
//  Server: get_asset_growth / update_asset_settings
//  (docs/migrations/2026_v3_memories_posts_growth.sql). Before that migration
//  the sheet still edits via the legacy owner UPDATE policy and shows today's
//  totals instead of history.
//

import SwiftUI
import Charts
import PhotosUI
import UniformTypeIdentifiers

struct AssetGrowthPoint: Identifiable, Decodable {
    var id: Date { day }
    let day: Date
    let hypes: Int
    let explorers: Int
    let comments: Int
    let memories: Int
    let offers: Int
    let value: Double?

    enum CodingKeys: String, CodingKey { case day, hypes, explorers, comments, memories, offers, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let dayString = try c.decode(String.self, forKey: .day)
        day = AssetGrowthPoint.dayFormatter.date(from: dayString) ?? Date()
        hypes = try c.decode(Int.self, forKey: .hypes)
        explorers = try c.decode(Int.self, forKey: .explorers)
        comments = try c.decode(Int.self, forKey: .comments)
        memories = try c.decode(Int.self, forKey: .memories)
        offers = try c.decode(Int.self, forKey: .offers)
        value = try c.decodeIfPresent(Double.self, forKey: .value)
    }

    init(day: Date, hypes: Int, explorers: Int, comments: Int, memories: Int, offers: Int, value: Double?) {
        self.day = day; self.hypes = hypes; self.explorers = explorers
        self.comments = comments; self.memories = memories; self.offers = offers; self.value = value
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

enum GrowthMetric: String, CaseIterable, Identifiable {
    case value = "Value", hypes = "Hypes", explorers = "Explorers", memories = "Memories", comments = "Comments", offers = "Offers"
    var id: String { rawValue }

    func read(_ p: AssetGrowthPoint) -> Double {
        switch self {
        case .value: return p.value ?? 0
        case .hypes: return Double(p.hypes)
        case .explorers: return Double(p.explorers)
        case .memories: return Double(p.memories)
        case .comments: return Double(p.comments)
        case .offers: return Double(p.offers)
        }
    }

    func format(_ v: Double) -> String {
        self == .value ? String(format: "$%.2f", v) : Int(v).compactFormatted
    }
}

enum GrowthRange: String, CaseIterable, Identifiable {
    case week = "1W", month = "1M", quarter = "3M", year = "1Y", all = "ALL"
    var id: String { rawValue }
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return 730
        }
    }
}

struct AssetManageSheet: View {
    let asset: DigitalAsset
    var onUpdated: ((DigitalAsset) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userVM: UserViewModel

    @State private var points: [AssetGrowthPoint] = []
    @State private var growthAvailable = true
    @State private var loadingGrowth = false
    @State private var metric: GrowthMetric = .hypes
    @State private var range: GrowthRange = .month
    @State private var scrubbed: AssetGrowthPoint?

    @State private var acceptsOffers = false
    @State private var visibility = "public"
    @State private var name = ""
    @State private var details = ""
    @State private var thumbItem: PhotosPickerItem?
    @State private var thumbPreview: UIImage?
    @State private var alertAudioName: String?
    @State private var alertAudioData: Data?
    @State private var clearAlertAudio = false
    @State private var alertRadius: Double = 60
    @State private var showAudioImporter = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var showMarketplace = false
    @ObservedObject private var features = AppFeatures.shared

    private var isOwner: Bool { userVM.currentUser?.id == asset.effectiveOwnerId }
    private var isCreator: Bool { userVM.currentUser?.id == asset.userId }

    var body: some View {
        NavigationStack {
            Form {
                Section { growthCard }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                if isOwner {
                    Section {
                        Toggle("Accept offers", isOn: $acceptsOffers)
                        if features.marketplaceEnabled {
                            Button { showMarketplace = true } label: {
                                Label(asset.isForSale == true ? "Manage listing" : "List for sale", systemImage: "storefront")
                            }
                        }
                        Picker("Who can see it", selection: $visibility) {
                            Text("Everyone").tag("public")
                            Text("Followers").tag("friends")
                            Text("Only me").tag("private")
                        }
                    } header: {
                        Text("Trading & visibility")
                    } footer: {
                        Text("Turning offers off hides the Make offer button. Pending offers stay until you answer them.")
                    }
                }

                if isCreator {
                    Section("Presentation") {
                        TextField("Name", text: $name)
                        TextField("Description", text: $details, axis: .vertical)
                            .lineLimit(2...6)
                        PhotosPicker(selection: $thumbItem, matching: .images) {
                            HStack {
                                Label("Thumbnail", systemImage: "photo")
                                Spacer()
                                Group {
                                    if let thumbPreview {
                                        Image(uiImage: thumbPreview).resizable().scaledToFill()
                                    } else {
                                        AssetThumbnailView(asset: asset, cornerRadius: 8)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Section {
                        Button { showAudioImporter = true } label: {
                            HStack {
                                Label("Alert sound", systemImage: "speaker.wave.2")
                                Spacer()
                                Text(alertAudioName ?? (clearAlertAudio ? "None" : "Choose…"))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if alertAudioName != nil {
                            Button("Remove sound", role: .destructive) {
                                alertAudioName = nil
                                alertAudioData = nil
                                clearAlertAudio = true
                            }
                        }
                        VStack(alignment: .leading) {
                            Text("Plays within \(Int(alertRadius)) m")
                            Slider(value: $alertRadius, in: 20...300, step: 10)
                        }
                    } header: {
                        Text("Background alert")
                    } footer: {
                        Text("Explorers with Background AR on hear this when they walk past — even with the phone in their pocket.")
                    }
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }

                if isCreator {
                    Section {
                        Button("Delete asset", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(asset.name ?? "Manage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving { ProgressView() } else { Text("Save").bold() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear(perform: seed)
            .task(id: range) { await loadGrowth() }
            .onChange(of: thumbItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        thumbPreview = UIImage(data: data)
                    }
                }
            }
            .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), data.count < 5_000_000 {
                    alertAudioData = data
                    alertAudioName = url.lastPathComponent
                    clearAlertAudio = false
                } else {
                    message = "Pick an audio file under 5 MB."
                }
            }
            .confirmationDialog("Delete this asset for everyone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await deleteAsset() } }
            } message: {
                Text("Its memories, comments and offers are removed too. This can't be undone.")
            }
            .sheet(isPresented: $showMarketplace) { MarketplaceSheet(asset: asset) {} }
        }
    }

    // MARK: Growth card

    private var series: [AssetGrowthPoint] {
        if !points.isEmpty { return points }
        // Pre-migration fallback: a flat line at today's totals.
        let now = AssetGrowthPoint(day: Date(), hypes: asset.hypeCount, explorers: asset.viewCount,
                                   comments: EngagementStore.shared.commentCount(for: asset.id),
                                   memories: MemoryStore.shared.byAsset[asset.id]?.count ?? 0,
                                   offers: asset.activeOffers ?? 0, value: asset.currentValue)
        let start = AssetGrowthPoint(day: max(asset.createdAt, Calendar.current.date(byAdding: .day, value: -range.days, to: Date())!),
                                     hypes: 0, explorers: 0, comments: 0, memories: 0, offers: 0,
                                     value: asset.boughtPrice ?? asset.currentValue)
        return [start, now]
    }

    private var current: Double { metric.read(scrubbed ?? series.last!) }
    private var baseline: Double { metric.read(series.first!) }
    private var delta: Double { current - baseline }
    private var deltaPct: Double? { baseline == 0 ? nil : delta / baseline * 100 }
    private var trendColor: Color { delta >= 0 ? Color(hex: "22C55E") : Color(hex: "EF4444") }

    private var growthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.rawValue.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(metric.format(current))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(delta >= 0 ? "+" : "")\(metric.format(delta))")
                    if let pct = deltaPct { Text(String(format: "(%+.1f%%)", pct)) }
                    Text(scrubbed.map { $0.day.formatted(date: .abbreviated, time: .omitted) } ?? range.label)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(trendColor)
            }

            chart
                .frame(height: 200)

            HStack(spacing: 6) {
                ForEach(GrowthRange.allCases) { r in
                    Button(r.rawValue) {
                        ARHaptics.tick()
                        range = r
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(range == r ? trendColor.opacity(0.18) : .clear))
                    .foregroundStyle(range == r ? trendColor : .secondary)
                }
            }
            .frame(maxWidth: .infinity)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GrowthMetric.allCases) { m in
                        ARFilterChip(title: m.rawValue, isActive: metric == m) {
                            withAnimation { metric = m }
                        }
                    }
                }
            }

            if !growthAvailable {
                Label("Full history appears after the next server update. Showing today's totals.",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .padding(.vertical, 6)
    }

    private var chart: some View {
        let values = series.map(metric.read)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, 1)
        return Chart {
            ForEach(series) { p in
                AreaMark(x: .value("Day", p.day), yStart: .value("Min", lo - pad), yEnd: .value(metric.rawValue, metric.read(p)))
                    .foregroundStyle(LinearGradient(colors: [trendColor.opacity(0.28), trendColor.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", p.day), y: .value(metric.rawValue, metric.read(p)))
                    .foregroundStyle(trendColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            // Dotted baseline at the range's opening value, like a stock chart.
            RuleMark(y: .value("Open", baseline))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            if let scrubbed {
                RuleMark(x: .value("Day", scrubbed.day))
                    .foregroundStyle(.secondary)
                PointMark(x: .value("Day", scrubbed.day), y: .value(metric.rawValue, metric.read(scrubbed)))
                    .foregroundStyle(trendColor)
                    .symbolSize(80)
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(metric.format(d)).font(.caption2) }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                guard let plot = proxy.plotFrame else { return }
                                let x = g.location.x - geo[plot].origin.x
                                if let day: Date = proxy.value(atX: x) {
                                    let nearest = series.min { abs($0.day.timeIntervalSince(day)) < abs($1.day.timeIntervalSince(day)) }
                                    if nearest?.day != scrubbed?.day { ARHaptics.tick() }
                                    scrubbed = nearest
                                }
                            }
                            .onEnded { _ in scrubbed = nil }
                    )
            }
        }
        .overlay {
            if loadingGrowth && points.isEmpty { ProgressView() }
        }
        .animation(.easeInOut(duration: 0.3), value: metric)
    }

    // MARK: Data

    private func seed() {
        acceptsOffers = asset.acceptsOffers ?? false
        visibility = asset.normalizedVisibility
        name = asset.name ?? ""
        details = asset.description ?? ""
        metric = asset.currentValue != nil || asset.isForSale == true ? .value : .hypes
    }

    private func loadGrowth() async {
        loadingGrowth = true
        defer { loadingGrowth = false }
        struct Params: Encodable { let p_asset: UUID; let p_days: Int }
        do {
            let rows: [AssetGrowthPoint] = try await SupabaseManager.shared.client
                .rpc("get_asset_growth", params: Params(p_asset: asset.id, p_days: range.days))
                .execute()
                .value
            // Trim the empty run before the asset existed.
            let created = Calendar.current.startOfDay(for: asset.createdAt)
            points = rows.filter { $0.day >= created }
            if points.count == 1, let only = points.first {
                points.insert(AssetGrowthPoint(day: Calendar.current.date(byAdding: .day, value: -1, to: only.day)!,
                                               hypes: 0, explorers: 0, comments: 0, memories: 0, offers: 0,
                                               value: only.value), at: 0)
            }
            growthAvailable = true
        } catch {
            growthAvailable = !EngagementStore.isMissingSchema(error)
            points = []
        }
    }

    private func save() {
        isSaving = true
        message = nil
        Task {
            defer { isSaving = false }
            do {
                var thumbURL: String?
                if let thumbPreview,
                   let jpeg = thumbPreview.locoloDownscaled(maxSide: 900).jpegData(compressionQuality: 0.85) {
                    thumbURL = try await ObjStorageManager.shared.uploadFile(
                        path: "thumbnails/\(asset.id.uuidString.lowercased())-\(Int(Date().timeIntervalSince1970)).jpg",
                        fileData: jpeg, contentType: "image/jpeg")
                }
                var audioURL: String?
                if let alertAudioData, let alertAudioName {
                    let ext = (alertAudioName as NSString).pathExtension.isEmpty ? "m4a" : (alertAudioName as NSString).pathExtension
                    audioURL = try await ObjStorageManager.shared.uploadFile(
                        path: "alerts/\(asset.id.uuidString.lowercased()).\(ext)",
                        fileData: alertAudioData, contentType: "audio/\(ext == "mp3" ? "mpeg" : ext)")
                } else if clearAlertAudio {
                    audioURL = ""
                }

                struct Params: Encodable {
                    let p_asset: UUID
                    let p_accepts_offers: Bool?
                    let p_visibility: String?
                    let p_name: String?
                    let p_description: String?
                    let p_thumb_url: String?
                    let p_alert_audio_url: String?
                    let p_alert_radius_m: Double?
                }
                let params = Params(
                    p_asset: asset.id,
                    p_accepts_offers: isOwner ? acceptsOffers : nil,
                    p_visibility: isOwner ? visibility : nil,
                    p_name: isCreator ? name : nil,
                    p_description: isCreator ? details : nil,
                    p_thumb_url: isCreator ? thumbURL : nil,
                    p_alert_audio_url: isCreator ? audioURL : nil,
                    p_alert_radius_m: isCreator ? alertRadius : nil)
                do {
                    try await SupabaseManager.shared.client.rpc("update_asset_settings", params: params).execute()
                } catch where EngagementStore.isMissingSchema(error) {
                    try await legacyUpdate(thumbURL: thumbURL)
                }
                if let fresh = await DigitalAssetRepository().fetchAsset(id: asset.id) { onUpdated?(fresh) }
                ARHaptics.success()
                dismiss()
            } catch {
                ARHaptics.warning()
                message = "Couldn't save: \(Self.friendly(error))"
            }
        }
    }

    /// Before the V3 migration: plain owner UPDATE (creator-only by RLS).
    private func legacyUpdate(thumbURL: String?) async throws {
        struct Update: Encodable {
            let accepts_offers: Bool
            let visibility: String
            let name: String?
            let description: String?
            let thumb_url: String?
        }
        try await SupabaseManager.shared.client.from("digital_assets")
            .update(Update(accepts_offers: acceptsOffers, visibility: visibility,
                           name: name.isEmpty ? nil : name, description: details,
                           thumb_url: thumbURL ?? asset.thumbUrl), returning: .minimal)
            .eq("asset_id", value: asset.id)
            .execute()
    }

    private func deleteAsset() async {
        do {
            try await SupabaseManager.shared.client.from("digital_assets").delete()
                .eq("asset_id", value: asset.id).execute()
            ARHaptics.success()
            dismiss()
        } catch {
            message = "Couldn't delete: \(Self.friendly(error))"
        }
    }

    private static func friendly(_ error: Error) -> String {
        let raw = "\(error)".lowercased()
        if raw.contains("42501") || raw.contains("only the") { return "you don't have permission for that change." }
        return "check your connection and try again."
    }
}

private extension GrowthRange {
    var label: String {
        switch self {
        case .week: return "past week"
        case .month: return "past month"
        case .quarter: return "past 3 months"
        case .year: return "past year"
        case .all: return "all time"
        }
    }
}
