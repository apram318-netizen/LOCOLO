
import SwiftUI

struct EventDetailView: View {
    let event: EventItem

    @StateObject private var attendanceVM: EventAttendanceViewModel
    @State private var showAttendeesSheet = false

    init(event: EventItem) {
        self.event = event
        let userId = SupabaseManager.shared.currentUserId.flatMap(UUID.init) ?? UUID()
        _attendanceVM = StateObject(wrappedValue: EventAttendanceViewModel(
            eventId: event.id,
            currentUserId: userId,
            goingCount: event.attendees
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // MARK: Hero image
                AsyncImage(url: URL(string: event.image)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.1, blue: 0.35), Color(red: 0.4, green: 0.1, blue: 0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
                .frame(height: 240)
                .clipped()

                // MARK: Content card
                VStack(alignment: .leading, spacing: 16) {

                    // Title
                    Text(event.name)
                        .font(.title.bold())
                        .foregroundStyle(AppColors.primaryText)

                    // Category badge
                    Text(event.category)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.categoryBadge)
                        .clipShape(Capsule())

                    // Date / time
                    Label("\(event.date) · \(event.time)", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.secondaryText)

                    // Location
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.secondaryText)

                    Divider()

                    // MARK: Live attendee counts
                    HStack(spacing: 20) {
                        liveCountChip(
                            count: attendanceVM.goingCount,
                            label: "going",
                            icon: "checkmark.circle.fill",
                            colors: [.green, .teal]
                        )
                        liveCountChip(
                            count: attendanceVM.interestedCount,
                            label: "interested",
                            icon: "heart.fill",
                            colors: [.purple, .pink]
                        )

                        Spacer()

                        // See all attendees
                        Button {
                            showAttendeesSheet = true
                        } label: {
                            Text("See all →")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.purple)
                        }
                    }

                    // MARK: Attendance CTA
                    AttendanceCTAView(
                        vm: attendanceVM,
                        style: .card,
                        onSeeAll: { showAttendeesSheet = true }
                    )

                    Divider()

                    // Description
                    Text(event.description)
                        .font(.body)
                        .foregroundStyle(AppColors.primaryText)

                    Divider()

                    // External ticket / event link
                    Button {
                        if let url = URL(string: event.ticketUrl) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Get Tickets", systemImage: "ticket.fill")
                            .font(.headline.bold())
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: AppColors.cardShadow, radius: 5, x: 0, y: 2)
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { attendanceVM.load() }
        .sheet(isPresented: $showAttendeesSheet) {
            AttendeesListView(eventId: event.id, eventName: event.name)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Live count chip

    private func liveCountChip(count: Int, label: String, icon: String, colors: [Color]) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                )
            Text("\(count) \(label)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.primaryText)
        }
    }
}
