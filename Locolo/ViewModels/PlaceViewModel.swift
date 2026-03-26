//
//  PlaceViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 18/9/2025.
//

import MapKit
import Foundation

@MainActor
class PlaceViewModel: ObservableObject {
    
    @Published var places: [Place] = []
    @Published var postedPlaces: [PostPlace] = []
    @Published var placesResult: [PlaceResult] = []
    @Published var selectedPlace: Place?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var placesById: [UUID: Place] = [:]
    @Published var uploadedMediaUrl: String?
    
    private let repository: PlacesRepositoryProtocol
    private let storageManager = ObjStorageManager.shared
    
    init(repository: PlacesRepositoryProtocol = PlacesRepository()) {
        self.repository = repository
    }
    
    // MARK: - Fetch All Places
    /// Loads all places for a given loop and updates local state.
    /// Discussion: Used mainly by CreatePostFlow and Discover screens.
    func fetchPlaces(forLoop loopID: UUID) {
        isLoading = true
        errorMessage = nil
        repository.getPlaces(forLoop: loopID) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let fetchedPlaces):
                    self?.places = fetchedPlaces
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    
    
    // MARK: - Upload Media
    /// Uploads a place image or related media file to object storage.
    /// Discussion: Handles compression and returns the uploaded file URL.
    func uploadMedia(
        fileData: Data,
        fileName: String,
        contentType: String,
        storeIn: String
    ) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let filePath = "\(storeIn)/\(UUID().uuidString)_\(fileName)"
            
            let currentUrl = try await storageManager.uploadFile(
                path: filePath,
                fileData: fileData,
                contentType: contentType
            )
            
            await MainActor.run {
                self.uploadedMediaUrl = currentUrl
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                print(" Error uploading media: \(error)")
            }
        }
    }
    
    
    
    // MARK: - Get Place by ID
    /// Returns a single place, using cache if available.
    /// Discussion: Commonly used in CreatePostViewModel and detail views.
    func getPlace(by id: UUID) async -> Place? {
        if let cached = placesById[id] {
            return cached
        }
        do {
            let place = try await repository.getPlace(by: id)
            if let place = place {
                placesById[id] = place
            }
            return place
        } catch {
            print("Error fetching place:", error)
            return nil
        }
    }
    
    
    
    // MARK: - Add New Place
    /// Adds a newly created place to the backend and local state.
    /// Discussion: Triggered when a user confirms a new location not found in search.
    func addPlace(_ place: PostPlace) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            try await repository.addPlace(place)
            postedPlaces.append(place)
            print(" Added place to local state:", place.name)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    
    
    // MARK: - Delete Place
    /// Deletes a place from both backend and local cache.
    /// Discussion: Used in moderation or admin tools, not typical user flow.
    func deletePlace(by id: UUID) {
        isLoading = true
        errorMessage = nil
        repository.deletePlace(by: id) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success:
                    self?.places.removeAll { $0.id == id }
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    
    
    // MARK: - Search Place Flow
    /// Searches for places by name from both the database and Apple Maps.
    /// Discussion: Merges and deduplicates results for user selection.
    func searchPlaceFlow(
        query: String,
        userLat: Double?,
        userLon: Double?,
        radiusMeters: Double,
        loopID: UUID?,
        postedBy: UUID?
    ) async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        do {
            async let dbResults = repository.searchPlacesByName(query)
            
            async let appleResults: [MKMapItem] = {
                guard let lat = userLat, let lon = userLon else {
                    return []
                }
                
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    latitudinalMeters: radiusMeters,
                    longitudinalMeters: radiusMeters
                )
                
                let search = MKLocalSearch(request: request)
                let response = try? await search.start()
                return response?.mapItems ?? []
            }()
            
            let (localResults, appleMapItems) = try await (dbResults, appleResults)
            
            print("🔎 Searching for: \(query)")
            print("   userLat = \(String(describing: userLat)), userLon = \(String(describing: userLon))")
            print("   DB results: \(localResults.count)")
            print("   Apple results: \(appleMapItems.count)")
            
            var combinedResult: [PlaceResult] = []
            
            for place in localResults {
                combinedResult.append(
                    PlaceResult(
                        id: UUID(),
                        place: place,
                        location: nil,
                        source: .database
                    )
                )
            }
            
            for item in appleMapItems {
                let location = mapItemToLocation(item)
                let place = mapItemToPlace(item, loopID: loopID, postedBy: postedBy)
                combinedResult.append(
                    PlaceResult(
                        id: UUID(),
                        place: place,
                        location: location,
                        source: .appleMap
                    )
                )
            }
            
            await MainActor.run {
                self.placesResult = combinedResult
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    
    
    // MARK: - Map Item Converters
    /// Converts an MKMapItem to a `Location` object.
    func mapItemToLocation(_ item: MKMapItem) -> Location {
        Location(
            id: UUID(),
            name: item.name ?? "Unknown",
            address: item.placemark.title ?? "",
            city: item.placemark.locality,
            country: item.placemark.country,
            googlePlaceId: nil,
            geom: nil,
            similarityScore: nil,
            distMeters: nil,
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
    }
    
    
    
    /// Converts an MKMapItem to a `Place` with minimal default data.
    func mapItemToPlace(_ item: MKMapItem, loopID: UUID?, postedBy: UUID?) -> Place {
        let location = mapItemToLocation(item)
        
        return Place(
            id: UUID(),
            loopID: loopID,
            postedBy: postedBy,
            name: item.name ?? "Unknown",
            categoryId: nil,
            description: "",
            placeImageUrl: nil,
            trailerMediaUrl: nil,
            createdAt: Date(),
            locationId: location.id,
            verificationStatus: "pending",
            score: nil
        )
    }
    
    
}

struct PlaceResult: Identifiable {
    let id: UUID
    let place: Place?
    let location: Location?
    let source: DataSource
}

enum DataSource {
    case database
    case appleMap
}
