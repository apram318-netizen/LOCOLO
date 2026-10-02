//
//  AssetNavigationView.swift
//  Locolo
//
//  In-app turn-by-turn-lite to an asset: MapKit route (walk / drive), live
//  distance + ETA, step list, "Open in AR" once you're within 150 m, and a
//  hand-off to Apple Maps for full voice navigation.
//

import SwiftUI
import MapKit

struct AssetNavigationView: View {
    let asset: DigitalAsset

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var location = LocationManager.shared
    @State private var route: MKRoute?
    @State private var mode: TravelMode = .walk
    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var errorText: String?
    @State private var showAR = false
    @State private var showSteps = false

    private var destination: CLLocationCoordinate2D? {
        guard let lat = asset.latitude, let lon = asset.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var remainingMeters: Double? { asset.distanceMeters }
    private var arrived: Bool { (remainingMeters ?? .infinity) <= 150 }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                UserAnnotation()
                if let destination {
                    Annotation(asset.name ?? "Asset", coordinate: destination) {
                        AssetThumbnailView(asset: asset, cornerRadius: 22)
                            .frame(width: 46, height: 46)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(AppColors.purplePinkGradient, lineWidth: 3))
                            .shadow(radius: 6)
                    }
                }
                if let route {
                    MapPolyline(route.polyline)
                        .stroke(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .ignoresSafeArea()

            header
        }
        .safeAreaInset(edge: .bottom) { bottomCard }
        .task(id: mode) { await calculate() }
        .onChange(of: location.userLocation?.latitude) { _, _ in
            // Re-route if the walker drifts well off the line (cheap heuristic).
            if let route, let here = location.userLocation,
               route.polyline.distance(to: here) > 60 {
                Task { await calculate() }
            }
        }
        .fullScreenCover(isPresented: $showAR) {
            ZStack(alignment: .topLeading) {
                ARDisplayView(focusAssetId: asset.id)
                Button { showAR = false } label: {
                    Image(systemName: "xmark").font(.subheadline.bold()).foregroundStyle(.white)
                        .padding(10).background(Circle().fill(.black.opacity(0.5)))
                }
                .padding(.top, 54).padding(.leading, 20)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showSteps) {
            NavigationStack {
                List(route?.steps.filter { !$0.instructions.isEmpty } ?? [], id: \.self) { step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.instructions)
                        Text(Self.format(meters: step.distance)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Directions")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.primary)
                    .frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close directions")
            Picker("Mode", selection: $mode) {
                ForEach(TravelMode.allCases) { m in
                    Image(systemName: m.icon).tag(m).accessibilityLabel(m.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AssetThumbnailView(asset: asset, cornerRadius: 12).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.name ?? "Untitled drop").font(.headline).lineLimit(1)
                    if arrived {
                        Label("You're here — open the AR camera", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    } else if let route {
                        Text("\(Self.format(seconds: route.expectedTravelTime)) · \(Self.format(meters: remainingMeters ?? route.distance))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ARDesign.accent)
                    } else if let errorText {
                        Text(errorText).font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                Spacer()
                if route != nil {
                    Button { showSteps = true } label: {
                        Image(systemName: "list.bullet").font(.headline)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .accessibilityLabel("Step-by-step directions")
                }
            }

            HStack(spacing: 10) {
                Button(action: openInMaps) {
                    Label("Apple Maps", systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Button { showAR = true } label: {
                    Label(arrived ? "Open in AR" : "AR when closer", systemImage: "arkit")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.purplePinkGradient))
                        .opacity(arrived ? 1 : 0.45)
                }
                .disabled(!arrived)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func calculate() async {
        guard let destination else { errorText = "This asset has no location."; return }
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = mode.type
        do {
            let response = try await MKDirections(request: request).calculate()
            route = response.routes.first
            errorText = nil
            if let rect = route?.polyline.boundingMapRect {
                withAnimation { camera = .rect(rect.insetBy(dx: -rect.width * 0.25 - 400, dy: -rect.height * 0.35 - 400)) }
            }
        } catch {
            route = nil
            errorText = mode == .transit ? "No transit route here — try walking." : "Couldn't find a route. Try Apple Maps."
        }
    }

    private func openInMaps() {
        guard let destination else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        item.name = asset.name ?? "Locolo AR asset"
        let launchMode: String = {
            switch self.mode {
            case .drive: return MKLaunchOptionsDirectionsModeDriving
            case .transit: return MKLaunchOptionsDirectionsModeTransit
            case .walk: return MKLaunchOptionsDirectionsModeWalking
            }
        }()
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: launchMode])
    }

    static func format(meters: Double) -> String {
        meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)
    }

    static func format(seconds: TimeInterval) -> String {
        let mins = Int((seconds / 60).rounded(.up))
        return mins < 60 ? "\(mins) min" : "\(mins / 60) h \(mins % 60) min"
    }
}

enum TravelMode: String, CaseIterable, Identifiable {
    case walk = "Walk", drive = "Drive", transit = "Transit"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .drive: return "car.fill"
        case .transit: return "tram.fill"
        }
    }
    var type: MKDirectionsTransportType {
        switch self {
        case .walk: return .walking
        case .drive: return .automobile
        case .transit: return .transit
        }
    }
}

private extension MKPolyline {
    /// Rough distance from a coordinate to the nearest vertex of the line.
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let here = MKMapPoint(coordinate)
        var best = CLLocationDistance.greatestFiniteMagnitude
        let pts = points()
        for i in 0..<pointCount { best = min(best, here.distance(to: pts[i])) }
        return best
    }
}
