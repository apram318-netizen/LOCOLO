//
//  ARDisplayView.swift
//  Locolo
//
//  Created by Apramjot Singh on 14/11/2025.
//
//  This screen shows the AR camera feed and the digital assets
//  placed around the user. It also shows a status message overlay
//  and a small green indicator once AR geo-tracking is fully ready.

import SwiftUI
import RealityKit
import ARKit
import CoreLocation

struct ARDisplayView: View {
    @StateObject private var vm = ARDisplayViewModel()

    @State private var snapshot: SnapshotItem?
    @State private var isCapturing = false
    @State private var flash = false

    private struct SnapshotItem: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    var body: some View {
        ZStack {

            // MARK: - AR Camera View
            // Hosts the ARView from RealityKit and fills the whole screen.
            ARViewContainer(vm: vm)
                .edgesIgnoringSafeArea(.all)

            // MARK: - Hot/cold finder
            if vm.isLocalized, vm.justFound == nil, let target = vm.finderTarget {
                VStack {
                    ARFinderChip(target: target, trend: vm.finderTrend)
                        .padding(.top, vm.listeningHint == nil ? 50 : 90)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.finderTrend)
            }

            if let found = vm.justFound {
                ARFoundBanner(asset: found)
                    .transition(.scale.combined(with: .opacity))
            }

            // MARK: - Snapshot shutter
            if vm.isLocalized {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: takeSnapshot) {
                            ZStack {
                                Circle().fill(.ultraThinMaterial)
                                Circle().strokeBorder(Color.white, lineWidth: 3).padding(5)
                                if isCapturing {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(width: 64, height: 64)
                        }
                        .disabled(isCapturing)
                        .accessibilityLabel("Take AR snapshot")
                        .padding(.trailing, 20)
                        .padding(.bottom, 116)
                    }
                }
            }

            if flash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }


