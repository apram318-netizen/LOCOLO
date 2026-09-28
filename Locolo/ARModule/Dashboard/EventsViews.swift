//
//  EventsViews.swift
//  Locolo
//
//  AR events list + create sheet.
//

import SwiftUI
import CoreLocation

struct EventsListView: View {
    @ObservedObject private var store = EventsStore.shared
    @EnvironmentObject private var dashboardState: ARDashboardState
    @State private var showCreate = false

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()
            if !store.available && store.hasLoaded {
                ARInlineEmptyState(
                    icon: "calendar",
                    title: "Events coming soon",
                    subtitle: "Meetups and drop nights will show up here once they're live."
                )
            } else if store.upcoming.isEmpty && store.hasLoaded {
                ARInlineEmptyState(
                    icon: "calendar.badge.plus",
                    title: "No meetups yet",
                    subtitle: "Host a drop night — pick a place and time.",
                    actionTitle: "Host event",
                    action: { showCreate = true }
                )
            } else {
                List(store.upcoming) { event in
                    EventRow(event: event) {
                        Task { try? await store.rsvp(eventId: event.id, status: "going") }
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await store.refresh() }
            }
        }
        .navigationTitle("AR Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .disabled(!store.available && store.hasLoaded)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateEventSheet { showCreate = false }
                .presentationDetents([.medium, .large])
        }
        .task { await store.refresh() }
    }
}

private struct EventRow: View {
    let event: AREvent
    let onGoing: () -> Void
    @ObservedObject private var creators = CreatorCache.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title).font(.headline)
            if let detail = event.detail, !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
            }
            HStack {
                Label(event.placeName ?? "Pinned place", systemImage: "mappin.and.ellipse")
                Spacer()
                Text(event.startsAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption)
            .foregroundColor(.secondary)

            HStack {
                Text("Hosted by \(creators.creator(event.hostId)?.displayName ?? "Creator")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(event.rsvpCount) going")
                    .font(.caption.weight(.semibold))
                Button(event.myStatus == "going" ? "You're going" : "I'm going") {
                    ARHaptics.tick()
                    onGoing()
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(event.myStatus == "going")
            }
        }
        .padding(.vertical, 6)
    }
}

struct CreateEventSheet: View {
    var onCreated: () -> Void
    @ObservedObject private var store = EventsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var startsAt = Date().addingTimeInterval(86400)
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Details", text: $detail, axis: .vertical).lineLimit(2...4)
                DatePicker("Starts", selection: $startsAt, in: Date()...)
                if let error { Text(error).foregroundColor(.red).font(.caption) }
            }
            .navigationTitle("Host event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func create() async {
        saving = true; defer { saving = false }
        let coord = LocationManager.shared.userLocation
            ?? LocationManager.shared.latestStoredLocation
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        do {
            _ = try await store.create(
                title: title, detail: detail,
                lat: coord.latitude, lon: coord.longitude,
                placeName: nil, startsAt: startsAt)
            ARHaptics.success()
            onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
