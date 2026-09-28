//
//  CommentsSheet.swift
//  Locolo
//
//  Comment thread for an AR asset. Presented as a resizable sheet from feed
//  cards and the detail sheet. Blocked users and reported comments are
//  filtered through SafetyService; RLS enforces who may post/delete.
//

import SwiftUI

struct CommentsSheet: View {
    let asset: DigitalAsset
    /// Opens a profile; the sheet dismisses itself first.
    var onOpenProfile: ((UUID) -> Void)? = nil

    @EnvironmentObject private var userVM: UserViewModel
    @ObservedObject private var safety = SafetyService.shared
    @ObservedObject private var creators = CreatorCache.shared
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case loading, loaded, unavailable, failed }

    @State private var comments: [AssetComment] = []
    @State private var phase: Phase = .loading
    @State private var draft = ""
    @State private var isPosting = false
    @State private var banner: String?
    @State private var reporting: AssetComment?
    @State private var pendingDelete: AssetComment?
    @State private var reportedToast = false
    @State private var replyTo: AssetComment?
    @FocusState private var composerFocused: Bool

    private static let quickReactions = ["🔥", "😍", "👏", "🤯", "✨", "💜"]

    private var me: UUID? { userVM.currentUser?.id }
    private var visibleComments: [AssetComment] { safety.visible(comments) }
    private var rootComments: [AssetComment] {
        visibleComments.filter { $0.parentId == nil }
    }
    private func replies(to parent: UUID) -> [AssetComment] {
        visibleComments.filter { $0.parentId == parent }
    }
    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if phase != .unavailable {
                    composer
                }
            }
            .background(ARDesign.screenBackground.ignoresSafeArea())
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .top) { toast }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
        .confirmationDialog("Report comment", isPresented: Binding(
            get: { reporting != nil }, set: { if !$0 { reporting = nil } }
        ), titleVisibility: .visible, presenting: reporting) { comment in
            ForEach(SafetyService.ReportReason.allCases) { reason in
                Button(reason.title) { Task { await report(comment, reason: reason) } }
            }
        } message: { _ in
            Text("The comment will be hidden for you and reviewed by our team.")
        }
        .confirmationDialog("Delete this comment?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { comment in
            Button("Delete", role: .destructive) { Task { await delete(comment) } }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in ARRowSkeleton() }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        case .unavailable:
            ARInlineEmptyState(
                icon: "bubble.left.and.bubble.right",
                title: "Comments are coming soon",
                subtitle: "Hype this creation to show the creator some love in the meantime."
            )
        case .failed:
            ARInlineEmptyState(
                icon: "wifi.exclamationmark",
                title: "Couldn't load comments",
                subtitle: "Check your connection and try again.",
                actionTitle: "Retry",
                action: { Task { await load() } }
            )
        case .loaded:
            if visibleComments.isEmpty {
                ARInlineEmptyState(
                    icon: "bubble.left.and.text.bubble.right",
                    title: "No comments yet",
                    subtitle: "Start the conversation — say what you think.",
                    actionTitle: "Add a comment",
                    action: { composerFocused = true }
                )
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(rootComments) { comment in
                    row(comment, isReply: false)
                        .id(comment.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            swipeActions(for: comment)
                        }
                    ForEach(replies(to: comment.id)) { reply in
                        row(reply, isReply: true)
                            .id(reply.id)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 52, bottom: 4, trailing: 18))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                swipeActions(for: reply)
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: comments.count) { _, _ in
                if let last = visibleComments.last {
                    withAnimation(ARDesign.spring) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func swipeActions(for comment: AssetComment) -> some View {
        if canDelete(comment) {
            Button(role: .destructive) { pendingDelete = comment } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        if comment.userId != me {
            Button { reporting = comment } label: {
                Label("Report", systemImage: "flag")
            }
            .tint(.orange)
        }
    }

    private func row(_ comment: AssetComment, isReply: Bool) -> some View {
        let author = creators.creator(comment.userId)
        return HStack(alignment: .top, spacing: 12) {
            Button { openProfile(comment.userId) } label: {
                ARAvatarView(url: author?.avatarUrl, name: author?.displayName ?? "?", size: isReply ? 28 : 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(author?.displayName ?? "creator")'s profile")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ARCreatorName(creator: author, fallback: "Explorer", font: .footnote.weight(.semibold))
                    if comment.userId == asset.userId {
                        Text("Creator")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.purplePinkGradient))
                    }
                    Text(comment.createdAt.shortRelative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(comment.body)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 14) {
                    if CommentsRepository.shared.likesAvailable {
                        Button {
                            Task { await toggleLike(comment) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: comment.likedByMe ? "heart.fill" : "heart")
                                    .font(.caption)
                                    .foregroundColor(comment.likedByMe ? .pink : .secondary)
                                if comment.likeCount > 0 {
                                    Text("\(comment.likeCount)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        replyTo = comment
                        let handle = author?.username ?? ""
                        if !handle.isEmpty, !draft.contains("@\(handle)") {
                            draft = "@\(handle) "
                        }
                        composerFocused = true
                    } label: {
                        Text("Reply")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            Button { UIPasteboard.general.string = comment.body } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if comment.userId != me {
                Button { reporting = comment } label: {
                    Label("Report", systemImage: "flag")
                }
                Button(role: .destructive) {
                    Task {
                        guard let me else { return }
                        await safety.block(comment.userId, by: me)
                        ARHaptics.success()
                    }
                } label: {
                    Label("Block \(author?.displayName ?? "user")", systemImage: "hand.raised")
                }
            }
            if me == asset.userId, CommentsRepository.shared.moderationAvailable {
                Button {
                    Task {
                        try? await CommentsRepository.shared.setPinned(
                            commentId: comment.id, pinned: !comment.pinned)
                        await load()
                    }
                } label: {
                    Label(comment.pinned ? "Unpin" : "Pin comment", systemImage: "pin")
                }
                Button {
                    Task {
                        try? await CommentsRepository.shared.setHiddenByCreator(
                            commentId: comment.id, hidden: true)
                        await load()
                    }
                } label: {
                    Label("Hide comment", systemImage: "eye.slash")
                }
            }
            if canDelete(comment) {
                Button(role: .destructive) { pendingDelete = comment } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if let banner {
                Text(banner)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
            }

            if let replyTo {
                HStack {
                    Text("Replying to comment")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel") {
                        self.replyTo = nil
                    }
                    .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 18)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.quickReactions, id: \.self) { emoji in
                        Button {
                            ARHaptics.tick()
                            draft += emoji
                        } label: {
                            Text(emoji)
                                .font(.title3)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(ARDesign.headerButtonCircle))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(emoji)")
                    }
                }
                .padding(.horizontal, 18)
            }

            HStack(alignment: .bottom, spacing: 10) {
                ARAvatarView(url: userVM.currentUser?.avatarUrl,
                             name: userVM.currentUser?.name ?? userVM.currentUser?.username ?? "Me",
                             size: 34)

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .submitLabel(.send)
                        .onChange(of: draft) { _, value in
                            if value.count > CommentsRepository.maxLength {
                                draft = String(value.prefix(CommentsRepository.maxLength))
                            }
                        }
                    let remaining = CommentsRepository.maxLength - draft.count
                    if remaining < 80 {
                        Text("\(remaining)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(remaining < 20 ? .red : .secondary)
                            .padding(.bottom, 2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ARDesign.headerButtonCircle))

                Button { Task { await post() } } label: {
                    ZStack {
                        Circle()
                            .fill(trimmedDraft.isEmpty
                                  ? AnyShapeStyle(ARDesign.headerButtonCircle)
                                  : AnyShapeStyle(AppColors.purplePinkGradient))
                            .frame(width: 38, height: 38)
                        if isPosting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(trimmedDraft.isEmpty ? .secondary : .white)
                        }
                    }
                }
                .disabled(trimmedDraft.isEmpty || isPosting)
                .accessibilityLabel("Post comment")
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    @ViewBuilder
    private var toast: some View {
        if reportedToast {
            Label("Thanks — comment reported", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.8)))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Actions

    private func canDelete(_ c: AssetComment) -> Bool {
        guard let me else { return false }
        return c.userId == me || asset.userId == me
    }

    private func openProfile(_ id: UUID) {
        guard let onOpenProfile else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onOpenProfile(id) }
    }

    private func load() async {
        if comments.isEmpty { phase = .loading }
        do {
            let rows = try await CommentsRepository.shared.fetch(assetId: asset.id)
            await CreatorCache.shared.load(rows.map(\.userId))
            comments = rows
            EngagementStore.shared.setCommentCount(rows.count, for: asset.id)
            phase = .loaded
        } catch CommentsError.unavailable {
            EngagementStore.shared.markCommentsUnavailable()
            phase = .unavailable
        } catch {
            phase = .failed
        }
    }

    private func post() async {
        guard let me, !trimmedDraft.isEmpty, !isPosting else { return }
        isPosting = true
        banner = nil
        defer { isPosting = false }
        do {
            let parent = replyTo.map { $0.parentId ?? $0.id } // reply to root of thread
            let comment = try await CommentsRepository.shared.post(
                assetId: asset.id, userId: me, body: trimmedDraft, parentId: parent)
            await CreatorCache.shared.load([me])
            withAnimation(ARDesign.spring) { comments.append(comment) }
            EngagementStore.shared.adjustCommentCount(by: 1, for: asset.id)
            draft = ""
            replyTo = nil
            ARHaptics.success()
        } catch {
            banner = error.localizedDescription
        }
    }

    private func toggleLike(_ comment: AssetComment) async {
        guard let idx = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        let was = comments[idx].likedByMe
        comments[idx].likedByMe.toggle()
        comments[idx].likeCount += was ? -1 : 1
        do {
            let nowOn = try await CommentsRepository.shared.toggleLike(commentId: comment.id)
            comments[idx].likedByMe = nowOn
            if !was && nowOn { ARHaptics.tick() }
        } catch {
            comments[idx].likedByMe = was
            comments[idx].likeCount += was ? 1 : -1
        }
    }

    private func delete(_ comment: AssetComment) async {
        let snapshot = comments
        withAnimation(ARDesign.spring) {
            comments.removeAll { $0.id == comment.id || $0.parentId == comment.id }
        }
        do {
            try await CommentsRepository.shared.delete(commentId: comment.id)
            EngagementStore.shared.adjustCommentCount(by: -1, for: asset.id)
        } catch {
            comments = snapshot
            banner = "Couldn't delete that comment. Try again."
        }
    }

    private func report(_ comment: AssetComment, reason: SafetyService.ReportReason) async {
        guard let me else { return }
        await safety.reportComment(comment, reason: reason, details: nil, reporter: me)
        ARHaptics.success()
        withAnimation(ARDesign.spring) { reportedToast = true }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        withAnimation(ARDesign.spring) { reportedToast = false }
    }
}
