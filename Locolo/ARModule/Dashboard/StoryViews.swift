//
//  StoryViews.swift
//  Locolo
//
//  Phase D stories: avatar rings on Explore + a full-screen viewer with an
//  auto-advancing progress bar. Add-your-own ring opens the photo picker.
//

import SwiftUI
import PhotosUI

// MARK: - Rail

struct StoryRailView: View {
    @ObservedObject private var store = StoryStore.shared
    @ObservedObject private var creators = CreatorCache.shared
    @EnvironmentObject private var userVM: UserViewModel

    @State private var viewerGroup: StoryAuthorGroup?
    @State private var showComposer = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var draftImage: UIImage?
    @State private var draftCaption = ""
    @State private var isPosting = false
    @State private var postError: String?

    var body: some View {
        Group {
            if store.available && (store.hasLoaded || store.isLoading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        addRing
                        ForEach(store.groups) { group in
                            authorRing(group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .fullScreenCover(item: $viewerGroup) { group in
            StoryViewer(group: group, allGroups: store.groups) {
                viewerGroup = nil
            }
        }
        .sheet(isPresented: $showComposer) {
            composer
                .presentationDetents([.medium])
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    draftImage = image
                    draftCaption = ""
                    showComposer = true
                }
                pickerItem = nil
            }
        }
    }

    private var addRing: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            AngularGradient(colors: [.purple, .pink, .blue, .purple],
                                            center: .center),
                            lineWidth: 2.5)
                        .frame(width: 68, height: 68)
                    ARAvatarView(url: userVM.currentUser?.avatarUrl,
                                 name: userVM.currentUser?.name ?? "You", size: 58)
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.purple)
                        .font(.system(size: 20))
                        .offset(x: 22, y: 22)
                }
                Text("Your story")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .accessibilityLabel("Add to your story")
    }

    private func authorRing(_ group: StoryAuthorGroup) -> some View {
        let creator = creators.creator(group.userId)
        let name = group.userId == userVM.currentUser?.id
            ? "You" : (creator?.displayName ?? "Creator")
        return Button {
            ARHaptics.tick()
            viewerGroup = group
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            group.hasUnviewed
                                ? AnyShapeStyle(AngularGradient(colors: [.purple, .pink, .orange, .purple],
                                                                center: .center))
                                : AnyShapeStyle(Color.secondary.opacity(0.35)),
                            lineWidth: group.hasUnviewed ? 2.5 : 1.5)
                        .frame(width: 68, height: 68)
                    ARAvatarView(url: creator?.avatarUrl, name: name, size: 58)
                }
                Text(name)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)'s story\(group.hasUnviewed ? ", new" : "")")
    }

    private var composer: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let draftImage {
                    Image(uiImage: draftImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                TextField("Say something (optional)", text: $draftCaption)
                    .textFieldStyle(.roundedBorder)
                if let postError {
                    Text(postError).font(.caption).foregroundColor(.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("New story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showComposer = false; draftImage = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") { Task { await post() } }
                        .disabled(draftImage == nil || isPosting)
                }
            }
            .overlay { if isPosting { ProgressView() } }
        }
    }

    private func post() async {
        guard let image = draftImage, let data = image.jpegData(compressionQuality: 0.72) else { return }
        isPosting = true; defer { isPosting = false }
        do {
            _ = try await store.post(imageData: data, caption: draftCaption, assetId: nil)
            ARHaptics.success()
            showComposer = false
            draftImage = nil
        } catch {
            postError = error.localizedDescription
        }
    }
}

// MARK: - Viewer

struct StoryViewer: View {
    let group: StoryAuthorGroup
    let allGroups: [StoryAuthorGroup]
    let onClose: () -> Void

    @ObservedObject private var store = StoryStore.shared
    @ObservedObject private var creators = CreatorCache.shared
    @State private var groupIndex: Int = 0
    @State private var storyIndex: Int = 0
    @State private var progress: CGFloat = 0
    @State private var timer: Timer?

    private var currentGroup: StoryAuthorGroup {
        allGroups.indices.contains(groupIndex) ? allGroups[groupIndex] : group
    }
    private var currentStory: StoryItem? {
        let stories = currentGroup.stories
        guard stories.indices.contains(storyIndex) else { return stories.last }
        return stories[storyIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let story = currentStory {
                AsyncImage(url: URL(string: story.mediaUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: "photo").font(.largeTitle).foregroundColor(.white)
                    default:
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if let caption = story.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(.black.opacity(0.45))
                    }
                }
            }

            VStack(spacing: 10) {
                progressBars
                header
                Spacer()
            }
            .padding(.top, 8)

            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { advance(by: -1) }
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { advance(by: 1) }
            }
        }
        .statusBarHidden()
        .onAppear {
            if let idx = allGroups.firstIndex(where: { $0.userId == group.userId }) {
                groupIndex = idx
            }
            storyIndex = currentGroup.stories.firstIndex(where: { !$0.viewed }) ?? 0
            startTimer()
            Task { if let s = currentStory { await store.markViewed(s) } }
        }
        .onDisappear { timer?.invalidate() }
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(Array(currentGroup.stories.enumerated()), id: \.element.id) { i, _ in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white)
                            .frame(width: geo.size.width * (i < storyIndex ? 1 : (i == storyIndex ? progress : 0)))
                    }
                }
                .frame(height: 2.5)
            }
        }
        .padding(.horizontal, 12)
    }

    private var header: some View {
        let creator = creators.creator(currentGroup.userId)
        return HStack(spacing: 10) {
            ARAvatarView(url: creator?.avatarUrl, name: creator?.displayName ?? "Creator", size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(creator?.displayName ?? "Creator")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                if let story = currentStory {
                    Text(story.createdAt.shortRelative)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.bold())
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .accessibilityLabel("Close stories")
        }
        .padding(.horizontal, 14)
    }

    private func startTimer() {
        timer?.invalidate()
        progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                progress += 0.05 / 5.0
                if progress >= 1 { advance(by: 1) }
            }
        }
    }

    private func advance(by delta: Int) {
        let stories = currentGroup.stories
        let next = storyIndex + delta
        if stories.indices.contains(next) {
            storyIndex = next
            startTimer()
            Task { if let s = currentStory { await store.markViewed(s) } }
            return
        }
        let nextGroup = groupIndex + (delta > 0 ? 1 : -1)
        if allGroups.indices.contains(nextGroup) {
            groupIndex = nextGroup
            storyIndex = delta > 0 ? 0 : max(0, currentGroup.stories.count - 1)
            startTimer()
            Task { if let s = currentStory { await store.markViewed(s) } }
        } else {
            onClose()
        }
    }
}

extension StoryAuthorGroup: Hashable {
    static func == (lhs: StoryAuthorGroup, rhs: StoryAuthorGroup) -> Bool { lhs.userId == rhs.userId }
    func hash(into hasher: inout Hasher) { hasher.combine(userId) }
}
