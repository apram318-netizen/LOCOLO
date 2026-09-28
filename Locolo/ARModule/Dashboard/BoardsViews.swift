//
//  BoardsViews.swift
//  Locolo
//
//  Phase D boards: list, detail grid, create sheet, and "Save to board"
//  picker used from asset surfaces.
//

import SwiftUI

// MARK: - List

struct BoardsListView: View {
    var ownerId: UUID? = nil

    @ObservedObject private var store = BoardsStore.shared
    @EnvironmentObject private var userVM: UserViewModel
    @EnvironmentObject private var dashboardState: ARDashboardState

    @State private var boards: [Board] = []
    @State private var showCreate = false
    @State private var isLoading = true

    private var targetId: UUID? { ownerId ?? userVM.currentUser?.id }
    private var isMine: Bool { targetId == userVM.currentUser?.id }

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()
            Group {
                if !store.available && store.hasLoaded {
                    ARInlineEmptyState(
                        icon: "square.stack.3d.up",
                        title: "Boards coming soon",
                        subtitle: "Curated collections of AR art will show up here once they're live."
                    )
                } else if isLoading {
                    ProgressView().tint(.purple)
                } else if boards.isEmpty {
                    ARInlineEmptyState(
                        icon: "square.stack.3d.up",
                        title: isMine ? "No boards yet" : "No public boards",
                        subtitle: isMine
                            ? "Group pieces you love — street art, want-to-collect, a weekend trail."
                            : "This creator hasn't shared any boards.",
                        actionTitle: isMine ? "New board" : nil,
                        action: isMine ? { showCreate = true } : nil
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            ForEach(boards) { board in
                                Button {
                                    dashboardState.path.append(.board(boardId: board.id))
                                } label: {
                                    BoardCoverCard(board: board)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                    .refreshable { await reload() }
                }
            }
        }
        .navigationTitle("Boards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMine && store.available {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New board")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateBoardSheet { board in
                boards.insert(board, at: 0)
                showCreate = false
                dashboardState.path.append(.board(boardId: board.id))
            }
            .presentationDetents([.medium])
        }
        .task { await reload() }
    }

    private func reload() async {
        guard let targetId else { isLoading = false; return }
        isLoading = boards.isEmpty
        if isMine {
            await store.refresh()
            boards = store.mine
        } else {
            boards = await store.boards(for: targetId)
        }
        isLoading = false
    }
}

private struct BoardCoverCard: View {
    let board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.adaptive(light: Color.black.opacity(0.06),
                                         dark: Color.white.opacity(0.08)))
                if let url = board.coverUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 120)
            .clipped()

            Text(board.title)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
                .lineLimit(1)
            Text("\(board.itemCount) piece\(board.itemCount == 1 ? "" : "s") · \(board.visibility)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(board.title), \(board.itemCount) pieces, \(board.visibility)")
    }
}

// MARK: - Detail

struct BoardDetailView: View {
    let boardId: UUID

    @ObservedObject private var store = BoardsStore.shared
    @EnvironmentObject private var userVM: UserViewModel
    @EnvironmentObject private var dashboardState: ARDashboardState

    @State private var board: Board?
    @State private var assets: [DigitalAsset] = []
    @State private var selectedAsset: DigitalAsset?
    @State private var isLoading = true

