//
//  ARGalleryViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 2/11/2025.
//


import SwiftUI
import Foundation

// MARK: - ViewModel

// applying search and category filters, and exposing data to the SwiftUI view layer.
@MainActor
final class ARGalleryViewModel: ObservableObject {
    // MARK: - Published State
    @Published var artworks: [DigitalAsset] = []      // all fetched assets
    @Published var searchQuery: String = ""           // search filter text
    @Published var selectedCategory: String = "all"   // active category filter
    @Published var isLoading: Bool = false            // loading state
    @Published var errorMessage: String?              // holds user-facing error messages

    private let repo = DigitalAssetRepository()

    // MARK: - Computed Property: filteredArtworks
    /// - Description: Returns artworks filtered by search query and category.
    /// - Parameter [DigitalAsset]: The list that includes almost all that are being displayed
    /// - Logic:
    ///   - Matches items if their description or category contains the search text.
    ///   - If a category other than all is selected, only shows matching ones.
    var filteredArtworks: [DigitalAsset] {
        artworks.filter { art in
            let matchesSearch =
                searchQuery.isEmpty ||
                (art.description ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                (art.category ?? "").localizedCaseInsensitiveContains(searchQuery)
            
            let matchesCategory =
                selectedCategory == "all" ||
                (art.category?.lowercased() == selectedCategory.lowercased())

            return matchesSearch && matchesCategory
        }
    }

    
    // MARK: - FUNCTION: loadArtworks
    /// - Description: Fetches all digital assets from the repository and updates the view state.
    /// Called when the gallery view appears or on pull-to-refresh.
    ///
    /// - Throws: Sets an error message if fetching fails.
    func loadArtworks() async {
        isLoading = true
        do {
            artworks = await repo.fetchAll()
            for art in artworks.prefix(3) {
                print("asset:", art.id, "thumb:", art.thumbUrl ?? "nil", "file:", art.fileUrl)
                
                if let thumb = art.thumbUrl, let url = URL(string: thumb) {
                    print("-----thumb exists?", FileManager.default.fileExists(atPath: url.path))
                    let data = try? Data(contentsOf: url)
                    print("---thumb bytes:", data?.count ?? 0)
                    if let data, UIImage(data: data) == nil {
                        print("-----thumb data isn't a decodable image")
                    }
                }
            }
            
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load artworks: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    
}
