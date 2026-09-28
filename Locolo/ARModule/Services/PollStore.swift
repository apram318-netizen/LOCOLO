//
//  PollStore.swift
//  Locolo
//
//  Phase D polls on assets (§5.20). Degrades when tables aren't applied.
//

import Foundation
import Combine
import Supabase

struct AssetPoll: Identifiable, Hashable {
    let id: UUID
    let assetId: UUID
    var question: String
    var options: [String]
    var endsAt: Date?
    var counts: [Int]
    var myVote: Int?
}

@MainActor
final class PollStore: ObservableObject {
    static let shared = PollStore()

    @Published private(set) var pollsByAsset: [UUID: AssetPoll] = [:]
    @Published private(set) var available = true

    private let client = SupabaseManager.shared.client
    private var me: UUID?

    private init() {}

    func configure(me: UUID) {
        if self.me != me { pollsByAsset = [:]; available = true }
        self.me = me
    }

    func reset() {
        me = nil
        pollsByAsset = [:]
        available = true
    }

    private struct PollRow: Decodable {
        let poll_id: UUID
        let asset_id: UUID
        let question: String
        let options: [String]
        let ends_at: Date?
    }

    private struct VoteRow: Decodable {
        let poll_id: UUID
        let user_id: UUID
        let option_idx: Int
    }

    func load(for assetId: UUID) async {
        guard available else { return }
        do {
            let rows: [PollRow] = try await client
                .from("asset_polls")
                .select("poll_id, asset_id, question, options, ends_at")
                .eq("asset_id", value: assetId)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else {
                pollsByAsset.removeValue(forKey: assetId)
                return
            }
            let votes: [VoteRow] = try await client
                .from("asset_poll_votes")
                .select("poll_id, user_id, option_idx")
                .eq("poll_id", value: row.poll_id)
                .execute()
                .value
            var counts = Array(repeating: 0, count: row.options.count)
            var mine: Int?
            for v in votes {
                if v.option_idx >= 0, v.option_idx < counts.count {
                    counts[v.option_idx] += 1
                }
                if v.user_id == me { mine = v.option_idx }
            }
            pollsByAsset[assetId] = AssetPoll(
                id: row.poll_id, assetId: row.asset_id, question: row.question,
                options: row.options, endsAt: row.ends_at, counts: counts, myVote: mine)
            available = true
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }

    func create(assetId: UUID, question: String, options: [String], endsAt: Date? = nil) async throws {
        struct Insert: Encodable {
            let asset_id: UUID
            let question: String
            let options: [String]
            let ends_at: Date?
        }
        let clean = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard clean.count >= 2 else { return }
        _ = try await client.from("asset_polls")
            .insert(Insert(asset_id: assetId,
                           question: String(question.prefix(140)),
                           options: Array(clean.prefix(6)),
                           ends_at: endsAt))
            .execute()
        await load(for: assetId)
    }

    func vote(pollId: UUID, assetId: UUID, optionIdx: Int) async {
        guard let me else { return }
        struct Ins: Encodable {
            let poll_id: UUID
            let user_id: UUID
            let option_idx: Int
        }
        do {
            try await client.from("asset_poll_votes")
                .upsert(Ins(poll_id: pollId, user_id: me, option_idx: optionIdx))
                .execute()
            await load(for: assetId)
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }
}
