//
//  PlaceDetailViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 3/10/2025.
//

import Foundation

@MainActor
class PlaceDetailViewModel: ObservableObject {
    
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let repository: PostRepositoryProtocol
    
    init(repository: PostRepositoryProtocol = PostsRepository()) {
        self.repository = repository
    }
    
    // MARK: - Load Posts for Place
    /// Fetches all posts linked to a specific place.
    /// Discussion: Used in place detail screens to display the content created at that location.
    /// - Parameter placeId: The unique identifier of the place.
    func loadPosts(for placeId: UUID) async {
        isLoading = true
        do {
            let result = try await repository.fetchPosts(forPlaceId: placeId)
            self.posts = result
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to load posts"
            self.isLoading = false
            print("Error loading posts: \(error)")
        }
    }
    
    
}
