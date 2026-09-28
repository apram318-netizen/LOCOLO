//
//  MarketplaceMath.swift
//  Locolo
//
//  Pure fee / ownership helpers — unit-testable without Supabase.
//  Mirrors Phase A buy_listing economics (7.5% royalty / 2.5% platform).
//

import Foundation

enum MarketplaceMath {
    static let royaltyRate = 0.075
    static let platformFeeRate = 0.025

    struct Settlement: Equatable {
        let price: Double
        let royalty: Double
        let platformFee: Double
        var sellerNet: Double { price - royalty - platformFee }
    }

    static func settle(price: Double) -> Settlement {
        let p = max(0, price)
        let royalty = (p * royaltyRate * 100).rounded() / 100
        let fee = (p * platformFeeRate * 100).rounded() / 100
        return Settlement(price: p, royalty: royalty, platformFee: fee)
    }

    /// Bid must strictly beat the current high (auction rule).
    static func isValidBid(_ amount: Double, currentHigh: Double) -> Bool {
        amount > currentHigh && amount > 0 && amount.isFinite
    }
}

extension DigitalAsset {
    /// Current economic owner — falls back to creator when RPC hasn't returned owner_id yet.
    var effectiveOwnerId: UUID { ownerId ?? userId }

    /// Heuristic "rare" find for AR flourish (listed or priced holdings).
    var isRareFind: Bool {
        (isForSale == true) || ((currentValue ?? 0) > 0)
    }
}
