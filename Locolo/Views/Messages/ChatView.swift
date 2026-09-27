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

            // MARK: Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleMessages) { msg in
                            bubble(for: msg)
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

    @ViewBuilder
    private func bubble(for msg: Message) -> some View {
        let isMine = msg.senderId == currentUserId
        HStack {
            if isMine { Spacer(minLength: 48) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
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
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isMine ? Color.clear : ARDesign.hairline, lineWidth: 1)
                    )

                Text(msg.time.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            if !isMine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isMine ? "You" : msg.senderName): \(msg.displayText)")
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
