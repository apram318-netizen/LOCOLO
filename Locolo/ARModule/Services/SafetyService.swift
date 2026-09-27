//
//  SafetyService.swift
//  Locolo
//
//  Trust & safety for user-generated AR content: blocking creators, reporting
//  assets/users, and self-serve account deletion (App Store guidelines 1.2
//  and 5.1.1(v)).
//
//  Blocks and hidden assets are persisted locally so they take effect instantly
//  and survive offline use; the server copy (user_blocks / content_reports,
//  see docs/migrations/2026_ar_safety_and_hardening.sql) is best-effort.
//

import Foundation
import Combine
import Supabase

@MainActor
final class SafetyService: ObservableObject {
    static let shared = SafetyService()

    @Published private(set) var blockedUserIds: Set<UUID> = []
    /// Assets this user reported — hidden from them immediately.
    @Published private(set) var hiddenAssetIds: Set<UUID> = []

    enum ReportReason: String, CaseIterable, Identifiable {
        case spam
        case harassment
        case nudity
        case violence
        case hate
        case intellectualProperty = "intellectual_property"
        case unsafeLocation = "unsafe_location"
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .spam:                 return "Spam or scam"
            case .harassment:           return "Harassment or bullying"
            case .nudity:               return "Nudity or sexual content"
            case .violence:             return "Violence or threats"
            case .hate:                 return "Hate speech or symbols"
            case .intellectualProperty: return "Stolen or copyrighted work"
            case .unsafeLocation:       return "Placed somewhere unsafe or private"
            case .other:                return "Something else"
            }
        }

        var icon: String {
            switch self {
            case .spam:                 return "envelope.badge.shield.half.filled"
            case .harassment:           return "person.2.slash"
            case .nudity:               return "eye.slash"
            case .violence:             return "exclamationmark.triangle"
            case .hate:                 return "hand.raised.slash"
            case .intellectualProperty: return "c.circle"
            case .unsafeLocation:       return "mappin.slash"
            case .other:                return "ellipsis.bubble"
            }
        }
    }

    private let client = SupabaseManager.shared.client
    private let blockedKey = "ar_safety_blocked_user_ids"
    private let hiddenKey = "ar_safety_hidden_asset_ids"

    private init() {
        blockedUserIds = Self.loadIds(blockedKey)
        hiddenAssetIds = Self.loadIds(hiddenKey)
    }

    // MARK: - Queries

    func isBlocked(_ userId: UUID) -> Bool { blockedUserIds.contains(userId) }

    /// Whether an asset should be kept out of every feed, map, and AR scene.
    func isHidden(_ asset: DigitalAsset) -> Bool {
        blockedUserIds.contains(asset.userId) || hiddenAssetIds.contains(asset.id)
    }

    func visible(_ assets: [DigitalAsset]) -> [DigitalAsset] {
        guard !blockedUserIds.isEmpty || !hiddenAssetIds.isEmpty else { return assets }
        return assets.filter { !isHidden($0) }
    }

    // MARK: - Sync

    private struct BlockRow: Codable {
        let blocker_id: UUID
        let blocked_id: UUID
    }

    /// Merges the server block list into the local one (server may be missing
    /// the table before the safety migration is applied — that's fine).
    func syncBlocks(for me: UUID) async {
        do {
            let rows: [BlockRow] = try await client
                .from("user_blocks")
                .select("blocker_id, blocked_id")
                .eq("blocker_id", value: me)
                .execute()
                .value
            blockedUserIds.formUnion(rows.map(\.blocked_id))
            persist()
        } catch {
            print("Block sync skipped:", error.localizedDescription)
        }
    }

    // MARK: - Block

    func block(_ userId: UUID, by me: UUID) async {
        guard userId != me else { return }
        blockedUserIds.insert(userId)
        persist()
        do {
            try await client
                .from("user_blocks")
                .upsert(BlockRow(blocker_id: me, blocked_id: userId),
                        onConflict: "blocker_id,blocked_id")
                .execute()
        } catch {
            print("Server block failed (kept locally):", error.localizedDescription)
        }
    }

    func unblock(_ userId: UUID, by me: UUID) async {
        blockedUserIds.remove(userId)
        persist()
        do {
            try await client
                .from("user_blocks")
                .delete()
                .eq("blocker_id", value: me)
                .eq("blocked_id", value: userId)
                .execute()
        } catch {
            print("Server unblock failed:", error.localizedDescription)
        }
    }

    // MARK: - Report

    private struct ReportRow: Encodable {
        let reporter_id: UUID
        let asset_id: UUID?
        let reported_user_id: UUID?
        let reason: String
        let details: String?
    }

    /// Files a report and hides the asset for this user right away. Returns
    /// false when the report couldn't reach the server (the hide still sticks).
    @discardableResult
    func report(assetId: UUID?, userId: UUID?, reason: ReportReason,
                details: String?, reporter: UUID) async -> Bool {
        if let assetId {
            hiddenAssetIds.insert(assetId)
            persist()
        }
        let trimmed = (details ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await client
                .from("content_reports")
                .insert(ReportRow(
                    reporter_id: reporter,
                    asset_id: assetId,
                    reported_user_id: userId,
                    reason: reason.rawValue,
                    details: trimmed.isEmpty ? nil : String(trimmed.prefix(1000))
                ))
                .execute()
            return true
        } catch {
            print("Report failed:", error.localizedDescription)
            return false
        }
    }

    // MARK: - Account deletion

    /// Permanently deletes the signed-in account server-side (delete_my_account
    /// RPC removes the auth user; FKs cascade to profile, assets, follows...).
    func deleteMyAccount() async throws {
        try await client.rpc("delete_my_account").execute()
        blockedUserIds = []
        hiddenAssetIds = []
        persist()
    }

    /// Drops the in-memory lists on sign-out so the next account on this
    /// device starts clean (UserDefaults is wiped by logout separately).
    func resetForSignOut() {
        blockedUserIds = []
        hiddenAssetIds = []
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(blockedUserIds.map(\.uuidString), forKey: blockedKey)
        UserDefaults.standard.set(hiddenAssetIds.map(\.uuidString), forKey: hiddenKey)
    }

    private static func loadIds(_ key: String) -> Set<UUID> {
        let strings = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }
}
