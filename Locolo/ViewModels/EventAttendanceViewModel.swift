//
//  EventAttendanceViewModel.swift
//  Locolo
//
//  Manages attendance state for a single event.
//  Follows the same optimistic-update pattern as HypeViewModel —
//  UI flips instantly, rolls back if the network call fails.
//

import Foundation

@MainActor
final class EventAttendanceViewModel: ObservableObject {

    @Published var myStatus: AttendanceStatus?
    @Published var goingCount: Int
    @Published var interestedCount: Int
    @Published var previews: [AttendeePreview] = []
    @Published var isLoading = false

    let eventId: UUID
    let currentUserId: UUID
    private let repo = EventsDiscoverRepository()

    init(eventId: UUID, currentUserId: UUID, goingCount: Int = 0, interestedCount: Int = 0) {
        self.eventId        = eventId
        self.currentUserId  = currentUserId
        self.goingCount     = goingCount
        self.interestedCount = interestedCount
    }

    // MARK: FUNCTION: load
    /// Parallel fetch: my status + counts + avatar previews. Safe to call on appear.
    func load() {
        Task {
            isLoading = true
            async let statusResult   = repo.fetchMyStatus(eventId: eventId, userId: currentUserId)
            async let countsResult   = repo.fetchAttendeeCounts(eventId: eventId)
            async let previewsResult = repo.fetchAttendees(eventId: eventId, limit: 5)

            do {
                let (status, counts, fetched) = try await (statusResult, countsResult, previewsResult)
                myStatus       = status
                goingCount     = counts.going
                interestedCount = counts.interested
                previews       = fetched
            } catch {
                print("❌ [Attendance] Load failed: \(error)")
            }
            isLoading = false
        }
    }

    // MARK: FUNCTION: toggle
    /// Optimistic update then sync. Reverts the full previous state on error.
    func toggle(_ status: AttendanceStatus) {
        let previousStatus      = myStatus
        let previousGoing       = goingCount
        let previousInterested  = interestedCount

        applyOptimistic(newStatus: myStatus == status ? nil : status)

        Task {
            do {
                let result = try await repo.toggleAttendance(
                    eventId: eventId,
                    userId: currentUserId,
                    newStatus: status,
                    currentStatus: previousStatus
                )
                myStatus = result
            } catch {
                // Roll back
                myStatus        = previousStatus
                goingCount      = previousGoing
                interestedCount = previousInterested
                print("❌ [Attendance] Toggle failed: \(error)")
            }
        }
    }

    // MARK: - Private

    private func applyOptimistic(newStatus: AttendanceStatus?) {
        if myStatus == .going      { goingCount     = max(0, goingCount - 1) }
        if myStatus == .interested { interestedCount = max(0, interestedCount - 1) }

        myStatus = newStatus

        if newStatus == .going      { goingCount     += 1 }
        if newStatus == .interested { interestedCount += 1 }
    }
}
