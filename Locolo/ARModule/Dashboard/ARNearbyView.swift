//
//  ARNearbyView.swift
//  Locolo
//
//  The Nearby tab: a full-screen map of AR assets around the user with
//  category filtering, a synced bottom carousel, and quick access to
//  the AR viewer. Builds on MapViewModel (PostGIS get_nearby_assets RPC)
//  and replaces the old bare MapView.
//

import SwiftUI
import MapKit

struct ARNearbyView: View {
    var onDismiss: (() -> Void)? = nil

    @StateObject private var vm = MapViewModel()
    @ObservedObject private var safety = SafetyService.shared
    @EnvironmentObject private var dashboardState: ARDashboardState

    @State private var detailAsset: DigitalAsset?
    @State private var streetViewAsset: DigitalAsset?
    @State private var selectedAssetId: UUID?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var categoryFilter: String = "all"
    @State private var lastFetchTime: Date = .distantPast
    @State private var lastZoomLevel: Double = 0
    @State private var hasCenteredOnUser = false
    @State private var searchText = ""
    @State private var searchResults: [DigitalAsset] = []
    @State private var isSearching = false
    @State private var navigateAsset: DigitalAsset?
    @FocusState private var searchFocused: Bool

    /// ±2.5 km around the user = the 5 km square the map opens on.
    private static let fiveKmSpan = MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)

    private let panThrottleInterval: TimeInterval = 1.5
    private let minZoomChange: Double = 0.5
    private let categories = ["all", "art", "photo", "3d", "audio"]

    private var visibleAssets: [DigitalAsset] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return vm.assets.filter { asset in
            if !q.isEmpty {
                let hay = [asset.name, asset.description, asset.displayLocation, asset.categoryLabel]
                    .compactMap { $0?.lowercased() }.joined(separator: " ")
                guard hay.contains(q) else { return false }
            }
            guard asset.latitude != nil, asset.longitude != nil, !safety.isHidden(asset) else { return false }
            return categoryFilter == "all"
                || asset.normalizedCategory == categoryFilter
        }
    }

    var body: some View {
        ZStack {
            map

            if vm.isLoading {
                ProgressView("Scanning area…")
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 10) {
                ARGlassHeader(title: "Nearby", subtitle: "AR assets around you", onExit: onDismiss) {
                    ARHeaderIconButton(icon: "location.fill", label: "Center on me") {
                        centerOnUser(animated: true)
                    }
                    ARHeaderIconButton(icon: "arkit", label: "Open AR viewer", prominent: true) {
                        dashboardState.path.append(.viewer)
                    }
                }
                searchBar
                if searchFocused && !searchText.isEmpty { searchResultsList }
                filterRow
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !visibleAssets.isEmpty {
                assetCarousel
            }
        }
        .task {
            vm.requestLocation()
            centerOnUser(animated: false)
        }
        .onChange(of: vm.userCoordinate?.latitude) { _, _ in
            if !hasCenteredOnUser { centerOnUser(animated: true) }
        }
        .task(id: searchText) { await searchServer() }
        .fullScreenCover(item: $navigateAsset) { asset in
            AssetNavigationView(asset: asset)
        }
        .sheet(item: $detailAsset) { asset in
            AssetDetailSheet(
                asset: asset,
                onOpenCreator: { dashboardState.path.append(.profile(userId: asset.userId)) },
                onOpenProfile: { dashboardState.path.append(.profile(userId: $0)) }
            )
        }
        .sheet(item: $streetViewAsset) { asset in
            ARStreetViewSheet(asset: asset)
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            UserAnnotation()

            ForEach(visibleAssets) { asset in
                if let lat = asset.latitude, let lon = asset.longitude {
                    Annotation(
                        asset.name ?? "Artwork",
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    ) {
                        assetPin(asset)
                    }
                }
            }
        }
        .mapControls {
            MapCompass()
        }
        .ignoresSafeArea()
        .onMapCameraChange { context in
            handleCameraChange(context.region)
        }
    }

    private func assetPin(_ asset: DigitalAsset) -> some View {
        let isSelected = selectedAssetId == asset.id

        return Button {
            if isSelected {
                // Second tap on an already-focused pin opens the live street view.
                streetViewAsset = asset
            } else {
                ARHaptics.tick()
                withAnimation(ARDesign.spring) { selectedAssetId = asset.id }
            }
        } label: {
            AssetThumbnailView(asset: asset, cornerRadius: 22)
                .frame(width: isSelected ? 52 : 40, height: isSelected ? 52 : 40)
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [.purple, .pink],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        lineWidth: isSelected ? 3 : 2
                    )
                )
                .clipShape(Circle())
                .shadow(color: Color.purple.opacity(0.35), radius: 6, x: 0, y: 3)
        }
        .accessibilityLabel(asset.name ?? "AR asset")
        .accessibilityHint(isSelected ? "Opens street view" : "Focuses the map on this asset")
    }

    private func handleCameraChange(_ region: MKCoordinateRegion) {
        let span = region.span
        guard span.longitudeDelta > 0.0001 else { return }

        let mapWidth = Double(UIScreen.main.bounds.width)
        let zoom = log2(360.0 * (mapWidth / 256.0) / span.longitudeDelta)

        let zoomChanged = abs(zoom - lastZoomLevel) >= minZoomChange
        let now = Date()
        let timeSinceLastFetch = now.timeIntervalSince(lastFetchTime)

        // Always refetch on a real zoom change; throttle plain panning.
        if zoomChanged || timeSinceLastFetch >= panThrottleInterval {
            lastFetchTime = now
            lastZoomLevel = zoom
            vm.region = region

            Task {
                await vm.fetchAssetsFor(region: region, zoomLevel: zoom)
            }
        } else {
            vm.region = region
        }
    }

    // MARK: - Location & search

    /// Frames a 5 km square around the user (live fix, else last stored).
    private func centerOnUser(animated: Bool) {
        guard let coord = vm.userCoordinate ?? LocationManager.shared.userLocation
                ?? LocationManager.shared.latestStoredLocation else { return }
        hasCenteredOnUser = true
        let region = MKCoordinateRegion(center: coord, span: Self.fiveKmSpan)
        if animated {
            withAnimation(.easeInOut(duration: 0.8)) { cameraPosition = .region(region) }
        } else {
            cameraPosition = .region(region)
        }
        Task { await vm.fetchAssetsFor(region: region, zoomLevel: 13) }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search assets on the map", text: $searchText)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = ""; searchResults = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    /// Matches beyond the loaded map area, from the server (name / place).
    private var searchResultsList: some View {
        let merged = (visibleAssets + searchResults.filter { r in !visibleAssets.contains { $0.id == r.id } })
            .filter { !safety.isHidden($0) }
            .prefix(8)
        return VStack(spacing: 0) {
            if merged.isEmpty {
                Text(isSearching ? "Searching…" : "No assets match \"\(searchText)\"")
                    .font(.footnote).foregroundStyle(.secondary).padding(14)
            }
            ForEach(Array(merged)) { asset in
                Button { focus(asset) } label: {
                    HStack(spacing: 10) {
                        AssetThumbnailView(asset: asset, cornerRadius: 8).frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(asset.name ?? "Untitled").font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text([asset.displayLocation, asset.distanceLabel].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 58)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func focus(_ asset: DigitalAsset) {
        searchFocused = false
        guard let lat = asset.latitude, let lon = asset.longitude else { return }
        if !vm.assets.contains(where: { $0.id == asset.id }) { vm.assets.append(asset) }
        searchText = ""
        withAnimation(ARDesign.spring) {
            selectedAssetId = asset.id
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))
        }
    }

    private func searchServer() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { searchResults = []; return }
        isSearching = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        searchResults = await AssetSearch.byName(q)
        isSearching = false
    }

    // MARK: - Filters

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    ARFilterChip(
                        title: category == "all" ? "All" : category.capitalized,
                        isActive: categoryFilter == category
                    ) {
                        ARHaptics.tick()
                        withAnimation(ARDesign.spring) { categoryFilter = category }
                    }
                }

                Spacer(minLength: 0)

                Text("\(visibleAssets.count) found")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Bottom carousel

    private var assetCarousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(visibleAssets) { asset in
                        nearbyCard(asset)
                            .id(asset.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: selectedAssetId) { _, newId in
                guard let newId else { return }
                withAnimation(ARDesign.spring) {
                    proxy.scrollTo(newId, anchor: .center)
                }
                if let asset = visibleAssets.first(where: { $0.id == newId }),
                   let lat = asset.latitude, let lon = asset.longitude {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                        ))
                    }
                }
            }
        }
    }

    private func nearbyCard(_ asset: DigitalAsset) -> some View {
        let isSelected = selectedAssetId == asset.id

        return Button {
            if isSelected {
                detailAsset = asset
            } else {
                ARHaptics.tick()
                withAnimation(ARDesign.spring) { selectedAssetId = asset.id }
            }
        } label: {
            HStack(spacing: 10) {
                AssetThumbnailView(asset: asset)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.name ?? "Untitled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let cat = asset.categoryLabel {
                        Text(cat)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        if let dist = asset.distanceLabel {
                            Label(dist, systemImage: "location.fill")
                                .font(.caption2)
                                .foregroundColor(.cyan)
                        }
                        Label("\(asset.engagementScore)", systemImage: "flame.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                if isSelected {
                    VStack(spacing: 6) {
                        Button {
                            streetViewAsset = asset
                        } label: {
                            Image(systemName: "binoculars.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(AppColors.blueCyanMutedGradient))
                        }
                        .accessibilityLabel("Open street view")

                        Button {
                            navigateAsset = asset
                        } label: {
                            Image(systemName: "location.north.line.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.green.gradient))
                        }
                        .accessibilityLabel("Directions")

                        Button {
                            detailAsset = asset
                        } label: {
                            Image(systemName: "info")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(AppColors.purplePinkGradient))
                        }
                        .accessibilityLabel("Open asset details")
                    }
                } else {
                    Image(systemName: "chevron.right.circle")
                        .foregroundColor(.purple)
                }
            }
            .padding(10)
            .frame(width: 240, alignment: .leading)
            .arGlassCard(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink],
                                                           startPoint: .leading,
                                                           endPoint: .trailing))
                            : AnyShapeStyle(Color.clear),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(isSelected ? "Opens asset details" : "Centers the map on this asset")
    }
}

