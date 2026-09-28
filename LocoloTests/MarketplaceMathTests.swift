//
//  MarketplaceMathTests.swift
//  LocoloTests
//
//  Pure unit tests for marketplace fee math + prefs gating.
//  Target `LocoloTests` is wired in Locolo.xcodeproj (stage 18).
//

import XCTest
@testable import Locolo

final class MarketplaceMathTests: XCTestCase {
    func testSettleSplitsMatchPhaseARates() {
        let s = MarketplaceMath.settle(price: 100)
        XCTAssertEqual(s.royalty, 7.5, accuracy: 0.001)
        XCTAssertEqual(s.platformFee, 2.5, accuracy: 0.001)
        XCTAssertEqual(s.sellerNet, 90, accuracy: 0.001)
    }

    func testSettleZeroPrice() {
        let s = MarketplaceMath.settle(price: 0)
        XCTAssertEqual(s.royalty, 0)
        XCTAssertEqual(s.platformFee, 0)
        XCTAssertEqual(s.sellerNet, 0)
    }

    func testBidMustBeatHigh() {
        XCTAssertTrue(MarketplaceMath.isValidBid(11, currentHigh: 10))
        XCTAssertFalse(MarketplaceMath.isValidBid(10, currentHigh: 10))
        XCTAssertFalse(MarketplaceMath.isValidBid(-1, currentHigh: 0))
    }
}

final class NotificationPrefsV2Tests: XCTestCase {
    func testV2TypesMapToPrefs() {
        var prefs = NotificationPrefs()
        prefs.reactions = false
        prefs.sales = false
        prefs.quests = true
        XCTAssertFalse(prefs.allows(type: "reaction"))
        XCTAssertFalse(prefs.allows(type: "sale"))
        XCTAssertTrue(prefs.allows(type: "quest_complete"))
        XCTAssertTrue(prefs.allows(type: "remix")) // under reposts
    }
}
