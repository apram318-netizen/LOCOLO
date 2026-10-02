//
//  ARShareSheet.swift
//  Locolo
//
//  Instagram-style "Share" sheet used by EVERY share button: a preview of what
//  you're sending, a grid of recent chats + people you follow (multi-select),
//  live people search, an optional message, then Send — plus Copy link /
//  Post about it / Share externally. Sends go through AssetShareService, so
//  every message stays end-to-end encrypted.
//

import SwiftUI

/// What is being shared. Each case maps to a `locolo://` deep link the chat
/// renders as a rich card.
enum ARSharePayload: Identifiable, Hashable {
    static func == (lhs: ARSharePayload, rhs: ARSharePayload) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }

    case asset(DigitalAsset)
    case memory(AssetMemory)
    case post(UserPost)
    case profile(ARCreator)

    var id: String { url.absoluteString }

    var url: URL {
        switch self {
        case .asset(let a): return DeepLinkRouter.assetURL(for: a.id)
        case .memory(let m): return DeepLinkRouter.memoryURL(for: m.id)
        case .post(let p): return DeepLinkRouter.postURL(for: p.id)
        case .profile(let c): return DeepLinkRouter.userURL(for: c.id)
        }
    }

    var title: String {
        switch self {
        case .asset(let a): return a.name ?? "AR asset"
        case .memory(let m): return m.caption ?? "Memory at \(m.assetName ?? "an AR asset")"
        case .post(let p): return p.body ?? "Post"
        case .profile(let c): return c.displayName
        }
    }

    var subtitle: String {
        switch self {
        case .asset: return "AR asset on Locolo"
        case .memory: return "Memory on Locolo"
        case .post: return "Post on Locolo"
        case .profile(let c): return "@\(c.username) on Locolo"
        }
    }

    var externalMessage: String {
        switch self {
        case .asset(let a): return "Check out \"\(a.name ?? "this AR asset")\" on Locolo"
        case .memory: return "Look at this memory on Locolo"
        case .post: return "Look at this post on Locolo"
        case .profile(let c): return "Follow \(c.displayName) on Locolo"
        }
    }

    /// What "Post about it" links to (profiles can't be quoted).
    var postLink: PostLink? {
        switch self {
        case .asset(let a): return .asset(a.id)
        case .memory(let m): return .memory(m.id)
        case .post(let p): return .post(p.id)
        case .profile: return nil
        }
    }
}

struct ARShareSheet: View {
    let payload: ARSharePayload
    /// Shown after the sheet closes ("Sent to Maya").
    var onSent: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userVM: UserViewModel
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var follows = FollowStore.shared
    @ObservedObject private var creators = CreatorCache.shared