    private var isMine: Bool { board?.ownerId == userVM.currentUser?.id }

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()
            if isLoading {
                ProgressView().tint(.purple)
            } else if let board {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(board.title)
                                .font(.title2.bold())
                            if let desc = board.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Text("\(board.itemCount) piece\(board.itemCount == 1 ? "" : "s") · \(board.visibility)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        if assets.isEmpty {
                            ARInlineEmptyState(
                                icon: "photo.on.rectangle",
                                title: "Empty board",
                                subtitle: isMine
                                    ? "Save art from Explore or a detail page to fill this board."
                                    : "Nothing here yet."
                            )
                            .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                                GridItem(.flexible(), spacing: 10)],
                                      spacing: 10) {
                                ForEach(assets) { asset in
                                    Button { selectedAsset = asset } label: {
                                        AssetThumbnailView(asset: asset, cornerRadius: 14)
                                            .aspectRatio(1, contentMode: .fill)
                                            .clipped()
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if isMine {
                                            Button(role: .destructive) {
                                                Task {
                                                    await store.remove(assetId: asset.id, from: boardId)
                                                    assets.removeAll { $0.id == asset.id }
                                                }
                                            } label: {
                                                Label("Remove from board", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .refreshable { await reload() }
            } else {
                ARInlineEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Board not found",
                    subtitle: "It may be private or was deleted."
                )
            }
        }
        .navigationTitle(board?.title ?? "Board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMine, let board {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                await store.delete(board)
                                dashboardState.path.removeAll { $0 == .board(boardId: boardId) }
                            }
                        } label: {
                            Label("Delete board", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $selectedAsset) { asset in
            AssetDetailSheet(
                asset: asset,
                onOpenCreator: { dashboardState.path.append(.profile(userId: asset.userId)) },
                onOpenProfile: { dashboardState.path.append(.profile(userId: $0)) }
            )
        }
        .task { await reload() }
    }

    private func reload() async {
        isLoading = board == nil && assets.isEmpty
        if let me = userVM.currentUser?.id {
            if store.mine.isEmpty { await store.refresh() }
            if let mine = store.mine.first(where: { $0.id == boardId }) {
                board = mine
            } else {
                board = (await store.boards(for: me)).first { $0.id == boardId }
            }
        }
        assets = await store.loadAssets(on: boardId)
        if board == nil, !assets.isEmpty {
            board = Board(id: boardId, ownerId: UUID(), title: "Board",
                          description: nil, visibility: "public", coverUrl: nil,
                          itemCount: assets.count, createdAt: Date(), updatedAt: Date())
        }
        isLoading = false
    }
}

// MARK: - Create

struct CreateBoardSheet: View {
    var onCreated: (Board) -> Void

    @ObservedObject private var store = BoardsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var visibility = "private"
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Melbourne Street Art", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Who can see it") {
                    Picker("Visibility", selection: $visibility) {
                        Text("Only me").tag("private")
                        Text("Friends").tag("friends")
                        Text("Everyone").tag("public")
                    }
                    .pickerStyle(.inline)
                }
                if let error {
                    Text(error).font(.caption).foregroundColor(.red)
                }
            }
            .navigationTitle("New board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay { if isSaving { ProgressView() } }
        }
    }

    private func create() async {
        isSaving = true; defer { isSaving = false }
        do {
            let board = try await store.create(title: title, description: description, visibility: visibility)
            ARHaptics.success()
            onCreated(board)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Save to board picker

struct SaveToBoardSheet: View {
    let asset: DigitalAsset

    @ObservedObject private var store = BoardsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showCreate = false
    @State private var banner: String?
    @State private var busyId: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if !store.available && store.hasLoaded {
                    ARInlineEmptyState(
                        icon: "square.stack.3d.up",
                        title: "Boards coming soon",
                        subtitle: "You'll be able to save pieces into named boards once this is live."
                    )
                } else {
                    List {
                        if store.mine.isEmpty {
                            Text("Create a board to start collecting.")
                                .foregroundColor(.secondary)
                        }
                        ForEach(store.mine) { board in
                            Button {
                                Task { await add(to: board) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(board.title).font(.body.weight(.semibold))
                                        Text("\(board.itemCount) pieces")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if busyId == board.id {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(AppColors.purplePinkGradient)
                                    }
                                }
                            }
                            .disabled(busyId != nil)
                        }
                    }
                }
            }
            .navigationTitle("Save to board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!store.available)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let banner {
                    Text(banner)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.9))
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateBoardSheet { board in
                    showCreate = false
                    Task { await add(to: board) }
                }
                .presentationDetents([.medium])
            }
            .task {
                if !store.hasLoaded { await store.refresh() }
            }
        }
    }

    private func add(to board: Board) async {
        busyId = board.id
        defer { busyId = nil }
        do {
            _ = try await store.add(assetId: asset.id, to: board.id)
            ARHaptics.success()
            banner = "Saved to \(board.title)"
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            banner = error.localizedDescription
        }
    }
}
