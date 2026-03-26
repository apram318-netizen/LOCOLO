import SwiftUI
import MapKit


struct MapView: View {
    @StateObject private var vm = MapViewModel()
    @State private var selectedAsset: DigitalAsset?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var lastFetchTime: Date = .distantPast
    @State private var lastZoomLevel: Double = 0
    
    private let panThrottleInterval: TimeInterval = 1.5 // Throttle pan movements
    private let minZoomChange: Double = 0.5 // Refresh if zoom changes by this much

    var body: some View {
        ZStack {
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(vm.assets.filter { $0.latitude != nil && $0.longitude != nil }) { asset in
                    if let lat = asset.latitude, let lon = asset.longitude {
                        Annotation(
                            asset.name ?? "Artwork",
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        ) {
                            Button { selectedAsset = asset } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.title2)
                                    Text(asset.name ?? "Artwork")
                                        .font(.caption2)
                                }
                                .padding(6)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .onMapCameraChange { context in
                let region = context.region
                let span = region.span
                
                // Safety check for division by zero
                guard span.longitudeDelta > 0.0001 else { return }
                
                let mapWidth = Double(UIScreen.main.bounds.width)
                let zoom = log2(360.0 * (mapWidth / 256.0) / span.longitudeDelta)
                
                let zoomChanged = abs(zoom - lastZoomLevel) >= minZoomChange
                let now = Date()
                let timeSinceLastFetch = now.timeIntervalSince(lastFetchTime)
                
                // Refresh if:
                // 1. Zoom changed significantly (always refresh on zoom)
                // 2. OR enough time passed since last fetch (throttle pan movements)
                if zoomChanged || timeSinceLastFetch >= panThrottleInterval {
                    lastFetchTime = now
                    lastZoomLevel = zoom
                    vm.region = region
                    
                    Task {
                        await vm.fetchAssetsFor(region: region, zoomLevel: zoom)
                    }
                } else {
                    // Still update region for display, but don't fetch
                    vm.region = region
                }
            }

            if vm.isLoading {
                ProgressView("Loading…")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }

            if let error = vm.errorMessage {
                Text(error)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding()
            }
        }
        .task {
            vm.requestLocation()
        }
        .sheet(item: $selectedAsset) { asset in
            if let lat = asset.latitude, let lon = asset.longitude {
                PanoramaSceneView(asset: asset)
                .ignoresSafeArea()
//                LookAroundSceneView(asset: asset)
//                       .ignoresSafeArea()
//                MapPanoramaView(
//                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
//                       )
//                       .frame(height: 300)
//                       .cornerRadius(12)
//                       .shadow(radius: 8)
            }
        }
    }
}
