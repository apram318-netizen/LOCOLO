//
//  DiscoveryStore.swift
//  Locolo
//
//  Remembers which AR assets this user has physically walked up to in the
//  viewer ("found"), and when. Feeds the viewer's hot/cold finder (skip what
//  you've already found) and the Explorer Passport (discoveries, streaks).
//  Device-local by design: it's a game layer, not a source of truth.
//

import Foundation

@MainActor
final class DiscoveryStore: ObservableObject {
    static let shared = DiscoveryStore()

    @Published private(set) var found: [UUID: Date] = [:]

    private let defaultsKey = "ar_discoveries_v1"

    private init() {
        let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
        found = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UUID(uuidString: key).map { ($0, Date(timeIntervalSince1970: value)) }
        })
    }

    func hasFound(_ id: UUID) -> Bool { found[id] != nil }

    /// - Returns: true the first time an asset is found.
    @discardableResult
    func markFound(_ id: UUID, at date: Date = Date()) -> Bool {
        guard found[id] == nil else { return false }
        found[id] = date
        persist()
        ProgressStore.shared.noteDiscovery(id)
        return true
    }

    private func persist() {
        let raw = Dictionary(uniqueKeysWithValues: found.map { ($0.key.uuidString, $0.value.timeIntervalSince1970) })
        UserDefaults.standard.set(raw, forKey: defaultsKey)
    }
}