            // MARK: - Localization Indicator
            // Shows which placement mode is active (green = ready, orange =
            // still localizing). Where geo data exists it doubles as a manual
            // Geo ⇄ GPS switch.
            if vm.isLocalized || vm.geoAvailableHere {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            vm.toggleTrackingMode()
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(vm.isLocalized ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(vm.trackingModeLabel)
                                    .font(.caption2.weight(.semibold))
                                if vm.geoAvailableHere {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.geoAvailableHere)
                        .padding(.top, 50)
                        .padding(.trailing, 20)
                        .accessibilityLabel("\(vm.isLocalized ? "AR ready" : "Localizing"), \(vm.trackingModeLabel)")
                        .accessibilityHint(vm.geoAvailableHere
                            ? "Switches to \(vm.trackingMode == .geo ? "GPS mode" : "geo-anchoring")"
                            : "")
                    }
                    Spacer()
                }
                .transition(.scale)
            }


            // MARK: - Speech Trigger Banner
            // Tells the viewer why the mic is on and what to say.
            if let hint = vm.listeningHint {
                VStack {
                    Label("Listening for: \"\(hint)\"", systemImage: "mic.fill")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 50)
                    Spacer()
                }
            }


            // MARK: - Trigger flash caption
            if let flash = vm.triggerFlash {
                VStack {
                    Spacer()
                    Text(flash)
                        .font(.callout.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(AppColors.purplePinkGradient))
                        .shadow(color: .purple.opacity(0.5), radius: 12)
                        .padding(.bottom, 160)
                        .transition(.scale.combined(with: .opacity))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: vm.triggerFlash)
            }

            // MARK: - AR Radar
            // A compass ring showing where nearby assets are around you —
            // blips rotate as you turn, drift inward as you approach.
            if vm.isLocalized && !vm.radarBlips.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        ARRadarView(blips: vm.radarBlips, heading: vm.headingDegrees)
                            .padding(.leading, 20)
                            .padding(.bottom, 96)
                        Spacer()
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }

            // MARK: - Status Message
            // Shows helpful AR messages at the bottom (accuracy, loading, errors, etc).
            if let msg = vm.statusMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                        .padding(.bottom, vm.permissionDenied || vm.showRetry ? 108 : 40)
                }
                .animation(.easeInOut, value: msg)
            }

            // MARK: - Recovery actions (WS3)
            // Denied permission or a stuck start gets an actionable button
            // instead of a dead end.
            if vm.permissionDenied || vm.showRetry {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        if vm.permissionDenied {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Open Settings", systemImage: "gearshape.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 18).padding(.vertical, 12)
                                    .background(LinearGradient(colors: [.purple, .pink],
                                                               startPoint: .leading, endPoint: .trailing),
                                                in: Capsule())
                                    .foregroundColor(.white)
                            }
                        }
                        Button {
                            vm.retry()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }

        // MARK: - Startup
        // Resets AR state and begins location updates when the view appears.
        .onAppear {
            vm.resetARState()
            vm.startLocationUpdates()
            ProximityNotifier.shared.isViewerActive = true
        }
        // Release the mic and motion sensors when leaving the AR session
        .onDisappear {
            vm.triggerEngine.teardown()
            ProximityNotifier.shared.isViewerActive = false
        }
        .task { await vm.runFinderPulses() }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: vm.justFound?.id)
        .sheet(item: $snapshot) { item in
            ARSnapshotPreview(image: item.image)
        }
    }

    private func takeSnapshot() {
        guard !isCapturing else { return }
        isCapturing = true
        ARHaptics.tick()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        Task {
            defer { isCapturing = false }
            withAnimation(.easeIn(duration: 0.35)) { flash = false }
            guard let raw = await vm.captureSnapshot() else { return }
            snapshot = SnapshotItem(image: ARSnapshotRenderer.render(raw, caption: snapshotCaption))
        }
    }

    /// Names the nearest asset in view range, e.g. "with Neon Koi".
    private var snapshotCaption: String? {
        guard let origin = vm.userLocation else { return nil }
        let nearest = vm.nearbyAssets
            .compactMap { asset -> (String, Double)? in
                guard let name = asset.name, let lat = asset.latitude, let lon = asset.longitude else { return nil }
                return (name, origin.distance(from: CLLocation(latitude: lat, longitude: lon)))
            }
            .filter { $0.1 < 60 }
            .min { $0.1 < $1.1 }
        return nearest.map { "with \($0.0)" }
    }
}

// MARK: - Finder chip
/// "Neon Koi · 42 m · Warmer" with an arrow that points toward the asset.
struct ARFinderChip: View {
    let target: ARDisplayViewModel.FinderTarget
    let trend: FinderTrend

    private var trendLabel: (String, Color)? {
        switch trend {
        case .warmer: return ("Warmer", .orange)
        case .colder: return ("Colder", .cyan)
        case .steady: return nil
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let angle = target.relativeAngle {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .rotationEffect(.radians(angle))
                        .animation(.easeOut(duration: 0.25), value: angle)
                } else {
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(target.asset.name ?? "Hidden asset")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(ARDisplayViewModel.formatDistance(target.distance))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    if let trend = trendLabel {
                        Text(trend.0)
                            .font(.caption.weight(.bold))
                            .foregroundColor(trend.1)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nearest undiscovered asset: \(target.asset.name ?? "unnamed"), \(ARDisplayViewModel.formatDistance(target.distance)) away\(trendLabel.map { ", \($0.0.lowercased())" } ?? "")")
    }
}

// MARK: - Found banner
struct ARFoundBanner: View {
    let asset: DigitalAsset

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            Text("You found it!")
                .font(.title3.bold())
            Text(asset.name ?? "A hidden asset")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("+1 discovery in your Passport")
                .font(.caption.weight(.semibold))
                .foregroundColor(.purple)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Snapshot preview
struct ARSnapshotPreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                    .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        ARHaptics.success()
                        saved = true
                    } label: {
                        Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .disabled(saved)

                    Button {
                        showShare = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing),
                                        in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: .infinity)
            .background(ARDesign.screenBackground.ignoresSafeArea())
            .navigationTitle("AR Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [image])
                    .presentationDetents([.medium, .large])
            }
        }
    }
}


