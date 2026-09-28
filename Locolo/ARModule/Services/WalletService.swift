//
//  WalletService.swift
//  Locolo
//
//  Phase C embedded-wallet linking (address only — never keys). Degrades when
//  §5.19 isn't applied. Real passkey / Coinbase Smart Wallet SDK hooks later.
//

import Foundation
import Combine
import Supabase

struct LinkedWallet: Identifiable, Hashable {
    var id: String { "\(chain):\(address)" }
    let address: String
    let chain: String
    let provider: String?
    let isPrimary: Bool
}

@MainActor
final class WalletService: ObservableObject {
    static let shared = WalletService()

    @Published private(set) var wallets: [LinkedWallet] = []
    @Published private(set) var available = true
    @Published private(set) var hasLoaded = false

    private let client = SupabaseManager.shared.client
    private var me: UUID?

    private init() {}

    func configure(me: UUID) {
        if self.me != me {
            wallets = []
            hasLoaded = false
            available = true
        }
        self.me = me
    }

    func reset() {
        me = nil
        wallets = []
        hasLoaded = false
        available = true
    }

    var primary: LinkedWallet? { wallets.first(where: \.isPrimary) ?? wallets.first }

    private struct Row: Decodable {
        let address: String
        let chain: String
        let provider: String?
        let is_primary: Bool
    }

    private struct LinkParams: Encodable {
        let p_address: String
        let p_chain: String
        let p_provider: String
    }

    func refresh() async {
        guard me != nil else { return }
        do {
            let rows: [Row] = try await client
                .rpc("get_my_wallets")
                .execute()
                .value
            available = true
            wallets = rows.map {
                LinkedWallet(address: $0.address, chain: $0.chain,
                             provider: $0.provider, isPrimary: $0.is_primary)
            }
        } catch {
            if EngagementStore.isMissingSchema(error) {
                available = false
                wallets = []
            }
        }
        hasLoaded = true
    }

    func link(address: String, chain: String = "base",
              provider: String = "coinbase_smart_wallet") async throws {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client
            .rpc("link_wallet", params: LinkParams(
                p_address: trimmed, p_chain: chain, p_provider: provider))
            .execute()
        await refresh()
    }
}