// MARK: - Street view sheet

/// Street-level view of where an asset lives.
///
/// Why it "never worked": the Google key's Cloud project has no billing, so
/// every Street View request returned 403 REQUEST_DENIED and the sphere stayed
/// grey. Now we ask Google's free metadata endpoint first; if Google can serve
/// imagery we show the stitched panorama + model, otherwise we fall back to
/// Apple Look Around (free, no key), and if neither has coverage we say why.
private struct ARStreetViewSheet: View {
    let asset: DigitalAsset

    @Environment(\.dismiss) private var dismiss
    @State private var source: Source = .checking

    enum Source: Equatable {
        case checking
        case google
        case apple(MKLookAroundScene)
        case unavailable(String)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch source {
                case .checking:
                    ProgressView("Finding street imagery…").tint(.white).foregroundStyle(.white)
                case .google:
                    PanoramaSceneView(asset: asset)
                case .apple(let scene):
                    LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: true)
                case .unavailable(let reason):
                    VStack(spacing: 12) {
                        Image(systemName: "binoculars").font(.system(size: 40)).foregroundStyle(.white.opacity(0.7))
                        Text("No street view here").font(.headline).foregroundStyle(.white)
                        Text(reason)
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(9)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .accessibilityLabel("Close street view")

                VStack(alignment: .leading, spacing: 1) {
                    Text(asset.name ?? "Untitled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let loc = asset.displayLocation {
                        Text(loc)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Label(sourceLabel, systemImage: "binoculars.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .task { await resolve() }
    }

    private var sourceLabel: String {
        switch source {
        case .google: return "Google Street View"
        case .apple: return "Apple Look Around"
        default: return "Street View"
        }
    }

    private func resolve() async {
        guard let lat = asset.latitude, let lon = asset.longitude else {
            source = .unavailable("This asset has no saved location.")
            return
        }
        let googleStatus = await StreetViewProbe.googleStatus(lat: lat, lon: lon)
        if googleStatus == "OK" { source = .google; return }

        let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        if let scene = try? await request.scene {
            source = .apple(scene)
            return
        }
        switch googleStatus {
        case "REQUEST_DENIED":
            source = .unavailable("Google Street View is switched off for this app (the Google Cloud project needs billing enabled), and Apple Look Around has no coverage here.")
        case "ZERO_RESULTS", "NOT_FOUND":
            source = .unavailable("Neither Google nor Apple has street-level imagery at this spot.")
        default:
            source = .unavailable("Couldn't reach street imagery. Check your connection and try again.")
        }
    }
}

/// Google's Street View metadata endpoint is free and tells us whether a
/// panorama exists (and whether the key is allowed) before we spend quota.
enum StreetViewProbe {
    static func googleStatus(lat: Double, lon: Double) async -> String {
        guard let url = URL(string: "https://maps.googleapis.com/maps/api/streetview/metadata?location=\(lat),\(lon)&radius=60&key=\(keys.googleAPIKey)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String
        else { return "UNKNOWN_ERROR" }
        return status
    }
}
