//
//  LocoloLog.swift
//  Locolo
//
//  Thin os.Logger wrapper. Prefer this over print() for new code — never log
//  tokens, ciphertext, or precise user coordinates in release.
//

import Foundation
import os

enum LocoloLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.locolo"

    static let ar = Logger(subsystem: subsystem, category: "ar")
    static let social = Logger(subsystem: subsystem, category: "social")
    static let market = Logger(subsystem: subsystem, category: "market")
    static let chat = Logger(subsystem: subsystem, category: "chat")
    static let mint = Logger(subsystem: subsystem, category: "mint")
    static let general = Logger(subsystem: subsystem, category: "general")

    /// Debug-only convenience that strips in release builds.
    static func debug(_ logger: Logger = general, _ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }
}
