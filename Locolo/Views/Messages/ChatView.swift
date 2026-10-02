//
//  ChatView.swift
//  Locolo
//
//  E2E-encrypted 1:1 chat (WS6), styled to the LOCOLO design language:
//  gradient bubbles for the sender, glass bubbles for the peer, a lock header,
//  a safety-number-changed banner, and in-conversation search over the
//  locally-decrypted messages (the server only holds ciphertext, so search
//  can only ever run on-device).
//

import SwiftUI
import Foundation

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel
    let currentUserId: String
    let currentUserName: String

    @State private var text = ""
    @State private var searchQuery = ""
    /// An asset-share card was tapped → open its detail sheet.
    @State private var openedAsset: DigitalAsset?

    init(vm: ChatViewModel, currentUserId: String, currentUserName: String) {
        self._vm = ObservedObject(initialValue: vm)
        self.currentUserId = currentUserId
        self.currentUserName = currentUserName
    }

    /// Messages filtered by the local search query (decrypted text only).
    private var visibleMessages: [Message] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return vm.messages }
        return vm.messages.filter {
            ($0.decryptedText ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            encryptionHeader

            if vm.peerKeyChanged {
                keyChangedBanner
            }

            if vm.isGroup && !vm.unreachableMembers.isEmpty {
                Label("\(vm.unreachableMembers.count) member(s) haven't set up encrypted chat yet and won't receive messages.",
                      systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }

            // MARK: Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        let list = visibleMessages
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, msg in
                            let prev = index > 0 ? list[index - 1] : nil
                            let next = index < list.count - 1 ? list[index + 1] : nil
                            if prev == nil || !Calendar.current.isDate(prev!.time, inSameDayAs: msg.time) {
                                daySeparator(msg.time)
                            }
                            bubble(for: msg,
                                   firstInRun: prev?.senderId != msg.senderId || msg.time.timeIntervalSince(prev!.time) > 300,
                                   lastInRun: next?.senderId != msg.senderId || next!.time.timeIntervalSince(msg.time) > 300)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: vm.messages.count) {
                    if let last = vm.messages.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let error = vm.sendError {
                sendErrorBanner(error)
            }

            inputBar
        }
        .background(ARDesign.screenBackground.ignoresSafeArea())
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search this conversation")
        .sheet(item: $openedAsset) { AssetDetailSheet(asset: $0) }
    }

    // MARK: - Header / banners

    private var encryptionHeader: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill").font(.caption2)
            Text("End-to-end encrypted")
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(.secondary)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(ARDesign.screenBackground)
        .accessibilityLabel("This conversation is end-to-end encrypted")
    }

    private var keyChangedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(.orange)
            Text("This person's security key changed. Verify with them before sharing anything sensitive.")
                .font(.caption)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
            Button {
                vm.peerKeyChanged = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Dismiss warning")
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Bubbles

    /// A shared item is a message whose whole body is one locolo:// link.
    private func sharedLink(in msg: Message) -> URL? {
        guard let body = msg.decryptedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.contains(" "), let url = URL(string: body), url.scheme == "locolo" else { return nil }
        return url
    }

    private func daySeparator(_ date: Date) -> some View {
        Text(Calendar.current.isDateInToday(date) ? "Today"
             : Calendar.current.isDateInYesterday(date) ? "Yesterday"
             : date.formatted(date: .abbreviated, time: .omitted))
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bubble(for msg: Message, firstInRun: Bool, lastInRun: Bool) -> some View {
        let isMine = msg.senderId == currentUserId
        let sender = UUID(uuidString: msg.senderId).flatMap { CreatorCache.shared.creator($0) }
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 48) }

            // Instagram shows the sender's avatar beside the last bubble of a run.
            if !isMine && vm.isGroup {
                if lastInRun {
                    ARAvatarView(url: sender?.avatarUrl, name: sender?.displayName ?? msg.senderName, size: 28)
                } else {
                    Color.clear.frame(width: 28, height: 1)
                }
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if vm.isGroup && !isMine && firstInRun {
                    Text(sender?.displayName ?? msg.senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                }
                if let link = sharedLink(in: msg) {
                    ChatLinkCard(url: link, isMine: isMine) { asset in openedAsset = asset }
                } else {
                    Text(msg.displayText)
                        .font(.subheadline)
                        .foregroundColor(isMine ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            if isMine {
                                AppColors.purplePinkGradient
                            } else {
                                Rectangle().fill(.ultraThinMaterial)
                            }
                        }
                        .clipShape(BubbleShape(isMine: isMine, tail: lastInRun))
                        .overlay(
                            BubbleShape(isMine: isMine, tail: lastInRun)
                                .stroke(isMine ? Color.clear : ARDesign.hairline, lineWidth: 1)
                        )
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = msg.decryptedText
                            } label: { Label("Copy", systemImage: "doc.on.doc") }
                        }
                }

                if lastInRun {
                    Text(msg.time.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            if !isMine { Spacer(minLength: 48) }
        }
        .padding(.top, firstInRun ? 6 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isMine ? "You" : (sender?.displayName ?? msg.senderName)): \(sharedLink(in: msg) != nil ? "shared a link" : msg.displayText)")
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(ARDesign.hairline, lineWidth: 1))

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(
                        text.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(Color.gray.opacity(0.4))
                            : AnyShapeStyle(AppColors.purplePinkGradient)
                    ))
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        ARHaptics.tick()
        text = ""
        Task {
            let sent = await vm.sendMessage(body, senderId: currentUserId.lowercased(), senderName: currentUserName)
            if !sent {
                ARHaptics.warning()
                if text.isEmpty { text = body }
            }
        }
    }

    private func sendErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
            Button {
                vm.sendError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}

