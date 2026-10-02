//
//  MemoryViews.swift
//  Locolo
//
//  Everything you see of a "memo" — a photo or clip captured live in an AR
//  session with an asset:
//    * MemoryComposerView — snap-style post-capture screen (caption, which
//      asset, Reels toggle, Save / Send / Story).
//    * MemoryBubble       — story-style thumbnail with an unseen ring.
//    * MemoryViewer       — full-screen snap viewer: progress bars, tap
//      left/right, hold to pause, swipe down to close, double-tap to like.
//    * MemoryReelsView    — Instagram-Reels vertical pager over the shared
//      memories feed, with a small "Inspect asset" button on every reel.
//

import SwiftUI
import AVKit
import Photos

// MARK: - Capture media

enum MemoryCaptureMedia {
    case photo(UIImage)
    case video(Data)

    var isVideo: Bool { if case .video = self { return true } else { return false } }
}

// MARK: - Composer

struct MemoryComposerView: View {
    let media: MemoryCaptureMedia
    let candidates: [DigitalAsset]
    var preselected: UUID?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MemoryStore.shared

    @State private var caption = ""
    @State private var selectedAsset: UUID?
    @State private var shareToReels = true
    @State private var visibility = "public"
    @State private var isSaving = false
    @State private var saved: AssetMemory?
    @State private var errorText: String?
    @State private var sharePayload: ARSharePayload?
    @State private var storyState: String?
    @State private var savedToPhotos = false
    @State private var videoPlayer: AVPlayer?
    @State private var suggestions: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview
                        .frame(maxWidth: .infinity)
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            if let saved {
                                Label("Saved to \(saved.assetName ?? "asset")", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(12)
                            }
                        }

