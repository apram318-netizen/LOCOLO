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

    private let panThrottleInterval: TimeInterval = 1.5
    private let minZoomChange: Double = 0.5
    private let categories = ["all", "art", "photo", "3d", "audio"]

    private var visibleAssets: [DigitalAsset] {
        vm.assets.filter { asset in
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
                    ARHeaderIconButton(icon: "arkit", label: "Open AR viewer", prominent: true) {
                        dashboardState.path.append(.viewer)
                    }
                }
                filterRow
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !visibleAssets.isEmpty {
                assetCarousel
            }
        }
        .task { vm.requestLocation() }
        .sheet(item: $detailAsset) { asset in
            AssetDetailSheet(asset: asset, onOpenCreator: {
                dashboardState.path.append(.profile(userId: asset.userId))
            })
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

/// Full-screen live street view: PanoramaSceneView stitches Google Street
/// View imagery around the asset's coordinates and places the 3D model in
/// the middle, with a small glass header so the user knows what they see.
private struct ARStreetViewSheet: View {
    let asset: DigitalAsset

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            PanoramaSceneView(asset: asset)
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

                Label("Street View", systemImage: "binoculars.fill")
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
    }
}
