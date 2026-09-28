//
//  MarketplaceRepository.swift
//  Locolo
//
//  Phase A off-chain marketplace: listings, trades, provenance, and
//  portfolio snapshots. Thin Supabase layer for the AR module.
//

import Foundation
import Supabase

// MARK: - Models

struct AssetListing: Identifiable, Codable, Equatable {
    let listingId: UUID
    let assetId: UUID
    let sellerId: UUID
    let kind: String
    let price: Double
    let currency: String
    let endsAt: Date?
    let status: String
    let createdAt: Date

    var id: UUID { listingId }

    enum CodingKeys: String, CodingKey {
        case listingId = "listing_id"
        case assetId = "asset_id"
        case sellerId = "seller_id"
        case kind, price, currency
        case endsAt = "ends_at"
        case status
        case createdAt = "created_at"
    }
}

struct Trade: Identifiable, Codable, Equatable {
    let tradeId: UUID
    let assetId: UUID
    let sellerId: UUID?
    let buyerId: UUID?
    let price: Double
    let currency: String
    let royaltyPaid: Double
    let platformFee: Double
    let txHash: String?
    let settledAt: Date

    var id: UUID { tradeId }

    enum CodingKeys: String, CodingKey {
        case tradeId = "trade_id"
        case assetId = "asset_id"
        case sellerId = "seller_id"
        case buyerId = "buyer_id"
        case price, currency
        case royaltyPaid = "royalty_paid"
        case platformFee = "platform_fee"
        case txHash = "tx_hash"
        case settledAt = "settled_at"
    }
}

struct ProvenanceRecord: Identifiable, Codable, Equatable {
    let recordId: UUID
    let assetId: UUID
    let eventType: String
    let actorId: UUID?
    let prevHash: String?
    let recordHash: String
    let createdAt: Date

    var id: UUID { recordId }

    enum CodingKeys: String, CodingKey {
        case recordId = "record_id"
        case assetId = "asset_id"
        case eventType = "event_type"
        case actorId = "actor_id"
        case prevHash = "prev_hash"
        case recordHash = "record_hash"
        case createdAt = "created_at"
    }
}

struct PortfolioSnapshot: Identifiable, Codable, Equatable {
    let userId: UUID
    let day: String
    let totalValue: Double
    let holdingsCount: Int
    let currency: String

    var id: String { "\(userId.uuidString)-\(day)" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case day
        case totalValue = "total_value"
        case holdingsCount = "holdings_count"
        case currency
    }