                    if saved == nil {
                        editor
                    } else {
                        afterSave
                    }

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(ARDesign.screenBackground.ignoresSafeArea())
            .navigationTitle(saved == nil ? "New memory" : "Memory saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved == nil ? "Discard" : "Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if saved == nil { saveBar }
            }
            .sheet(item: $sharePayload) { payload in
                ARShareSheet(payload: payload)
            }
            .onAppear {
                selectedAsset = preselected ?? candidates.first?.id
                if case .video(let data) = media {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("memory-preview.mp4")
                    try? data.write(to: url)
                    let player = AVPlayer(url: url)
                    player.isMuted = true
                    player.play()
                    videoPlayer = player
                }
            }
            .task {
                // On-device suggestions (Vision + NaturalLanguage, no network).
                if case .photo(let image) = media {
                    suggestions = await SmartSuggestions.captionIdeas(for: image,
                                                                      assetName: candidates.first { $0.id == selectedAsset }?.name)
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch media {
        case .photo(let image):
            Image(uiImage: image).resizable().scaledToFill()
        case .video:
            if let videoPlayer {
                VideoPlayer(player: videoPlayer)
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                        videoPlayer.seek(to: .zero)
                        videoPlayer.play()
                    }
            } else {
                Color.black
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Say something about this moment…", text: $caption, axis: .vertical)
                .lineLimit(1...4)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
                .onChange(of: caption) { _, new in
                    if new.count > 300 { caption = String(new.prefix(300)) }
                }

            if !suggestions.isEmpty && caption.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(ARDesign.accent)
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { caption = s }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(ARDesign.accent.opacity(0.14)))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Memory of")
                    .font(.subheadline.weight(.semibold))
                if candidates.isEmpty {
                    Text("No AR asset nearby — memories are pinned to an asset. You can still save this to Photos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(candidates.prefix(12)) { asset in
                                assetChip(asset)
                            }
                        }
                    }
                }
            }

            Toggle(isOn: $shareToReels) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share to Reels").font(.subheadline.weight(.semibold))
                    Text("Shows in the Swipe feed and on the asset").font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(ARDesign.accent)

            Picker("Who can see it", selection: $visibility) {
                Text("Everyone").tag("public")
                Text("Followers").tag("friends")
                Text("Only me").tag("private")
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                secondaryButton(savedToPhotos ? "Saved" : "Save to Photos",
                                icon: savedToPhotos ? "checkmark" : "square.and.arrow.down") { saveToPhotos() }
                if StoryStore.shared.available {
                    secondaryButton(storyState ?? "Add to Story", icon: "circle.dashed") { Task { await addToStory() } }
                }
            }
        }
    }

    private func assetChip(_ asset: DigitalAsset) -> some View {
        let on = selectedAsset == asset.id
        return Button {
            ARHaptics.tick()
            selectedAsset = asset.id
        } label: {
            HStack(spacing: 8) {
                AssetThumbnailView(asset: asset, cornerRadius: 8)
                    .frame(width: 32, height: 32)
                Text(asset.name ?? "Untitled")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(ARDesign.accent) }
            }
            .padding(6)
            .padding(.trailing, 6)
            .background(Capsule().fill(on ? ARDesign.accent.opacity(0.16) : Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(on ? ARDesign.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var saveBar: some View {
        Button(action: save) {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Text(selectedAsset == nil ? "Pick an asset to save" : "Save memory")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColors.purplePinkGradient))
        }
        .disabled(isSaving || selectedAsset == nil || !store.available)
        .opacity(selectedAsset == nil || !store.available ? 0.5 : 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var afterSave: some View {
        VStack(spacing: 12) {
            if let saved {
                primaryButton("Send to friends", icon: "paperplane.fill") { sharePayload = .memory(saved) }
                HStack(spacing: 10) {
                    secondaryButton("Post about it", icon: "square.and.pencil") { sharePayload = .memory(saved) }
                    secondaryButton(savedToPhotos ? "Saved" : "Save to Photos",
                                    icon: savedToPhotos ? "checkmark" : "square.and.arrow.down") { saveToPhotos() }
                }
            }
        }
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColors.purplePinkGradient))
        }
    }

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func save() {
        guard let assetId = selectedAsset else { return }
        isSaving = true
        errorText = nil
        Task {
            do {
                let created: AssetMemory
                switch media {
                case .photo(let image):
                    guard let jpeg = image.locoloDownscaled(maxSide: 1920).jpegData(compressionQuality: 0.85) else { return }
                    created = try await store.create(assetId: assetId, media: jpeg, isVideo: false,
                                                     caption: caption, visibility: visibility,
                                                     shareToFeed: shareToReels)
                case .video(let data):
                    created = try await store.create(assetId: assetId, media: data, isVideo: true,
                                                     caption: caption, visibility: visibility,
                                                     shareToFeed: shareToReels, duration: 5)
                }
                ARHaptics.success()
                withAnimation { saved = created }
            } catch {
                ARHaptics.warning()
                errorText = store.available ? "Couldn't save the memory. Check your connection and try again."
                                            : "Memories aren't switched on yet — try again after the next update."
            }
            isSaving = false
        }
    }

    private func saveToPhotos() {
        switch media {
        case .photo(let image):
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            savedToPhotos = true
            ARHaptics.success()
        case .video(let data):
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            guard (try? data.write(to: url)) != nil else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { ok, _ in
                Task { @MainActor in
                    savedToPhotos = ok
                    ok ? ARHaptics.success() : ARHaptics.warning()
                }
            }
        }
    }

    private func addToStory() async {
        storyState = "Posting…"
        do {
            switch media {
            case .photo(let image):
                guard let data = image.jpegData(compressionQuality: 0.85) else { return }
                _ = try await StoryStore.shared.post(imageData: data, caption: caption.isEmpty ? nil : caption,
                                                     assetId: selectedAsset)
            case .video(let data):
                _ = try await StoryStore.shared.postVideo(mp4Data: data, caption: caption.isEmpty ? nil : caption,
                                                          assetId: selectedAsset)
            }
            storyState = "On your story"
            ARHaptics.success()
        } catch {
            storyState = "Story unavailable"
            ARHaptics.warning()
        }
    }
}

// MARK: - Bubble

struct MemoryViewerItem: Identifiable {
    let id = UUID()
    let memories: [AssetMemory]
    let start: Int
}

/// Story-style tile: gradient ring while unseen, thumbnail, author avatar.
struct MemoryBubble: View {
    let memory: AssetMemory
    var width: CGFloat = 76
    @ObservedObject private var creators = CreatorCache.shared

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: memory.previewURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(colors: [.purple.opacity(0.5), .pink.opacity(0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .frame(width: width, height: width * 1.37)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if memory.isVideo {
                    Image(systemName: "play.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(.black.opacity(0.4)))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                ARAvatarView(url: creators.creator(memory.userId)?.avatarUrl,
                             name: creators.creator(memory.userId)?.displayName ?? "?", size: 22)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .padding(6)
            }
            .padding(3)
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(memory.seenByMe ? AnyShapeStyle(Color.white.opacity(0.2))
                                                  : AnyShapeStyle(AppColors.purplePinkGradient),
                                  lineWidth: 2.5)
            )
            Text(creators.creator(memory.userId)?.username ?? memory.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: width)
        }
    }
}

