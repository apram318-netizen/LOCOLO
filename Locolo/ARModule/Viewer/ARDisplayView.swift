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
    /// The asset the user came to see (detail sheet "View in AR"). Memories
    /// captured in this session attach to it by default.
    var focusAssetId: UUID? = nil

    @StateObject private var vm = ARDisplayViewModel()
    @ObservedObject private var backgroundMode = BackgroundExploreService.shared
    @State private var hypeBurst: UUID?

    @State private var snapshot: SnapshotItem?
    @State private var isCapturing = false
    @State private var isRecordingClip = false
    @State private var clipToast: String?
    @State private var flash = false

    private struct SnapshotItem: Identifiable {
        let id = UUID()
        let media: MemoryCaptureMedia
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

            // MARK: - Snapshot shutter (+ long-press AR clip → Story)
            if vm.isLocalized {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: takeSnapshot) {
                            ZStack {
                                Circle().fill(.ultraThinMaterial)
                                Circle().strokeBorder(
                                    isRecordingClip ? Color.red : Color.white, lineWidth: 3
                                ).padding(5)
                                if isCapturing || isRecordingClip {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(width: 64, height: 64)
                        }
                        .disabled(isCapturing || isRecordingClip)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                                Task { await recordClipToStory() }
                            }
                        )
                        .accessibilityLabel("Capture a memory. Long-press to record a clip.")
                        .padding(.trailing, 20)
                        .padding(.bottom, 116)
                    }
                }
            }

            if let clipToast {
                VStack {
                    Spacer()
                    Text(clipToast)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.75)))
                        .padding(.bottom, 200)
                }
                .transition(.opacity)
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


            // MARK: - Background AR toggle
            // Keeps location + audio alive after you lock the phone, so asset
            // sounds still play as you walk past (ARKit itself can't run in
            // the background).
            VStack {
                HStack {
                    Spacer()
                    Button {
                        ARHaptics.tick()
                        backgroundMode.toggle()
                        clipToast = backgroundMode.isOn
                            ? "Background AR on — sounds play as you pass assets, even locked"
                            : "Background AR off"
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            clipToast = nil
                        }
                    } label: {
                        Label(backgroundMode.isOn ? "BG on" : "BG", systemImage: backgroundMode.isOn ? "speaker.wave.2.fill" : "speaker.slash")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(backgroundMode.isOn ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(backgroundMode.isOn ? AnyShapeStyle(Color.purple) : AnyShapeStyle(.ultraThinMaterial),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 88)
                    .padding(.trailing, 20)
                    .accessibilityLabel(backgroundMode.isOn ? "Background AR on" : "Background AR off")
                    .accessibilityHint("Keeps playing asset sounds as you walk with the phone locked")
                }
                Spacer()
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


            // MARK: - In-AR hype button (react to the asset you're at)
            if vm.isLocalized && vm.nearestReactableAsset != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            Task {
                                if let hyped = await vm.hypeNearest() {
                                    _ = hyped
                                    withAnimation { hypeBurst = UUID() }
                                }
                            }
                        } label: {
                            Image(systemName: vm.nearestIsHyped ? "bolt.fill" : "bolt")
                                .font(.title3.weight(.bold))
                                .foregroundColor(vm.nearestIsHyped ? .yellow : .white)
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(.ultraThinMaterial))
                                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                                .overlay(alignment: .center) {
                                    if let burst = hypeBurst {
                                        HypeBurst().id(burst)
                                    }
                                }
                        }
                        .accessibilityLabel("Hype the nearest asset")
                        .padding(.trailing, 26)
                        .padding(.bottom, 196)   // sits above the snapshot button
                    }
                }
            }

            // MARK: - Trigger flash caption + particle burst
            if let flash = vm.triggerFlash {
                VStack {
                    Spacer()
                    ZStack {
                        CelebrationBurst(symbol: "sparkles",
                                         colors: [.yellow, .orange, .pink, .cyan])
                            .frame(height: 90)
                        Text(flash)
                            .font(.callout.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(AppColors.purplePinkGradient))
                            .shadow(color: .purple.opacity(0.5), radius: 12)
                    }
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
        .onAppear {
            refreshLiveActivity()
        }
        // Release the mic and motion sensors when leaving the AR session
        .onDisappear {
            vm.triggerEngine.teardown()
            ProximityNotifier.shared.isViewerActive = false
            ExploringLiveActivity.end()
        }
        .onChange(of: vm.nearbyAssets.count) { _, _ in refreshLiveActivity() }
        .onChange(of: vm.finderTarget?.asset.id) { _, _ in refreshLiveActivity() }
        .task { await vm.runFinderPulses() }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: vm.justFound?.id)
        // Every capture becomes a "memo": attach it to the asset you're
        // with, share it to Reels, send it to friends, or just save it.
        .sheet(item: $snapshot) { item in
            MemoryComposerView(media: item.media,
                               candidates: memoryCandidates,
                               preselected: focusAssetId ?? memoryCandidates.first?.id)
        }
    }

    private func takeSnapshot() {
        guard !isCapturing, !isRecordingClip else { return }
        isCapturing = true
        ARHaptics.tick()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        Task {
            defer { isCapturing = false }
            withAnimation(.easeIn(duration: 0.35)) { flash = false }
            guard let raw = await vm.captureSnapshot() else { return }
            snapshot = SnapshotItem(media: .photo(ARSnapshotRenderer.render(raw, caption: snapshotCaption)))
        }
    }

    private func recordClipToStory() async {
        guard !isRecordingClip, ARClipRecorder.shared.isAvailable else {
            clipToast = "Clip recording needs a real device"
            return
        }
        isRecordingClip = true
        clipToast = "Recording…"
        ARHaptics.tick()
        defer { isRecordingClip = false }
        guard let data = await ARClipRecorder.shared.recordClip(seconds: 5) else {
            clipToast = "Couldn't record clip"
            return
        }
        clipToast = nil
        ARHaptics.success()
        // Same composer as photos: memory / Reels / Story / friends.
        snapshot = SnapshotItem(media: .video(data))
    }

    /// Assets close enough to plausibly be "in" the shot, nearest first; the
    /// focused asset always qualifies.
    private var memoryCandidates: [DigitalAsset] {
        let origin = vm.userLocation
        let ranked = vm.nearbyAssets
            .map { asset -> (DigitalAsset, Double) in
                guard let origin, let lat = asset.latitude, let lon = asset.longitude else { return (asset, .infinity) }
                return (asset, origin.distance(from: CLLocation(latitude: lat, longitude: lon)))
            }
            .filter { $0.1 < 200 || $0.0.id == focusAssetId }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        if let focusAssetId, let i = ranked.firstIndex(where: { $0.id == focusAssetId }), i > 0 {
            var copy = ranked
            copy.insert(copy.remove(at: i), at: 0)
            return copy
        }
        return ranked
    }

    private func refreshLiveActivity() {
        guard vm.isLocalized else { return }
        let nearest = vm.finderTarget
        ExploringLiveActivity.start(
            nearbyCount: vm.nearbyAssets.count,
            nearestName: nearest?.asset.name,
            nearestMeters: nearest?.distance
        )
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

    @State private var celebrate = true
    @State private var sharingToStory = false
    @State private var storyToast: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            Text(asset.isRareFind ? "Rare find!" : "You found it!")
                .font(.title3.bold())
            Text(asset.name ?? "A hidden asset")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(asset.isRareFind
                 ? "Listed drop · bigger passport flex"
                 : "+1 discovery in your Passport")
                .font(.caption.weight(.semibold))
                .foregroundColor(.purple)

            if StoryStore.shared.available {
                Button {
                    Task { await shareToStory() }
                } label: {
                    Group {
                        if sharingToStory {
                            ProgressView().tint(.white)
                        } else {
                            Label("Share to Story", systemImage: "circle.dashed")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(AppColors.purplePinkGradient))
                }
                .disabled(sharingToStory)
            }

            if let storyToast {
                Text(storyToast)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .celebration(trigger: $celebrate, symbol: "sparkles")
        .accessibilityElement(children: .combine)
    }

    private func shareToStory() async {
        sharingToStory = true
        defer { sharingToStory = false }
        guard let url = asset.thumbUrl.flatMap(URL.init(string:)),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            storyToast = "Couldn't load a snapshot for your story."
            return
        }
        do {
            _ = try await StoryStore.shared.post(
                imageData: data,
                caption: "Found \(asset.name ?? "this") in AR ✨",
                assetId: asset.id)
            ARHaptics.success()
            storyToast = "Posted to your story"
        } catch {
            storyToast = "Story unavailable right now"
        }
    }
}

