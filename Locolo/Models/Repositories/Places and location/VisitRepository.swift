import Foundation
import Supabase


/// So this is  the link between users and places. Keeps track of who’s been where.
/// Uses Supabase “visits” table under the hood.
final class VisitRepository {
    private let client = SupabaseManager.shared.client

    // MARK: FUNCTION: getVisit
    /// - Description: Checks if a user already has a visit record for a place.
    /// Returns the visit if found, or nil if they haven’t been there yet.
    func getVisit(userId: UUID, placeId: UUID) async throws -> Visit? {
        let visits: [Visit] = try await client
            .from("visits")
            .select()
            .eq("user_id", value: userId)
            .eq("place_id", value: placeId)
            .limit(1)
            .execute()
            .value
        return visits.first
    }
    

    // MARK: FUNCTION: createVisit
    /// - Description: Creates a new visit record for a user and place combo.
    /// Usually called when a user enters a location for the first time.
    func createVisit(userId: UUID, placeId: UUID) async {
        do {
            try await client
                .from("visits")
                .insert([
                    "user_id": userId.uuidString,
                    "place_id": placeId.uuidString,
                    "started_at": ISO8601DateFormatter().string(from: Date())
                ])
                .execute()
            print(" Created visit for \(placeId)")
        } catch {
            print(" Failed to create visit:", error)
        }
    }
    

    // MARK: FUNCTION: confirmVisit
    /// - Description: Marks an existing visit as confirmed — like “yes, this person was actually here”.
    /// Updates confirmation timestamp and sets the visit as verified.
    func confirmVisit(userId: UUID, placeId: UUID) async {
        do {
            try await client
                .from("visits")
                .update([
                    "visit_confirmed": AnyEncodable(true),
                    "confirmed_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
                ])
                .eq("user_id", value: userId)
                .eq("place_id", value: placeId)
                .execute()
            print(" Confirmed visit for \(placeId)")
        } catch {
            print(" Confirm visit failed:", error)
        }
    }
    
    

    // MARK: FUNCTION: resetVisit
    /// - Description: Deletes a user’s visit record for a place.
    /// Think of it as a full reset — wipes it from Supabase.
    func resetVisit(userId: UUID, placeId: UUID) async {
        do {
            try await client
                .from("visits")
                .delete()
                .eq("user_id", value: userId)
                .eq("place_id", value: placeId)
                .execute()
            print(" Reset visit for \(placeId)")
        } catch {
            print(" Reset visit failed:", error)
        }
    }
}
