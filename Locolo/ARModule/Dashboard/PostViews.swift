//
//  PostViews.swift
//  Locolo
//
//  User posts ("share something cool, link it, add your own take"):
//    * PostComposerView — text + up to 4 photos + one link (another post, an
//      asset or a memory) chosen from what you're sharing or picked inline.
//    * PostCard         — feed / profile rendering with a quoted embed.
//    * PostDetailRouteView — `locolo://post/<id>`.
//

import SwiftUI
import PhotosUI

// MARK: - Composer

struct PostComposerView: View {
    var initialLink: PostLink? = nil
    var onPosted: ((UserPost) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userVM: UserViewModel
    @ObservedObject private var store = PostStore.shared

    @State private var text = ""
    @State private var link: PostLink?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var visibility = "public"
    @State private var isPosting = false
    @State private var errorText: String?
    @State private var tagIdeas: [String] = []
    @FocusState private var focused: Bool

    private var canPost: Bool {
        !isPosting && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty || link != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        ARAvatarView(url: userVM.currentUser?.avatarUrl,
                                     name: userVM.currentUser?.name ?? userVM.currentUser?.username ?? "?", size: 40)
                        TextField(link == nil ? "What did you discover?" : "Add your take…",
                                  text: $text, axis: .vertical)
                            .lineLimit(3...12)
                            .focused($focused)
                            .onChange(of: text) { _, new in if new.count > 2000 { text = String(new.prefix(2000)) } }
                    }

                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(images.indices, id: \.self) { i in
                                    Image(uiImage: images[i])
                                        .resizable().scaledToFill()
                                        .frame(width: 120, height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                images.remove(at: i)
                                                if i < pickerItems.count { pickerItems.remove(at: i) }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title3)
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .padding(6)
                                        }
                                }
                            }
                        }
                    }

                    if let link {
                        LinkedEmbed(link: link)
                            .overlay(alignment: .topTrailing) {
                                if initialLink == nil {
                                    Button { self.link = nil } label: {
                                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                }
                            }
                    }

                    if !tagIdeas.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles").foregroundStyle(ARDesign.accent)
                                ForEach(tagIdeas, id: \.self) { tag in
                                    Button("#\(tag)") { text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + "#\(tag) " }
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Capsule().fill(ARDesign.accent.opacity(0.12)))
                                }
                            }
                        }
                    }

                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { toolbarRow }
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: post) {
                        if isPosting { ProgressView() } else { Text("Post").bold() }
                    }
                    .disabled(!canPost || !store.available)
                }
            }
            .onAppear {
                link = initialLink
                focused = true
            }
            .onChange(of: pickerItems) { _, items in
                Task {
                    var loaded: [UIImage] = []
                    for item in items.prefix(4) {
                        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                            loaded.append(img)
                        }
                    }
                    images = loaded
                    tagIdeas = await SmartSuggestions.hashtags(for: loaded.first, text: text)
                }
            }
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 18) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                Image(systemName: "photo.on.rectangle.angled").font(.title3)
            }
            .accessibilityLabel("Add photos")
            Spacer()
            Menu {
                Picker("Visibility", selection: $visibility) {
                    Label("Everyone", systemImage: "globe").tag("public")
                    Label("Followers", systemImage: "person.2").tag("friends")
                    Label("Only me", systemImage: "lock").tag("private")
                }
            } label: {
                Label(visibility == "public" ? "Everyone" : visibility == "friends" ? "Followers" : "Only me",
                      systemImage: visibility == "public" ? "globe" : visibility == "friends" ? "person.2" : "lock")
                    .font(.subheadline.weight(.semibold))
            }
            if !store.available {
                Text("Posts turn on after the next update").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func post() {
        isPosting = true
        errorText = nil
        Task {
            do {
                let created = try await store.create(body: text, images: images, link: link, visibility: visibility)
                ARHaptics.success()
                onPosted?(created)
                dismiss()
            } catch {
                ARHaptics.warning()
                errorText = "Couldn't post. Check your connection and try again."
            }
            isPosting = false
        }
    }
}

// MARK: - Linked embed (quote / asset / memory)

struct LinkedEmbed: View {
    let link: PostLink
    var depth = 0

    @State private var asset: DigitalAsset?
    @State private var memory: AssetMemory?
    @State private var post: UserPost?
    @State private var missing = false
    @ObservedObject private var creators = CreatorCache.shared

    var body: some View {
        Group {
            switch link {
            case .asset:
                if let asset { assetEmbed(asset) } else { placeholder }
            case .memory:
                if let memory { memoryEmbed(memory) } else { placeholder }
            case .post:
                if let post { postEmbed(post) } else { placeholder }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ARDesign.hairline))
        .task(id: link) { await load() }
    }