// MARK: - ARView Container
// Wraps the shared ARView so SwiftUI can display RealityKit content.

struct ARViewContainer: UIViewRepresentable {
    let vm: ARDisplayViewModel

    func makeUIView(context: Context) -> ARView {
        let view = SharedARViewHolder.shared
        vm.arView = view

        // The ARView is a shared singleton, so remove the recognizer from any
        // previous visit before installing a fresh one.
        if let old = SharedARViewHolder.triggerTapRecognizer {
            view.removeGestureRecognizer(old)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        SharedARViewHolder.triggerTapRecognizer = tap

        // Coaching overlay guides world-tracking initialization and auto-hides
        // once tracking is normal. Reuse one instance across visits. (WS3)
        let coaching = SharedARViewHolder.coachingOverlay ?? {
            let c = ARCoachingOverlayView()
            c.goal = .tracking
            c.activatesAutomatically = true
            c.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            SharedARViewHolder.coachingOverlay = c
            return c
        }()
        coaching.session = view.session
        coaching.frame = view.bounds
        if coaching.superview !== view {
            coaching.removeFromSuperview()
            view.addSubview(coaching)
        }

        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(vm: vm)
    }

    // MARK: Tap → trigger
    // Hit-tests the tapped point and forwards the entity to the trigger engine.
    // Gesture callbacks always arrive on the main thread, so MainActor is safe.
    @MainActor
    final class Coordinator {
        let vm: ARDisplayViewModel

        init(vm: ARDisplayViewModel) {
            self.vm = vm
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = vm.arView else { return }
            let point = gesture.location(in: arView)
            if let entity = arView.entity(at: point) {
                vm.triggerEngine.handleTap(on: entity)
            }
        }
    }
}


// MARK: - AR Radar
// Glass compass ring: N marker tracks true north, purple blips are nearby
// assets (angle = bearing relative to facing, radius = distance).
struct ARRadarView: View {
    let blips: [ARDisplayViewModel.RadarBlip]
    let heading: Double?

    private let size: CGFloat = 108

    var body: some View {
        ZStack {
            // Ring + sweep background
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            Circle()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: size * 0.55, height: size * 0.55)

            // Facing wedge (what's roughly in front of the camera)
            RadarWedge()
                .fill(LinearGradient(colors: [Color.purple.opacity(0.35), .clear],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: size, height: size)

            // North marker, rotating opposite the device heading
            if let heading {
                Text("N")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .offset(y: -size / 2 + 9)
                    .rotationEffect(.degrees(-heading))
            }

            // Asset blips
            ForEach(blips) { blip in
                Circle()
                    .fill(LinearGradient(colors: [.purple, .pink],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 7, height: 7)
                    .shadow(color: .purple.opacity(0.8), radius: 3)
                    .offset(blipOffset(blip))
            }

            // You
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .shadow(color: .white.opacity(0.9), radius: 2)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(blips.count) AR asset\(blips.count == 1 ? "" : "s") nearby")
    }

    private func blipOffset(_ blip: ARDisplayViewModel.RadarBlip) -> CGSize {
        // Up = the direction the device is facing. Keep a small inner margin.
        let r = (size / 2 - 10) * CGFloat(max(blip.normalizedDistance, 0.12))
        return CGSize(width: r * CGFloat(sin(blip.relativeAngle)),
                      height: -r * CGFloat(cos(blip.relativeAngle)))
    }
}

/// Narrow triangle from the center to the top edge — the facing indicator.
private struct RadarWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addLine(to: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Shared ARView
// Keeps one shared ARView instance so the AR session does not reset unnecessarily.
final class SharedARViewHolder {
    /// Sessions are always run explicitly (geo or gravity+heading world);
    /// automatic configuration would race them with a plain world config.
    static let shared: ARView = {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        return view
    }()
    static var triggerTapRecognizer: UITapGestureRecognizer?
    static var coachingOverlay: ARCoachingOverlayView?
}
