//
//  LocoloAnalytics.swift
//  Locolo
//
//  Thin Firebase Analytics + Crashlytics façade. No-ops gracefully if the
//  SPM products aren't linked yet.
//

import Foundation

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

enum LocoloAnalytics {
    static func configure() {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
    }

    static func log(_ name: String, params: [String: String] = [:]) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(name, parameters: params)
        #endif
        LocoloLog.debug(LocoloLog.general, "event \(name) \(params)")
    }

    static func record(error: Error, context: String? = nil) {
        #if canImport(FirebaseCrashlytics)
        if let context {
            Crashlytics.crashlytics().log(context)
        }
        Crashlytics.crashlytics().record(error: error)
        #endif
        LocoloLog.general.error("\(context ?? "error"): \(error.localizedDescription, privacy: .public)")
    }

    // Convenience AR/marketplace events
    static func mintSucceeded() { log("mint_succeeded") }
    static func buySettled() { log("buy_settled") }
    static func assetFound(rare: Bool) { log("asset_found", params: ["rare": rare ? "1" : "0"]) }
    static func listedForSale() { log("listed_for_sale") }
    static func storyPosted(video: Bool) { log("story_posted", params: ["video": video ? "1" : "0"]) }
}