    private var placeholder: some View {
        HStack {
            if missing {
                Label("This content is no longer available", systemImage: "eye.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            Spacer()
        }
        .frame(height: 44)
    }

    private func assetEmbed(_ a: DigitalAsset) -> some View {
        HStack(spacing: 12) {
            AssetThumbnailView(asset: a, cornerRadius: 12).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Label("AR asset", systemImage: "arkit").font(.caption2.weight(.bold)).foregroundStyle(ARDesign.accent)
                Text(a.name ?? "Untitled drop").font(.subheadline.weight(.semibold)).lineLimit(1)
                if let place = a.displayLocation {
                    Text(place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func memoryEmbed(_ m: AssetMemory) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: m.previewURL) { $0.resizable().scaledToFill() } placeholder: { Color.purple.opacity(0.2) }
                .frame(width: 64, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Label("Memory", systemImage: "camera.aperture").font(.caption2.weight(.bold)).foregroundStyle(.pink)
                Text(m.caption ?? "with \(m.assetName ?? "an AR asset")").font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("@\(creators.creator(m.userId)?.username ?? "explorer")").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func postEmbed(_ p: UserPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let author = creators.creator(p.userId)
            HStack(spacing: 6) {
                ARAvatarView(url: author?.avatarUrl, name: author?.displayName ?? "?", size: 20)
                Text(author?.displayName ?? "Someone").font(.caption.weight(.bold))
                Text(p.createdAt.formatted(.relative(presentation: .numeric))).font(.caption2).foregroundStyle(.secondary)
            }
            if let body = p.body { Text(body).font(.subheadline).lineLimit(4) }
            if let first = p.media.first, let url = URL(string: first.url) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.15) }
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            // One level of nesting only (Twitter-style), so quotes of quotes stay readable.
            if depth == 0, let nested = p.innerLink {
                LinkedEmbed(link: nested, depth: 1)
            }
        }
    }

    private func load() async {
        switch link {
        case .asset(let id):
            asset = await DigitalAssetRepository().fetchAsset(id: id)
            missing = asset == nil
        case .memory(let id):
            memory = await MemoryStore.shared.fetchOne(id)
            missing = memory == nil
        case .post(let id):
            post = await PostStore.shared.post(id)
            missing = post == nil
        }
    }
}

extension UserPost {
    var innerLink: PostLink? {
        if let id = linkedPostId { return .post(id) }
        if let id = linkedAssetId { return .asset(id) }
        if let id = linkedMemoryId { return .memory(id) }
        return nil
    }
}

// MARK: - Card

struct PostCard: View {
    let post: UserPost
    var onOpenProfile: ((UUID) -> Void)? = nil
    var onOpenLink: ((PostLink) -> Void)? = nil

    @EnvironmentObject private var userVM: UserViewModel
    @ObservedObject private var store = PostStore.shared
    @ObservedObject private var creators = CreatorCache.shared
    @State private var sharePayload: ARSharePayload?
    @State private var quoting = false
    @State private var confirmDelete = false

    private var live: UserPost { store.cache[post.id] ?? post }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let body = live.body, !body.isEmpty {
                Text(body).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            if !live.media.isEmpty { mediaGrid }
            if let link = live.innerLink {
                Button { onOpenLink?(link) } label: { LinkedEmbed(link: link) }
                    .buttonStyle(.plain)
            }
            actions
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.primary.opacity(0.04)))
        .sheet(item: $sharePayload) { ARShareSheet(payload: $0) }
        .sheet(isPresented: $quoting) { PostComposerView(initialLink: .post(live.id)) }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { _ = await store.delete(live) } }
        }
    }

    private var header: some View {
        let author = creators.creator(live.userId)
        return HStack(spacing: 10) {
            Button { onOpenProfile?(live.userId) } label: {
                HStack(spacing: 10) {
                    ARAvatarView(url: author?.avatarUrl, name: author?.displayName ?? "?", size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        ARCreatorName(creator: author)
                        Text("@\(author?.username ?? "explorer") · \(live.createdAt.formatted(.relative(presentation: .numeric)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button { sharePayload = .post(live) } label: { Label("Send to friends", systemImage: "paperplane") }
                ShareLink(item: DeepLinkRouter.postURL(for: live.id)) { Label("Share externally…", systemImage: "square.and.arrow.up") }
                if live.userId == userVM.currentUser?.id {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis").padding(8).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var mediaGrid: some View {
        let urls = live.media.compactMap { URL(string: $0.url) }
        if urls.count == 1 {
            AsyncImage(url: urls[0]) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.15) }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                ForEach(urls, id: \.self) { url in
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.15) }
                        .frame(height: 160)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var actions: some View {
        HStack(spacing: 22) {
            Button {
                ARHaptics.tick()
                Task { await store.toggleLike(live) }
            } label: {
                Label(live.likeCount.compactFormatted, systemImage: live.likedByMe ? "heart.fill" : "heart")
                    .foregroundStyle(live.likedByMe ? .pink : .primary)
            }
            Button { quoting = true } label: {
                Label(live.quoteCount.compactFormatted, systemImage: "quote.bubble")
            }
            .accessibilityLabel("Quote this post")
            Button { sharePayload = .post(live) } label: {
                Image(systemName: "paperplane")
            }
            .accessibilityLabel("Share")
            Spacer()
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

// MARK: - Route

struct PostDetailRouteView: View {
    let postId: UUID
    @EnvironmentObject private var dashboardState: ARDashboardState
    @State private var post: UserPost?
    @State private var failed = false
    @State private var detailAsset: DigitalAsset?

    var body: some View {
        ScrollView {
            if let post {
                PostCard(post: post,
                         onOpenProfile: { dashboardState.path.append(.profile(userId: $0)) },
                         onOpenLink: open)
                    .padding(16)
            } else if failed {
                ARInlineEmptyState(icon: "text.quote", title: "Post unavailable",
                                   subtitle: "It may have been deleted or made private.")
                    .padding(.top, 80)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(ARDesign.screenBackground.ignoresSafeArea())
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            post = await PostStore.shared.post(postId)
            failed = post == nil
        }
        .sheet(item: $detailAsset) { AssetDetailSheet(asset: $0) }
    }

    private func open(_ link: PostLink) {
        switch link {
        case .post(let id): dashboardState.path.append(.post(postId: id))
        case .memory(let id): dashboardState.path.append(.memory(memoryId: id))
        case .asset(let id): Task { detailAsset = await DigitalAssetRepository().fetchAsset(id: id) }
        }
    }
}