// MARK: - Snap-style viewer

struct MemoryViewer: View {
    let memories: [AssetMemory]
    var startIndex: Int = 0
    /// Presenter-supplied "open the asset" (dismiss + present detail sheet).
    var onOpenAsset: ((UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userVM: UserViewModel
    @ObservedObject private var store = MemoryStore.shared
    @ObservedObject private var creators = CreatorCache.shared

    @State private var index = 0
    @State private var progress: Double = 0
    @State private var paused = false
    @State private var dragY: CGFloat = 0
    @State private var heartBurst = false
    @State private var sharePayload: ARSharePayload?
    @State private var detailAsset: DigitalAsset?
    @State private var confirmDelete = false

    private let imageDuration: Double = 5
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var current: AssetMemory? {
        memories.indices.contains(index) ? (store.memory(memories[index].id) ?? memories[index]) : nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let memory = current {
                    MemoryMediaView(memory: memory, paused: paused) { duration in
                        // Videos drive their own progress length.
                        if duration > 0 { videoDuration = duration }
                    }
                    .id(memory.id)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()

                    // Readability scrims
                    VStack {
                        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 160)
                        Spacer()
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 220)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    tapZones(width: geo.size.width)

                    VStack(spacing: 10) {
                        progressBars
                        header(memory)
                        Spacer()
                        footer(memory)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    if heartBurst {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 110))
                            .foregroundStyle(.white)
                            .shadow(radius: 10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .offset(y: max(0, dragY))
            .scaleEffect(1 - min(0.12, max(0, dragY) / 2000))
            .gesture(
                DragGesture()
                    .onChanged { v in dragY = v.translation.height; paused = true }
                    .onEnded { v in
                        if v.translation.height > 140 { dismiss() } else {
                            withAnimation(.spring()) { dragY = 0 }
                            paused = false
                        }
                    }
            )
        }
        .statusBarHidden()
        .onAppear { index = min(max(0, startIndex), max(0, memories.count - 1)) }
        .onReceive(tick) { _ in advanceClock() }
        .onChange(of: index) { progress = 0; videoDuration = 0; markSeen() }
        .task { markSeen() }
        .sheet(item: $sharePayload, onDismiss: { paused = false }) { payload in
            ARShareSheet(payload: payload)
        }
        .sheet(item: $detailAsset, onDismiss: { paused = false }) { asset in
            AssetDetailSheet(asset: asset)
        }
        .confirmationDialog("Delete this memory?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let m = current else { return }
                Task {
                    if await store.delete(m) {
                        if memories.count <= 1 { dismiss() } else { next() }
                    }
                }
            }
        }
    }

    @State private var videoDuration: Double = 0

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(memories.indices, id: \.self) { i in
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.3))
                    Capsule().fill(.white)
                        .frame(width: g.size.width * (i < index ? 1 : (i == index ? progress : 0)))
                }
                .frame(height: 2.5)
            }
        }
    }

    private func header(_ memory: AssetMemory) -> some View {
        let author = creators.creator(memory.userId)
        return HStack(spacing: 10) {
            ARAvatarView(url: author?.avatarUrl, name: author?.displayName ?? "?", size: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(author?.displayName ?? "Explorer").font(.subheadline.weight(.bold))
                    if author?.isVerified == true { ARVerifiedBadge(size: 11) }
                    Text(memory.createdAt.formatted(.relative(presentation: .numeric)))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Label(memory.assetName ?? "AR asset", systemImage: "arkit")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer()
            if memory.userId == userVM.currentUser?.id || memory.assetOwnerId == userVM.currentUser?.id {
                Menu {
                    Button(role: .destructive) { paused = true; confirmDelete = true } label: {
                        Label("Delete memory", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.headline).padding(8)
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).padding(8)
            }
            .accessibilityLabel("Close")
        }
        .foregroundStyle(.white)
    }

    private func footer(_ memory: AssetMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let caption = memory.caption, !caption.isEmpty {
                Text(caption)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            HStack(spacing: 10) {
                Button { openAsset(memory) } label: {
                    HStack(spacing: 8) {
                        AsyncImage(url: URL(string: memory.assetThumbUrl ?? "")) { $0.resizable().scaledToFill() }
                            placeholder: { Color.white.opacity(0.2) }
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("Inspect asset").font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                    .padding(6).padding(.trailing, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Button {
                    Task { await store.toggleLike(memory) }
                    ARHaptics.tick()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: memory.likedByMe ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(memory.likedByMe ? .pink : .white)
                            .symbolEffect(.bounce, value: memory.likedByMe)
                        Text(memory.likeCount.compactFormatted).font(.caption2.bold())
                    }
                }
                Button { paused = true; sharePayload = .memory(memory) } label: {
                    Image(systemName: "paperplane").font(.title2)
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.bottom, 20)
    }

    private func tapZones(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle())
                .frame(width: width * 0.33)
                .onTapGesture { previous() }
            Color.clear.contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTapLike() }
                .onTapGesture { next() }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.2)
                .onChanged { _ in paused = true }
                .onEnded { _ in paused = false }
        )
    }

    // MARK: Clock

    private func advanceClock() {
        guard !paused, current != nil, sharePayload == nil, detailAsset == nil else { return }
        let length = (current?.isVideo == true && videoDuration > 0) ? videoDuration : imageDuration
        progress += 0.05 / length
        if progress >= 1 { next() }
    }

    private func next() {
        if index < memories.count - 1 { index += 1 } else { dismiss() }
    }

    private func previous() {
        if index > 0 { index -= 1 } else { progress = 0 }
    }

    private func markSeen() {
        guard let m = current else { return }
        Task { await store.markSeen(m) }
    }

    private func doubleTapLike() {
        guard let m = current else { return }
        if !m.likedByMe { Task { await store.toggleLike(m) } }
        ARHaptics.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heartBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { withAnimation { heartBurst = false } }
    }

    private func openAsset(_ memory: AssetMemory) {
        if let onOpenAsset { dismiss(); onOpenAsset(memory.assetId); return }
        paused = true
        Task { detailAsset = await DigitalAssetRepository().fetchAsset(id: memory.assetId) }
    }
}

/// Photo or looping video for one memory.
struct MemoryMediaView: View {
    let memory: AssetMemory
    var paused: Bool = false
    var onDuration: ((Double) -> Void)? = nil

    @State private var player: AVPlayer?
    @State private var looper: NSObjectProtocol?

    var body: some View {
        Group {
            if memory.isVideo {
                ZStack {
                    AsyncImage(url: memory.previewURL) { $0.resizable().scaledToFill() } placeholder: { Color.black }
                    if let player {
                        FillVideoLayer(player: player)
                    }
                }
            } else {
                AsyncImage(url: URL(string: memory.mediaUrl)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.5))
                    default: ProgressView().tint(.white)
                    }
                }
            }
        }
        .onAppear { if memory.isVideo { start() } }
        .onDisappear {
            player?.pause()
            if let looper { NotificationCenter.default.removeObserver(looper) }
        }
        .onChange(of: paused) { _, p in p ? player?.pause() : player?.play() }
    }

    private func start() {
        guard let url = URL(string: memory.mediaUrl) else { return }
        let p = AVPlayer(url: url)
        p.isMuted = false
        player = p
        looper = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                        object: p.currentItem, queue: .main) { _ in
            p.seek(to: .zero)
            p.play()
        }
        p.play()
        Task {
            if let d = try? await p.currentItem?.asset.load(.duration) {
                onDuration?(d.seconds)
            }
        }
    }
}

