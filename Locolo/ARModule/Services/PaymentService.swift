//
//  PaymentService.swift
//  Locolo
//
//  Phase B fiat intents. Creates a pending payment_intent row; real Apple Pay /
//  Stripe / Coinbase Onramp checkout lands via edge fn + partner webhook.
//  Until §5.18 is applied, createIntent fails soft and UI shows "coming soon".
//

import Foundation
import Supabase

struct PaymentIntent: Identifiable, Equatable {
    let id: UUID
    let provider: String
    let providerRef: String
    let amount: Double
    let currency: String
    let purpose: String
    let status: String
}

/// Result of calling the onramp-session edge stub / partner session.
struct CheckoutSession: Equatable {
    let intentId: UUID?
    let checkoutURL: URL?
    let status: String
    let message: String
}

@MainActor
final class PaymentService {
    static let shared = PaymentService()

    private let client = SupabaseManager.shared.client
    private(set) var available = true

    private init() {}

    private struct CreateParams: Encodable {
        let p_provider: String
        let p_amount: Double
        let p_currency: String
        let p_purpose: String
        let p_asset: String?
        let p_mint_order: String?
    }

    private struct Row: Decodable {
        let intent_id: UUID
        let provider: String
        let provider_ref: String
        let amount: Double
        let currency: String
        let purpose: String
        let status: String
    }

    private struct OnrampBody: Encodable {
        let amount: Double
        let currency: String
        let purpose: String
        let provider: String
        let asset_id: String?
        let mint_order_id: String?
    }

    private struct OnrampResponse: Decodable {
        let checkout_url: String?
        let status: String?
        let message: String?
        let intent: IntentBlob?

        struct IntentBlob: Decodable {
            let payout_id: UUID? // unused
            let intent_id: UUID?
            // payment_intents row may expose `id` instead of intent_id
            let id: UUID?
        }
    }

    /// Opens a partner checkout path. Returns a pending intent the UI can poll,
    /// or nil when fiat SQL / edge fn isn't live yet.
    func createIntent(
        provider: String = "coinbase_onramp",
        amount: Double,
        currency: String = "USD",
        purpose: String,
        assetId: UUID? = nil,
        mintOrderId: UUID? = nil
    ) async throws -> PaymentIntent {
        do {
            let row: Row = try await client
                .rpc("create_payment_intent", params: CreateParams(
                    p_provider: provider,
                    p_amount: amount,
                    p_currency: currency,
                    p_purpose: purpose,
                    p_asset: assetId?.uuidString.lowercased(),
                    p_mint_order: mintOrderId?.uuidString.lowercased()
                ))
                .execute()
                .value
            available = true
            return PaymentIntent(
                id: row.intent_id, provider: row.provider, providerRef: row.provider_ref,
                amount: row.amount, currency: row.currency, purpose: row.purpose,
                status: row.status
            )
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            throw error
        }
    }

    /// Calls `onramp-session` for a partner checkout URL. When the edge is a
    /// stub (null URL), returns a pending session with a human message.
    func startCheckout(
        amount: Double,
        purpose: String,
        currency: String = "USD",
        provider: String = "coinbase_onramp",
        assetId: UUID? = nil,
        mintOrderId: UUID? = nil
    ) async -> CheckoutSession {
        do {
            let request = try await EdgeFunctions.request("onramp-session", body: OnrampBody(
                amount: amount,
                currency: currency,
                purpose: purpose,
                provider: provider,
                asset_id: assetId?.uuidString.lowercased(),
                mint_order_id: mintOrderId?.uuidString.lowercased()
            ))
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 || code == 503 {
                return CheckoutSession(
                    intentId: nil, checkoutURL: nil, status: "unavailable",
                    message: checkoutComingSoonMessage)
            }
            let decoded = try JSONDecoder().decode(OnrampResponse.self, from: data)
            let url = decoded.checkout_url.flatMap(URL.init(string:))
            let intentId = decoded.intent?.intent_id ?? decoded.intent?.id
            let message = decoded.message
                ?? (url == nil
                    ? "Checkout session created — partner URL pending. Apply a coupon to mint free, or wait for onramp keys."
                    : "Opening checkout…")
            return CheckoutSession(
                intentId: intentId,
                checkoutURL: url,
                status: decoded.status ?? "pending",
                message: message)
        } catch {
            LocoloLog.market.error("onramp-session failed: \(error.localizedDescription, privacy: .public)")
            return CheckoutSession(
                intentId: nil, checkoutURL: nil, status: "error",
                message: checkoutComingSoonMessage)
        }
    }

    var checkoutComingSoonMessage: String {
        "Apple Pay / card checkout is wired for Phase B. Apply §5.18 SQL and deploy onramp-session (+ partner keys) to go live."
    }

    struct PayoutRow: Identifiable, Equatable, Decodable {
        let payoutId: UUID
        let provider: String
        let amount: Double
        let currency: String
        let status: String
        let createdAt: Date

        var id: UUID { payoutId }

        enum CodingKeys: String, CodingKey {
            case payoutId = "payout_id"
            case provider, amount, currency, status
            case createdAt = "created_at"
        }
    }

    /// Read-only payout history (partner/webhook writes rows; RLS is SELECT-self).
    func listPayouts(limit: Int = 40) async -> [PayoutRow] {
        do {
            let rows: [PayoutRow] = try await client
                .from("payouts")
                .select("payout_id, provider, amount, currency, status, created_at")
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            available = true
            return rows
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            return []
        }
    }
}