// MARK: - Bubble shape

/// Rounded bubble whose bottom corner on the sender's side tightens on the
/// last message of a run (the iMessage / Instagram "tail" without a hook).
private struct BubbleShape: Shape {
    let isMine: Bool
    let tail: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18, small: CGFloat = tail ? 6 : 18
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: r,
            bottomLeading: isMine ? r : small,
            bottomTrailing: isMine ? small : r,
            topTrailing: r))
    }
}

// MARK: - Shared link cards

/// Picks the right rich card for a shared locolo:// link.
private struct ChatLinkCard: View {
    let url: URL
    let isMine: Bool
    let onOpenAsset: (DigitalAsset) -> Void

    var body: some View {
        if let id = DeepLinkRouter.assetId(from: url) {
            AssetShareBubble(assetId: id, isMine: isMine, onOpen: onOpenAsset)
        } else if let id = DeepLinkRouter.userId(from: url) {
            ProfileShareBubble(userId: id, isMine: isMine)
        } else if case .memory(let id)? = DeepLinkRouter.route(from: url) {
            MemoryShareBubble(memoryId: id, isMine: isMine)
        } else if case .post(let id)? = DeepLinkRouter.route(from: url) {
            Button { DeepLinkRouter.shared.handle(url) } label: {
                LinkedEmbed(link: .post(id))
                    .frame(width: 240)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
        } else {
            Text(url.absoluteString).font(.footnote).foregroundColor(.secondary)
        }
    }
}

private struct ProfileShareBubble: View {
    let userId: UUID
    let isMine: Bool
    @ObservedObject private var creators = CreatorCache.shared

    var body: some View {
        let c = creators.creator(userId)
        Button { DeepLinkRouter.shared.handle(DeepLinkRouter.userURL(for: userId)) } label: {
            VStack(spacing: 8) {
                ARAvatarView(url: c?.avatarUrl, name: c?.displayName ?? "?", size: 64)
                ARCreatorName(creator: c, fallback: "Locolo explorer")
                Text("@\(c?.username ?? "")").font(.caption).foregroundColor(.secondary)
                Text("View profile")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .padding(14)
            .frame(width: 200)
            .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ARDesign.hairline))
        }
        .buttonStyle(.plain)
        .task { await CreatorCache.shared.load([userId]) }
    }
}

private struct MemoryShareBubble: View {
    let memoryId: UUID
    let isMine: Bool
    @State private var memory: AssetMemory?

    var body: some View {
        Button { DeepLinkRouter.shared.handle(DeepLinkRouter.memoryURL(for: memoryId)) } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: memory?.previewURL) { $0.resizable().scaledToFill() }
                    placeholder: { Color.purple.opacity(0.25) }
                    .frame(width: 180, height: 250)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Label("Memory", systemImage: memory?.isVideo == true ? "play.fill" : "camera.aperture")
                        .font(.caption2.weight(.bold))
                    Text(memory?.assetName ?? "AR memory").font(.caption.weight(.semibold)).lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(10)
            }
            .frame(width: 180, height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .task { memory = await MemoryStore.shared.fetchOne(memoryId) }
    }
}

// MARK: - Shared asset card (Instagram-style post-in-DM)

/// Renders a shared AR asset as a rich, tappable card. Loads the asset by id
/// (deep link payload) and shows its thumbnail, name and creator.
private struct AssetShareBubble: View {
    let assetId: UUID
    let isMine: Bool
    let onOpen: (DigitalAsset) -> Void

    @State private var asset: DigitalAsset?
    @State private var failed = false

    var body: some View {
        Button {
            if let asset { ARHaptics.tick(); onOpen(asset) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if let asset {
                        AssetThumbnailView(asset: asset, cornerRadius: 0)
                            .aspectRatio(1, contentMode: .fill)
                    } else if failed {
                        Image(systemName: "cube.transparent")
                            .font(.title)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                    } else {
                        ProgressView().tint(.purple)
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                    }
                }
                .frame(width: 210, height: 210)
                .clipped()

                HStack(spacing: 6) {
                    Image(systemName: "arkit")
                        .font(.caption2)
                        .foregroundStyle(AppColors.purplePinkGradient)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(asset?.name ?? (failed ? "AR asset unavailable" : "AR asset"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if let loc = asset?.displayLocation {
                            Text(loc).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        } else {
                            Text("Tap to view in Locolo").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(width: 210)
            }
            .background(Color.adaptive(light: Color(.systemBackground),
                                       dark: Color(red: 0.10, green: 0.07, blue: 0.18)))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isMine ? Color.white.opacity(0.25) : ARDesign.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task {
            if asset == nil {
                let loaded = await DigitalAssetRepository().fetchAsset(id: assetId)
                if let loaded { asset = loaded } else { failed = true }
            }
        }
    }
}