    var dayDate: Date? {
        PortfolioSnapshot.dayFormatter.date(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

// MARK: - Repository

@MainActor
final class MarketplaceRepository {
    static let shared = MarketplaceRepository()

    private let client = SupabaseManager.shared.client

    private init() {}

    // MARK: Listings

    func activeListing(for assetId: UUID) async throws -> AssetListing? {
        let rows: [AssetListing] = try await client
            .from("asset_listings")
            .select("*")
            .eq("asset_id", value: assetId)
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func listForSale(assetId: UUID, price: Double) async throws -> AssetListing {
        try await insertListing(assetId: assetId, kind: "fixed", price: price, endsAt: nil)
    }

    /// Auction with a starting price and optional end time (defaults to 24h).
    func listAuction(assetId: UUID, startingPrice: Double, endsAt: Date? = nil) async throws -> AssetListing {
        let end = endsAt ?? Date().addingTimeInterval(24 * 3600)
        return try await insertListing(assetId: assetId, kind: "auction", price: startingPrice, endsAt: end)
    }

    private func insertListing(assetId: UUID, kind: String, price: Double, endsAt: Date?) async throws -> AssetListing {
        let session = try await client.auth.session
        let sellerId = session.user.id

        var listingPayload: [String: AnyEncodable] = [
            "asset_id": AnyEncodable(assetId),
            "seller_id": AnyEncodable(sellerId),
            "kind": AnyEncodable(kind),
            "price": AnyEncodable(price),
            "currency": AnyEncodable("USDC"),
            "status": AnyEncodable("active")
        ]
        if let endsAt {
            listingPayload["ends_at"] = AnyEncodable(endsAt)
        }

        let inserted: [AssetListing] = try await client
            .from("asset_listings")
            .insert(listingPayload)
            .select("*")
            .execute()
            .value

        guard let listing = inserted.first else {
            throw MarketplaceError.unexpectedResponse
        }

        let assetUpdate: [String: AnyEncodable] = [
            "is_for_sale": AnyEncodable(true),
            "current_value": AnyEncodable(price)
        ]
        try await client
            .from("digital_assets")
            .update(assetUpdate, returning: .minimal)
            .eq("asset_id", value: assetId)
            .execute()

        return listing
    }

    struct AssetBid: Identifiable, Codable, Equatable {
        let bidId: UUID
        let listingId: UUID?
        let assetId: UUID
        let bidderId: UUID
        let amount: Double
        let currency: String
        let status: String
        let createdAt: Date

        var id: UUID { bidId }

        enum CodingKeys: String, CodingKey {
            case bidId = "bid_id"
            case listingId = "listing_id"
            case assetId = "asset_id"
            case bidderId = "bidder_id"
            case amount, currency, status
            case createdAt = "created_at"
        }
    }

    func bids(for listingId: UUID) async throws -> [AssetBid] {
        try await client
            .from("bids")
            .select("*")
            .eq("listing_id", value: listingId)
            .order("amount", ascending: false)
            .limit(40)
            .execute()
            .value
    }

    func placeBid(listingId: UUID, amount: Double) async throws -> UUID {
        struct Params: Encodable {
            let p_listing: String
            let p_amount: Double
        }
        do {
            let bidId: UUID = try await client
                .rpc("place_bid", params: Params(
                    p_listing: listingId.uuidString.lowercased(),
                    p_amount: amount))
                .execute()
                .value
            return bidId
        } catch {
            // Fallback when §5.21 RPC isn't applied yet — direct insert (no outbid cascade).
            if EngagementStore.isMissingSchema(error) {
                return try await placeBidDirect(listingId: listingId, amount: amount)
            }
            throw error
        }
    }

    private func placeBidDirect(listingId: UUID, amount: Double) async throws -> UUID {
        guard let listing = try await activeListingById(listingId) else {
            throw MarketplaceError.unexpectedResponse
        }
        let session = try await client.auth.session
        struct Ins: Encodable {
            let listing_id: UUID
            let asset_id: UUID
            let bidder_id: UUID
            let amount: Double
            let currency: String
            let status: String
        }
        let rows: [AssetBid] = try await client
            .from("bids")
            .insert(Ins(listing_id: listingId, asset_id: listing.assetId,
                        bidder_id: session.user.id, amount: amount,
                        currency: listing.currency, status: "active"))
            .select("*")
            .execute()
            .value
        guard let bid = rows.first else { throw MarketplaceError.unexpectedResponse }
        return bid.bidId
    }

    private func activeListingById(_ id: UUID) async throws -> AssetListing? {
        let rows: [AssetListing] = try await client
            .from("asset_listings")
            .select("*")
            .eq("listing_id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func settleAuction(listingId: UUID) async throws -> UUID? {
        let tradeId: UUID? = try await client
            .rpc("settle_auction", params: ["p_listing": listingId.uuidString])
            .execute()
            .value
        return tradeId
    }

    func cancelListing(listingId: UUID, assetId: UUID) async throws {
        try await client
            .from("asset_listings")
            .update(["status": "cancelled"], returning: .minimal)
            .eq("listing_id", value: listingId)
            .execute()

        let remaining: [AssetListing] = try await client
            .from("asset_listings")
            .select("listing_id")
            .eq("asset_id", value: assetId)
            .eq("status", value: "active")
            .execute()
            .value

        if remaining.isEmpty {
            try await client
                .from("digital_assets")
                .update(["is_for_sale": false], returning: .minimal)
                .eq("asset_id", value: assetId)
                .execute()
        }
    }

    func buyListing(listingId: UUID) async throws -> UUID {
        let tradeId: UUID = try await client
            .rpc("buy_listing", params: ["p_listing": listingId.uuidString])
            .execute()
            .value
        return tradeId
    }

    // MARK: History

    func trades(for assetId: UUID) async throws -> [Trade] {
        try await client
            .from("trades")
            .select("*")
            .eq("asset_id", value: assetId)
            .order("settled_at", ascending: false)
            .execute()
            .value
    }

    func provenance(for assetId: UUID) async throws -> [ProvenanceRecord] {
        try await client
            .from("provenance_records")
            .select("*")
            .eq("asset_id", value: assetId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    // MARK: Portfolio

    func portfolioSnapshots(for userId: UUID, limit: Int = 90) async throws -> [PortfolioSnapshot] {
        try await client
            .from("portfolio_snapshots")
            .select("*")
            .eq("user_id", value: userId)
            .order("day", ascending: true)
            .limit(limit)
            .execute()
            .value
    }

    func recordPortfolioSnapshot(userId: UUID, total: Double, holdings: Int) async throws {
        let day = Self.todayUTC
        let row = SnapshotUpsert(
            user_id: userId,
            day: day,
            total_value: total,
            holdings_count: holdings,
            currency: "USDC"
        )
        try await client
            .from("portfolio_snapshots")
            .upsert(row, onConflict: "user_id,day")
            .execute()
    }

    private static let todayUTC: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }()

    private struct SnapshotUpsert: Encodable {
        let user_id: UUID
        let day: String
        let total_value: Double
        let holdings_count: Int
        let currency: String
    }
}

enum MarketplaceError: LocalizedError {
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse: return "Unexpected response from marketplace."
        }
    }
}
