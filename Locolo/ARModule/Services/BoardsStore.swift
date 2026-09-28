//
//  BoardsStore.swift
//  Locolo
//
//  Phase D boards (Pinterest-style collections). Loads via get_user_boards;
//  degrades to unavailable when the boards migration hasn't been applied.
//

import Foundation
import Combine
import Supabase

struct Board: Identifiable, Hashable {
    let id: UUID
    let ownerId: UUID
    var title: String
    var description: String?
    var visibility: String
    var coverUrl: String?
    var itemCount: Int
    let createdAt: Date
    var updatedAt: Date
}

@MainActor
final class BoardsStore: ObservableObject {
    static let shared = BoardsStore()

    @Published private(set) var mine: [Board] = []
    @Published private(set) var isLoading = false
    @Published private(set) var available = true
    @Published private(set) var hasLoaded = false

    private let client = SupabaseManager.shared.client
    private var me: UUID?

    private init() {}

    func configure(me: UUID) {
        if self.me != me {
            mine = []
            hasLoaded = false
            available = true
        }
        self.me = me
    }

    func reset() {
        me = nil
        mine = []
        hasLoaded = false
        available = true
        isLoading = false
    }

    private struct BoardRow: Decodable {
        let board_id: UUID
        let owner_id: UUID
        let title: String
        let description: String?
        let visibility: String
        let cover_url: String?
        let item_count: Int?
        let created_at: Date
        let updated_at: Date
    }

    private struct ItemIdRow: Decodable {
        let asset_id: UUID
        let created_at: Date
    }

    private struct UserBoardsParams: Encodable {
        let p_user: String
        let p_limit: Int
    }

    private struct BoardItemsParams: Encodable {
        let p_board: String
        let p_limit: Int
    }

    func refresh() async {
        guard let me, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let rows: [BoardRow] = try await client
                .rpc("get_user_boards", params: UserBoardsParams(
                    p_user: me.uuidString.lowercased(), p_limit: 40))
                .execute()
                .value
            available = true
            mine = rows.map(Self.map)
        } catch {
            if EngagementStore.isMissingSchema(error) {
                available = false
                mine = []
            }
        }
    }

    func boards(for userId: UUID) async -> [Board] {
        do {
            let rows: [BoardRow] = try await client
                .rpc("get_user_boards", params: UserBoardsParams(
                    p_user: userId.uuidString.lowercased(), p_limit: 40))
                .execute()
                .value
            available = true
            let boards = rows.map(Self.map)
            if userId == me { mine = boards }
            return boards
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            return []
        }
    }

    func create(title: String, description: String?, visibility: String) async throws -> Board {
        guard let me else {
            throw NSError(domain: "Boards", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Sign in to create a board."])
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "Boards", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Give your board a name."])
        }
        struct Insert: Encodable {
            let owner_id: UUID
            let title: String
            let description: String?
            let visibility: String
        }
        let desc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let vis = ["public", "friends", "private"].contains(visibility) ? visibility : "private"
        let row: BoardRow = try await client
            .from("boards")
            .insert(Insert(
                owner_id: me,
                title: String(trimmed.prefix(60)),
                description: (desc?.isEmpty == false) ? String(desc!.prefix(280)) : nil,
                visibility: vis
            ))
            .select("board_id, owner_id, title, description, visibility, cover_url, created_at, updated_at")
            .single()
            .execute()
            .value
        let board = Self.map(row)
        mine.insert(board, at: 0)
        return board
    }

    @discardableResult
    func add(assetId: UUID, to boardId: UUID, note: String? = nil) async throws -> Bool {
        guard let me else { return false }
        struct Insert: Encodable {
            let board_id: UUID
            let asset_id: UUID
            let added_by: UUID
            let note: String?
        }
        let noteText = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await client.from("board_items")
                .insert(Insert(
                    board_id: boardId, asset_id: assetId, added_by: me,
                    note: (noteText?.isEmpty == false) ? String(noteText!.prefix(200)) : nil
                ))
                .execute()
            if let idx = mine.firstIndex(where: { $0.id == boardId }) {
                mine[idx].itemCount += 1
                mine[idx].updatedAt = Date()
            }
            return true
        } catch {
            let msg = String(describing: error).lowercased()
            if msg.contains("duplicate") || msg.contains("23505") { return true }
            throw error
        }
    }

    func remove(assetId: UUID, from boardId: UUID) async {
        _ = try? await client.from("board_items").delete()
            .eq("board_id", value: boardId)
            .eq("asset_id", value: assetId)
            .execute()
        if let idx = mine.firstIndex(where: { $0.id == boardId }) {
            mine[idx].itemCount = max(0, mine[idx].itemCount - 1)
        }
    }

    func delete(_ board: Board) async {
        mine.removeAll { $0.id == board.id }
        _ = try? await client.from("boards").delete()
            .eq("board_id", value: board.id)
            .execute()
    }

    func loadAssets(on boardId: UUID) async -> [DigitalAsset] {
        do {
            let ids: [ItemIdRow] = try await client
                .rpc("get_board_item_ids", params: BoardItemsParams(
                    p_board: boardId.uuidString.lowercased(), p_limit: 60))
                .execute()
                .value
            guard !ids.isEmpty else { return [] }
            let assets: [DigitalAsset] = try await client
                .from("digital_assets_flat")
                .select()
                .in("asset_id", values: ids.map { $0.asset_id.uuidString })
                .execute()
                .value
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element.asset_id, $0.offset) })
            return SafetyService.shared.visible(assets)
                .sorted { (order[$0.id] ?? 999) < (order[$1.id] ?? 999) }
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            return []
        }
    }

    private static func map(_ row: BoardRow) -> Board {
        Board(id: row.board_id, ownerId: row.owner_id, title: row.title,
              description: row.description, visibility: row.visibility,
              coverUrl: row.cover_url, itemCount: row.item_count ?? 0,
              createdAt: row.created_at, updatedAt: row.updated_at)
    }
}