// MARK: - Snapshot preview
struct ARSnapshotPreview: View {
    let image: UIImage
    var linkedAssetId: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var saved = false
    @State private var storyPosted = false
    @State private var postingStory = false

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

                if StoryStore.shared.available {
                    Button {
                        Task { await addToStory() }
                    } label: {
                        Group {
                            if postingStory {
                                ProgressView()
                            } else {
                                Label(storyPosted ? "On your story" : "Add to Story",
                                      systemImage: storyPosted ? "checkmark" : "circle.dashed")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .disabled(postingStory || storyPosted)
                    .padding(.horizontal, 20)
                }
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

    private func addToStory() async {
        postingStory = true
        defer { postingStory = false }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            _ = try await StoryStore.shared.post(
                imageData: data, caption: nil, assetId: linkedAssetId)
            storyPosted = true
            ARHaptics.success()
        } catch {
            ARHaptics.warning()
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
        if let old = SharedARViewHolder.triggerLongPressRecognizer {
            view.removeGestureRecognizer(old)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        SharedARViewHolder.triggerTapRecognizer = tap

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.55
        view.addGestureRecognizer(longPress)
        SharedARViewHolder.triggerLongPressRecognizer = longPress

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

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let arView = vm.arView else { return }
            let point = gesture.location(in: arView)
            if let entity = arView.entity(at: point) {
                vm.triggerEngine.handleLongPress(on: entity)
            }
        }
    }
}


// MARK: - Hype burst
// A quick shower of bolts flying up from the hype button when you react.
struct HypeBurst: View {
    @State private var go = false
    private let bolts = Array(0..<6)

    var body: some View {
        ZStack {
            ForEach(bolts, id: \.self) { i in
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.purplePinkGradient)
                    .offset(x: go ? CGFloat((i - 3) * 14) : 0,
                            y: go ? -70 - CGFloat(i * 6) : 0)
                    .opacity(go ? 0 : 1)
                    .scaleEffect(go ? 1.4 : 0.4)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { go = true }
        }
        .allowsHitTesting(false)
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
    static var triggerLongPressRecognizer: UILongPressGestureRecognizer?
    static var coachingOverlay: ARCoachingOverlayView?
}
