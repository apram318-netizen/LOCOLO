//
//  ActivitiesDiscoverViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 30/10/2025.
//

import Foundation

@MainActor
class ActivitiesDiscoverViewModel: ObservableObject {
    @Published var activities: [ActivityItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let repository = ActivitiesDiscoverRepository()
    
    
    // MARK: FUNCTION: loadActivities
    /// - Description: Fetches all activities for from Supabase.
    func loadActivities() async {
        isLoading = true
        errorMessage = nil
        
        do {
            activities = try await repository.fetchActivities()
        } catch {
            errorMessage = "Failed to load activities: \(error.localizedDescription)"
            print(" Error loading activities: \(error)")
        }
        
        isLoading = false
    }
    
    
    // Split activities into sections (for backwards compatibility with existing UI)
    var nycActivities: [ActivityItem] {
        Array(activities.prefix(3))
    }
    
    
    // MARK: FUNCTION: loadActivities
    /// - Description: Fetches all popular activities for from Supabase.
    var popularActivities: [ActivityItem] {
        Array(activities.dropFirst(3).prefix(3))
    }
    
}