    @State private var query = ""
    @State private var results: [ARCreator] = []
    @State private var isSearching = false
    @State private var selected: [ARCreator] = []
    @State private var note = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var copied = false
    @State private var showComposer = false
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 12)]

    /// Recent conversation partners first (Instagram's order), then follows.
    private var suggested: [ARCreator] {
        let blocked = SafetyService.shared.blockedUserIds
        var seen = Set<UUID>()
        var out: [ARCreator] = []
        let recentPeers = inbox.conversations
            .sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { inbox.peerId(of: $0) }
        for id in recentPeers + Array(follows.following) where !seen.contains(id) && !blocked.contains(id) {
            seen.insert(id)
            if let c = creators.creator(id), c.id != userVM.currentUser?.id { out.append(c) }
        }
        return out
    }

    private var people: [ARCreator] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? suggested : results
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                searchField
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                ScrollView {
                    if people.isEmpty {
                        emptyPeople
                            .padding(.top, 30)
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(people) { person in
                                personCell(person)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .scrollDismissesKeyboard(.interactively)

                Divider()
                bottomBar
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                let ids = inbox.conversations.compactMap { inbox.peerId(of: $0) } + Array(follows.following)
                await CreatorCache.shared.load(Array(Set(ids)))
            }
            .task(id: query) { await search() }
            .sheet(isPresented: $showComposer) {
                if let link = payload.postLink {
                    PostComposerView(initialLink: link) { _ in
                        onSent?("Posted to your profile")
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Pieces

    private var previewCard: some View {
        HStack(spacing: 12) {
            previewThumb
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(payload.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(payload.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder
    private var previewThumb: some View {
        switch payload {
        case .asset(let a):
            AssetThumbnailView(asset: a, cornerRadius: 10)
        case .memory(let m):
            AsyncImage(url: m.previewURL) { $0.resizable().scaledToFill() } placeholder: { Color.purple.opacity(0.3) }
        case .post(let p):
            if let first = p.media.first, let url = URL(string: first.url) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.purple.opacity(0.3) }
            } else {
                ZStack {
                    LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "text.quote").foregroundStyle(.white)
                }
            }
        case .profile(let c):
            ARAvatarView(url: c.avatarUrl, name: c.displayName, size: 52)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search people", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func personCell(_ person: ARCreator) -> some View {
        let isOn = selected.contains(person)
        return Button {
            ARHaptics.tick()
            if isOn { selected.removeAll { $0.id == person.id } } else { selected.append(person) }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    ARAvatarView(url: person.avatarUrl, name: person.displayName, size: 64)
                        .overlay(Circle().strokeBorder(isOn ? ARDesign.accent : .clear, lineWidth: 3))
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, ARDesign.accent)
                            .background(Circle().fill(Color(.systemBackground)))
                            .transition(.scale)
                    }
                }
                Text(person.displayName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.displayName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var emptyPeople: some View {
        VStack(spacing: 8) {
            if isSearching {
                ProgressView()
            } else {
                Image(systemName: "person.2").font(.title2).foregroundStyle(.secondary)
                Text(query.isEmpty ? "Search for someone to send this to" : "No one found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if selected.isEmpty {
            HStack(spacing: 0) {
                quickAction(copied ? "Copied" : "Copy link", icon: copied ? "checkmark" : "link") {
                    UIPasteboard.general.url = payload.url
                    ARHaptics.success()
                    copied = true
                }
                if payload.postLink != nil {
                    quickAction("Post about it", icon: "square.and.pencil") { showComposer = true }
                }
                ShareLink(item: payload.url, subject: Text(payload.title), message: Text(payload.externalMessage)) {
                    quickActionLabel("More", icon: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
        } else {
            VStack(spacing: 10) {
                TextField("Write a message…", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }
                Button(action: send) {
                    HStack {
                        if isSending { ProgressView().tint(.white) }
                        Text(selected.count == 1 ? "Send" : "Send separately (\(selected.count))")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ARDesign.accent))
                    .foregroundStyle(.white)
                }
                .disabled(isSending)
            }
            .padding(16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func quickAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { quickActionLabel(title, icon: icon) }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
    }

    private func quickActionLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.primary.opacity(0.07)))
            Text(title).font(.caption)
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Actions

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        isSearching = true
        try? await Task.sleep(nanoseconds: 250_000_000)   // debounce
        guard !Task.isCancelled else { return }
        let found = await PeopleSearch.search(q)
        guard !Task.isCancelled else { return }
        results = found.filter { $0.id != userVM.currentUser?.id && !SafetyService.shared.isBlocked($0.id) }
        isSearching = false
    }

    private func send() {
        guard let me = userVM.currentUser, !selected.isEmpty else { return }
        isSending = true
        errorText = nil
        let targets = selected
        let message = note
        Task {
            var failed: [String] = []
            for person in targets {
                let ok = await AssetShareService.shared.share(payload.url, note: message, to: person.id, from: me)
                if !ok { failed.append(person.displayName) }
            }
            isSending = false
            if failed.isEmpty {
                ARHaptics.success()
                let names = targets.count == 1 ? targets[0].displayName : "\(targets.count) people"
                onSent?("Sent to \(names)")
                dismiss()
            } else {
                ARHaptics.warning()
                errorText = "Couldn't send to \(failed.joined(separator: ", ")). They may not have set up encrypted chat yet."
                selected.removeAll { p in !failed.contains(p.displayName) }
            }
        }
    }
}
