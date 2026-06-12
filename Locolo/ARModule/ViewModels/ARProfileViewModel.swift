//
//  ARProfileViewModel.swift
//  Locolo
//
//  Backs the AR dashboard profile: the user's own digital assets and the
//  assets they've explored (seen in an AR session). No posts/places here —
//  that stays in the main app profile.
//

import Foundation
import Supabase

@MainActor
final class ARProfileViewModel: ObservableObject {
    @Published var ownAssets: [DigitalAsset] = []
    @Published var exploredAssets: [DigitalAsset] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = SupabaseManager.shared.client

    /// Total views across the user's own assets, for the header stats.
    var totalViews: Int {
        ownAssets.reduce(0) { $0 + $1.viewCount }
    }

    // MARK: Load both sections
    func load(userId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let own: [DigitalAsset] = client
                .from("digital_assets")
                .select("*")
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            async let seen = SeenAssetsRepository.shared.fetchSeenAssets(userId: userId)

            ownAssets = try await own
            // Your own assets don't belong in "Explored"
            exploredAssets = try await seen.filter { $0.userId != userId }
        } catch {
            errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
    }
}
