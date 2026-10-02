//
//  MintPurchaseService.swift
//  Locolo
//
//  Pays a mint order with an App Store In-App Purchase (StoreKit 2). The
//  consumable `com.apram.locolo.mint` is bought with the mint order id as its
//  appAccountToken; the signed transaction goes to the `verify-mint-purchase`
//  edge function, which checks Apple's signature and flips the order to
//  'paid'. Only then is the transaction finished, so an interrupted purchase
//  is retried from `Transaction.updates` / `Transaction.unfinished` on the
//  next launch instead of being lost.
//
//  App Store Connect: create the consumable with this product id, price tier
//  matching app_config.mint_fee_usd, and attach it to the app version.
//

import Foundation
import StoreKit

@MainActor
final class MintPurchaseService: ObservableObject {
    static let shared = MintPurchaseService()
    static let productID = "com.apram.locolo.mint"

    @Published private(set) var product: Product?

    private var updatesTask: Task<Void, Never>?

    private init() {}

    enum PurchaseError: LocalizedError {
        case unavailable, pending, unverified, server(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Purchases aren't available right now. Try again in a moment."
            case .pending: return "Your purchase is waiting for approval. You can post once it goes through."
            case .unverified: return "The App Store couldn't confirm this purchase."
            case .server(let message): return message
            }
        }
    }

    /// Call once at launch: settles purchases that finished while the app was
    /// closed or whose verification call failed last time.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.settle(update)
            }
        }
        Task {
            for await unfinished in Transaction.unfinished {
                await settle(unfinished)
            }
        }
    }

    @discardableResult
    func loadProduct() async -> Product? {
        if let product { return product }
        product = try? await Product.products(for: [Self.productID]).first
        return product
    }

    /// Buys the mint fee for `orderId`. Returns normally once the server has
    /// marked the order paid; returns `false` if the user cancelled.
    func purchase(orderId: UUID) async throws -> Bool {
        guard let product = await loadProduct() else { throw PurchaseError.unavailable }
        let result = try await product.purchase(options: [.appAccountToken(orderId)])
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw PurchaseError.unverified }
            try await verify(orderId: orderId, jws: verification.jwsRepresentation)
            await transaction.finish()
            return true
        case .pending:
            throw PurchaseError.pending
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    private func settle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification,
              transaction.productID == Self.productID else { return }
        guard let orderId = transaction.appAccountToken else {
            await transaction.finish()
            return
        }
        do {
            try await verify(orderId: orderId, jws: verification.jwsRepresentation)
            await transaction.finish()
        } catch {
            LocoloLog.mint.error("mint purchase settle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct VerifyBody: Encodable {
        let order_id: String
        let signed_transaction: String
    }

    private struct VerifyResponse: Decodable {
        let status: String?
        let error: String?
    }

    private func verify(orderId: UUID, jws: String) async throws {
        let request = try await EdgeFunctions.request("verify-mint-purchase", body: VerifyBody(
            order_id: orderId.uuidString.lowercased(), signed_transaction: jws))
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(VerifyResponse.self, from: data)
        guard (200..<300).contains(code), let status = decoded?.status,
              status == "paid" || status == "consumed" else {
            LocoloLog.mint.error("verify-mint-purchase \(code): \(decoded?.error ?? "no body", privacy: .public)")
            throw PurchaseError.server("We couldn't confirm your purchase yet. It will be applied automatically — try posting again shortly.")
        }
    }
}
