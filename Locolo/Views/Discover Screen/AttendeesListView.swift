//
//  AttendeesListView.swift
//  Locolo
//
//  Full attendee list sheet — segmented by Going / Interested with infinite scroll.
//  Presented as a sheet from EventDetailView and EventPostView.
//

import SwiftUI

// MARK: - AttendeesListView

struct AttendeesListView: View {
    let eventId: UUID
    let eventName: String

    @StateObject private var vm = AttendeesListViewModel()
    @State private var selectedTab: AttendanceStatus = .going
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Summary counts bar
                countsBar
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                // Going / Interested segmented picker
                Picker("Status", selection: $selectedTab) {
                    Text("Going").tag(AttendanceStatus.going)
                    Text("Interested").tag(AttendanceStatus.interested)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                // List
                if vm.isLoading && currentList.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if currentList.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(currentList) { attendee in
                            AttendeeRowView(attendee: attendee)
                                .listRowBackground(AppColors.cardBackground)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }

                        // Pagination trigger
                        if vm.hasMore(for: selectedTab) {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                            .onAppear {
                                Task { await vm.loadMore(for: selectedTab, eventId: eventId) }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .background(AppColors.screenBackground)
                }
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .navigationTitle("Who's going")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .task { await vm.loadInitial(eventId: eventId) }
        .onChange(of: selectedTab) { _ in
            // Already loaded both tabs on init — no extra fetch needed unless exhausted
        }
    }

    private var currentList: [AttendeePreview] {
        selectedTab == .going ? vm.goingList : vm.interestedList
    }

    // MARK: Counts bar

    private var countsBar: some View {
        HStack(spacing: 0) {
            countPill(
                count: vm.goingCount,
                label: "Going",
                colors: [.green, .teal],
                icon: "checkmark.circle.fill"
            )
            Spacer()
            countPill(
                count: vm.interestedCount,
                label: "Interested",
                colors: [.purple, .pink],
                icon: "heart.fill"
            )
        }
        .padding()
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
    }

    private func countPill(count: Int, label: String, colors: [Color], icon: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.primaryText)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(selectedTab == .going ? "👀" : "💭")
                .font(.system(size: 48))
            Text(selectedTab == .going ? "No one's marked going yet" : "No one's marked interested yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
            Text("Be the first one 🎉")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.secondaryText.opacity(0.7))
            Spacer()
        }
    }
}

// MARK: - AttendeeRowView

struct AttendeeRowView: View {
    let attendee: AttendeePreview

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            AsyncImage(url: attendee.avatarUrl.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    LinearGradient(
                        colors: [.purple, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Text(String(attendee.username.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    )
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))

            // Username
            Text("@\(attendee.username)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.primaryText)

            Spacer()

            // Status badge
            statusBadge
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: attendee.status == .going ? "checkmark.circle.fill" : "heart.fill")
                .font(.system(size: 11))
            Text(attendee.status == .going ? "Going" : "Interested")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Group {
                if attendee.status == .going {
                    LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                } else {
                    LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                }
            }
        )
        .clipShape(Capsule())
    }
}

// MARK: - AttendeesListViewModel

@MainActor
final class AttendeesListViewModel: ObservableObject {

    @Published var goingList:      [AttendeePreview] = []
    @Published var interestedList: [AttendeePreview] = []
    @Published var goingCount     = 0
    @Published var interestedCount = 0
    @Published var isLoading      = false

    private var goingPage       = 0
    private var interestedPage  = 0
    private var goingExhausted      = false
    private var interestedExhausted = false

    private let repo     = EventsDiscoverRepository()
    private let pageSize = 20

    // MARK: FUNCTION: loadInitial
    /// Parallel fetch of both tabs + counts so switching tabs feels instant.
    func loadInitial(eventId: UUID) async {
        isLoading = true
        async let goingResult      = repo.fetchAllAttendees(eventId: eventId, status: .going,      from: 0, limit: pageSize)
        async let interestedResult = repo.fetchAllAttendees(eventId: eventId, status: .interested, from: 0, limit: pageSize)
        async let countsResult     = repo.fetchAttendeeCounts(eventId: eventId)

        do {
            let (going, interested, counts) = try await (goingResult, interestedResult, countsResult)
            goingList       = going
            interestedList  = interested
            goingCount      = counts.going
            interestedCount = counts.interested
            goingPage       = 1
            interestedPage  = 1
            goingExhausted      = going.count      < pageSize
            interestedExhausted = interested.count < pageSize
        } catch {
            print("❌ [AttendeesListVM] Load failed: \(error)")
        }
        isLoading = false
    }

    // MARK: FUNCTION: loadMore
    /// Appends the next page when the user scrolls to the bottom.
    func loadMore(for status: AttendanceStatus, eventId: UUID) async {
        if status == .going {
            guard !goingExhausted else { return }
            do {
                let more = try await repo.fetchAllAttendees(
                    eventId: eventId, status: .going,
                    from: goingPage * pageSize, limit: pageSize
                )
                goingList.append(contentsOf: more)
                goingPage += 1
                goingExhausted = more.count < pageSize
            } catch { print("❌ \(error)") }
        } else {
            guard !interestedExhausted else { return }
            do {
                let more = try await repo.fetchAllAttendees(
                    eventId: eventId, status: .interested,
                    from: interestedPage * pageSize, limit: pageSize
                )
                interestedList.append(contentsOf: more)
                interestedPage += 1
                interestedExhausted = more.count < pageSize
            } catch { print("❌ \(error)") }
        }
    }

    func hasMore(for status: AttendanceStatus) -> Bool {
        status == .going ? !goingExhausted : !interestedExhausted
    }
}
