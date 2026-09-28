//
//  MintingService.swift
//  Locolo
//
//  Paid minting + coupon codes. Users pay a mint fee to create an asset; a
//  coupon can discount it (a 100%-off coupon like the test code mints free).
//  Wraps the server RPCs (preview_mint_fee / create_mint_order) which own all
//  validation — the client never sees the coupon table.
//
//  Payment rail note: a $0 (waived) order needs no payment and settles server-
//  side immediately. Paid orders (total > 0) await Phase B (Apple Pay / Stripe);
//  until then the UI offers "apply a coupon to mint now".
//

import Foundation
import Supabase

@MainActor
final class MintingService {
    static let shared = MintingService()
    private let client = SupabaseManager.shared.client
    private init() {}

    struct FeeQuote: Decodable {
        let fee: Double
        let discount: Double
        let total: Double
        let valid: Bool
        let reason: String?
    }

    struct OrderResult: Decodable {
        let order_id: UUID
        let total: Double
        let status: String   // 'pending' | 'waived'
    }

    private struct CouponParam: Encodable { let p_coupon: String }

    /// Preview the fee with an optional coupon (does not consume it).
    func preview(coupon: String?) async -> FeeQuote? {
        do {
            let rows: [FeeQuote] = try await client
                .rpc("preview_mint_fee", params: CouponParam(p_coupon: coupon ?? ""))
                .execute()
                .value
            return rows.first
        } catch {
            print("preview_mint_fee failed:", error.localizedDescription)
            return nil
        }
    }

    /// Create a mint order. A 100%-off coupon returns status 'waived' (free);
    /// otherwise 'pending' (awaiting payment). Throws with the server's reason
    /// if the coupon is invalid.
    func createOrder(coupon: String?) async throws -> OrderResult {
        let rows: [OrderResult] = try await client
            .rpc("create_mint_order", params: CouponParam(p_coupon: coupon ?? ""))
            .execute()
            .value
        guard let first = rows.first else {
            throw NSError(domain: "Minting", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't start the mint order."])
        }
        return first
    }

    private struct AttachParams: Encodable {
        let p_order: String
        let p_asset: String
    }

    /// Bind a waived/paid order to the asset just inserted. Marks the order
    /// `consumed`. Idempotent if already linked to the same asset.
    func attach(orderId: UUID, assetId: UUID) async throws {
        try await client
            .rpc("attach_mint_order", params: AttachParams(
                p_order: orderId.uuidString.lowercased(),
                p_asset: assetId.uuidString.lowercased()))
            .execute()
    }
}
