//
//  EventsDiscoverViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 30/10/2025.
//

import Foundation

@MainActor
class EventsDiscoverViewModel: ObservableObject {
    @Published var events: [EventItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let repository = EventsDiscoverRepository()
    
    
    // MARK: FUNCTION: loadActivities
    /// - Description: Fetches all events  from Supabase via repository
    /// start the debug from repository if needed 
    func loadEvents() async {
        isLoading = true
        errorMessage = nil
        
        do {
            events = try await repository.fetchEvents()
        } catch {
            errorMessage = "Failed to load events: \(error.localizedDescription)"
            print(" Error loading events: \(error)")
        }
        
        isLoading = false
    }
}


