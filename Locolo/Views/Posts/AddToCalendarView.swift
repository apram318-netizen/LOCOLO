//
//  AddToCalendarView.swift
//  Locolo
//
//  Created for adding events to calendar (Google Calendar integration)
//

import SwiftUI
import EventKit
import EventKitUI

struct AddToCalendarView: View {
    let event: Event
    let post: Post
    
    @Environment(\.dismiss) private var dismiss
    @State private var eventStore = EKEventStore()
    @State private var calendarAccessGranted = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var showingEventEdit = false
    @State private var ekEvent: EKEvent?
    @State private var isLoading = false
    @State private var successMessage = ""
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header with event info
                eventHeader
                    .padding(.top)
                
                Divider()
                
                // Action buttons
                VStack(spacing: 16) {
                    // Add to iOS Calendar button
                    Button(action: {
                        requestCalendarAccessAndAdd()
                    }) {
                        HStack {
                            Image(systemName: "calendar")
                                .font(.title2)
                            Text("Add to iOS Calendar")
                                .font(.headline)
                            Spacer()
                            if isLoading {
                                ProgressView()
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.blueCyanMutedGradient)
                        .cornerRadius(12)
                    }
                    .disabled(isLoading)
                    
                    // Add to Google Calendar button (opens in browser)
                    if let googleCalendarUrl = googleCalendarURL {
                        Link(destination: googleCalendarUrl) {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.title2)
                                Text("Add to Google Calendar")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Color.red, Color.blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
                
                if !successMessage.isEmpty {
                    Text(successMessage)
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .padding()
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Add to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Calendar Access Required", isPresented: $showingPermissionAlert) {
                Button("Settings", role: .none) {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(permissionAlertMessage)
            }
            .sheet(isPresented: $showingEventEdit) {
                if let ekEvent = ekEvent {
                    EventEditView(eventStore: eventStore, event: ekEvent)
                }
            }
            .onAppear {
                checkCalendarAccess()
            }
        }
    }
    
    // MARK: - Event Header
    private var eventHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.name)
                .font(.title2.bold())
                .foregroundColor(AppColors.primaryText)
            
            if let startAt = event.startAt {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text(formatDate(startAt))
                        .font(.subheadline)
                }
                
                if let endAt = event.endAt {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.blue)
                        Text("\(formatTime(startAt)) - \(formatTime(endAt))")
                            .font(.subheadline)
                    }
                } else {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.blue)
                        Text(formatTime(startAt))
                            .font(.subheadline)
                    }
                }
            }
            
            if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
    
    // MARK: - Google Calendar URL
    private var googleCalendarURL: URL? {
        guard let startAt = event.startAt else { return nil }
        
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")
        var queryItems: [URLQueryItem] = []
        
        queryItems.append(URLQueryItem(name: "action", value: "TEMPLATE"))
        queryItems.append(URLQueryItem(name: "text", value: event.name))
        
        if let description = event.description {
            queryItems.append(URLQueryItem(name: "details", value: description))
        }
        
        // Format dates for Google Calendar (YYYYMMDDTHHMMSSZ)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let startDateString = dateFormatter.string(from: startAt)
        
        if let endAt = event.endAt {
            let endDateString = dateFormatter.string(from: endAt)
            queryItems.append(URLQueryItem(name: "dates", value: "\(startDateString)/\(endDateString)"))
        } else {
            // Default to 1 hour duration if no end time
            if let endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startAt) {
                let endDateString = dateFormatter.string(from: endDate)
                queryItems.append(URLQueryItem(name: "dates", value: "\(startDateString)/\(endDateString)"))
            } else {
                queryItems.append(URLQueryItem(name: "dates", value: startDateString))
            }
        }
        
        components?.queryItems = queryItems
        return components?.url
    }
    
    // MARK: - Calendar Access
    private func checkCalendarAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarAccessGranted = status == .authorized
    }
    
    private func requestCalendarAccessAndAdd() {
        isLoading = true
        errorMessage = ""
        successMessage = ""
        
        eventStore.requestAccess(to: .event) { granted, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = "Failed to access calendar: \(error.localizedDescription)"
                    return
                }
                
                if granted {
                    calendarAccessGranted = true
                    addEventToCalendar()
                } else {
                    permissionAlertMessage = "Please enable calendar access in Settings to add events to your calendar."
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func addEventToCalendar() {
        let newEvent = EKEvent(eventStore: eventStore)
        newEvent.title = event.name
        newEvent.notes = event.description
        
        if let startAt = event.startAt {
            newEvent.startDate = startAt
            newEvent.endDate = event.endAt ?? Calendar.current.date(byAdding: .hour, value: 1, to: startAt) ?? startAt
        } else {
            errorMessage = "Event does not have a start date"
            return
        }
        
        newEvent.calendar = eventStore.defaultCalendarForNewEvents
        
        // Set location if available
        if event.locationMode == "online", let url = event.onlineUrl {
            newEvent.location = url
            newEvent.url = URL(string: url)
        } else if let placeId = event.placeID {
            // Could fetch place details here if needed
            newEvent.location = "Event Location"
        }
        
        // Set alarms/reminders
        let alarm = EKAlarm(relativeOffset: -3600) // 1 hour before
        newEvent.addAlarm(alarm)
        
        // Save event
        do {
            try eventStore.save(newEvent, span: .thisEvent, commit: true)
            successMessage = "Event added to calendar successfully!"
            
            // Dismiss after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } catch {
            errorMessage = "Failed to save event: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Date Formatting
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Event Edit View Wrapper
struct EventEditView: UIViewControllerRepresentable {
    let eventStore: EKEventStore
    let event: EKEvent
    
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, EKEventEditViewDelegate {
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
        }
    }
}

