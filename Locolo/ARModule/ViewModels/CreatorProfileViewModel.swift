//
//  CreatorProfileViewModel.swift
//  Locolo
//
//  Backs a public creator profile (WS4): the creator's identity, their
//  placed AR assets, follower/following counts, and the follow relationship
//  with the signed-in user. Follows/unfollows optimistically.
//

import Foundation
import Supabase

/// Where one of the creator's assets sits in the world, for the profile map.
struct AssetPlacementPin: Identifiable {
    let id: UUID
    let name: String?
    let latitude: Double
    let longitude: Double
}

private struct AssetPinRow: Decodable {
    struct LocationEmbed: Decodable {
        let latitude: Double?
        let longitude: Double?
    }
    let asset_id: UUID
    let name: String?
    let locations: LocationEmbed?

    var pin: AssetPlacementPin? {
        guard let lat = locations?.latitude, let lon = locations?.longitude else { return nil }
        return AssetPlacementPin(id: asset_id, name: name, latitude: lat, longitude: lon)
    }
}

@MainActor
final class CreatorProfileViewModel: ObservableObject {
    let userId: UUID

    @Published var user: User?
    @Published var assets: [DigitalAsset] = []
    @Published var pins: [AssetPlacementPin] = []
    @Published var followers = 0
    @Published var following = 0
    @Published var isFollowing = false
    @Published var isSelf = false
    @Published var isLoading = false
    @Published var isMutatingFollow = false
    @Published var errorMessage: String?

    private let client = SupabaseManager.shared.client
    private let follows = FollowRepository()

    private var meId: UUID? {
        SupabaseManager.shared.currentUserId.flatMap(UUID.init)
    }

    /// A compact creator view built from the loaded user, for chips/lists.
    var creator: ARCreator? {
        guard let user else { return nil }
        return ARCreator(id: user.id, username: user.username, name: user.name,
                         avatarUrl: user.avatarUrl, verifiedFlags: user.verifiedFlags)
    }

    var canFollow: Bool { !isSelf && meId != nil }

    init(userId: UUID) {
        self.userId = userId
    }

    func load() async {
        isLoading = user == nil
        errorMessage = nil
        isSelf = (meId == userId)

        do {
            async let userRow: [User] = client
                .from("users")
                .select(User.publicColumns)
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value

            async let assetRows: [DigitalAsset] = client
                .from("digital_assets")
                .select("*")
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value

            async let countPair = follows.counts(for: userId)

            user = try await userRow.first
            assets = try await assetRows
            let c = try await countPair
            followers = c.followers
            following = c.following

            if let me = meId, !isSelf {
                isFollowing = (try? await follows.isFollowing(userId, from: me)) ?? false
            }

            // Map is a nice-to-have: a failure here shouldn't fail the profile.
            let pinRows: [AssetPinRow]? = try? await client
                .from("digital_assets")
                .select("asset_id, name, locations(latitude, longitude)")
                .eq("user_id", value: userId)
                .execute()
                .value
            pins = pinRows?.compactMap(\.pin) ?? []
        } catch {
            errorMessage = "Couldn't load this profile."
            print("CreatorProfile load failed:", error.localizedDescription)
        }

        isLoading = false
    }

    /// Optimistic follow/unfollow with rollback on failure.
    func toggleFollow() async {
        guard let me = meId, !isSelf, !isMutatingFollow else { return }
        isMutatingFollow = true
        defer { isMutatingFollow = false }

        let wasFollowing = isFollowing
        // Optimistic UI
        isFollowing.toggle()
        followers += wasFollowing ? -1 : 1
        ARHaptics.tick()

        do {
            if wasFollowing {
                try await follows.unfollow(userId, from: me)
            } else {
                try await follows.follow(userId, from: me)
            }
        } catch {
            // Roll back
            isFollowing = wasFollowing
            followers += wasFollowing ? 1 : -1
            errorMessage = "Couldn't update follow. Try again."
            print("toggleFollow failed:", error.localizedDescription)
        }
    }
}