/// AVPlayerLayer with aspect-fill (VideoPlayer letterboxes and shows controls).
struct FillVideoLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// `locolo://memory/<id>` and chat cards land here.
struct MemoryRouteView: View {
    let memoryId: UUID
    @State private var memory: AssetMemory?
    @State private var failed = false

    var body: some View {
        Group {
            if let memory {
                MemoryViewer(memories: [memory])
            } else if failed {
                ARInlineEmptyState(icon: "photo.on.rectangle.angled", title: "Memory unavailable",
                                   subtitle: "It may have been deleted or made private.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ARDesign.screenBackground.ignoresSafeArea())
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            memory = await MemoryStore.shared.fetchOne(memoryId)
            failed = memory == nil
        }
    }
}

// MARK: - Reels

/// Instagram-Reels-style vertical pager over memories shared to the feed.
/// (Feedback: the swipe mode should show photos/videos captured WITH assets,
/// not the assets themselves, plus a small button to inspect the asset.)
struct MemoryReelsView: View {
    var startAt: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MemoryStore.shared
    @State private var current: UUID?
    @State private var detailAsset: DigitalAsset?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if store.feed.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.feed) { memory in
                            ReelPage(memory: memory, isActive: current == memory.id) { assetId in
                                Task { detailAsset = await DigitalAssetRepository().fetchAsset(id: assetId) }
                            }
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(memory.id)
                            .onAppear {
                                if memory.id == store.feed.last?.id { Task { await store.loadMoreFeed() } }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $current)
                .ignoresSafeArea()
            }

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Back")
                Text("Reels")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .task {
            if store.feed.isEmpty { await store.refreshFeed() }
            current = startAt ?? store.feed.first?.id
        }
        .sheet(item: $detailAsset) { asset in
            AssetDetailSheet(asset: asset)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if store.isLoadingFeed {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(.white.opacity(0.7))
                Text(store.available ? "No memories yet" : "Reels are coming soon")
                    .font(.title3.bold()).foregroundStyle(.white)
                Text("Find an AR asset, open it in AR and tap the shutter. Your memory shows up here.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReelPage: View {
    let memory: AssetMemory
    let isActive: Bool
    let onInspect: (UUID) -> Void

    @ObservedObject private var store = MemoryStore.shared
    @ObservedObject private var creators = CreatorCache.shared
    @State private var heart = false
    @State private var sharePayload: ARSharePayload?

    private var live: AssetMemory { store.memory(memory.id) ?? memory }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isActive {
                MemoryMediaView(memory: live)
            } else {
                AsyncImage(url: live.previewURL) { $0.resizable().scaledToFill() } placeholder: { Color.black }
            }

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { like(fromDoubleTap: true) }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    let author = creators.creator(live.userId)
                    HStack(spacing: 8) {
                        ARAvatarView(url: author?.avatarUrl, name: author?.displayName ?? "?", size: 32)
                        Text(author?.username ?? "explorer").font(.subheadline.weight(.bold))
                        if author?.isVerified == true { ARVerifiedBadge(size: 11) }
                        if live.userId != SupabaseManager.shared.currentUserId.flatMap(UUID.init(uuidString:)) {
                            ARFollowButton(userId: live.userId, style: .compact)
                        }
                    }
                    if let caption = live.caption, !caption.isEmpty {
                        Text(caption).font(.subheadline).lineLimit(3)
                    }
                    Button { onInspect(live.assetId) } label: {
                        HStack(spacing: 8) {
                            AsyncImage(url: URL(string: live.assetThumbUrl ?? "")) { $0.resizable().scaledToFill() }
                                placeholder: { Color.white.opacity(0.2) }
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text(live.assetName ?? "AR asset").font(.caption.weight(.semibold)).lineLimit(1)
                            Text("Inspect").font(.caption.weight(.bold)).foregroundStyle(.black)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(.white))
                        }
                        .padding(5).padding(.trailing, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .accessibilityLabel("Inspect asset \(live.assetName ?? "")")
                }
                Spacer()
                VStack(spacing: 22) {
                    railButton(live.likedByMe ? "heart.fill" : "heart", live.likeCount.compactFormatted,
                               tint: live.likedByMe ? .pink : .white) { like(fromDoubleTap: false) }
                    railButton("paperplane", "Share") { sharePayload = .memory(live) }
                    railButton("cube.transparent", "Asset") { onInspect(live.assetId) }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 110)

            if heart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .frame(maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onChange(of: isActive) { _, active in if active { Task { await store.markSeen(live) } } }
        .sheet(item: $sharePayload) { ARShareSheet(payload: $0) }
    }

    private func railButton(_ icon: String, _ label: String, tint: Color = .white,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 28)).foregroundStyle(tint)
                Text(label).font(.caption2.weight(.semibold))
            }
            .shadow(radius: 4)
        }
    }

    private func like(fromDoubleTap: Bool) {
        if fromDoubleTap {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heart = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { withAnimation { heart = false } }
            if live.likedByMe { return }
        }
        ARHaptics.tick()
        Task { await store.toggleLike(live) }
    }
}
