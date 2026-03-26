//
//  GooglePlacesService.swift
//  Locolo
//
//  Created by Apramjot Singh on 22/9/2025.
//


// This whole file is not being used currently, may include it in future if apple maps seem less reliable

import Foundation

class GooglePlacesService {
    
    static let shared = GooglePlacesService()
    
    private let apiKey = "Not entering in yet, bacause I dont want to spend money// Can make it a bit advance search later but apple mapkit is fine for now"
    
    
    struct GooglePlace: Codable, Identifiable {
        let id: String
        let name: String
        let address: String
        let city: String?
        let country: String?
        let lat: Double
        let lon: Double
    }
    
    func searchPlaces(query: String) async throws -> [GooglePlace] {
        let urlString =
        "https://maps.googleapis.com/maps/api/place/textsearch/json?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&key=\(apiKey)"
        
        let (data, _) = try await URLSession.shared.data(from: URL(string: urlString)!)
        let decoded = try JSONDecoder().decode(GooglePlacesResponse.self, from: data)
        
        return decoded.results.map { result in
            let (city, country) = Self.parseAddress(result.formatted_address)
            return GooglePlace(
                id: result.place_id,
                name: result.name,
                address: result.formatted_address,
                city: city,
                country: country,
                lat: result.geometry.location.lat,
                lon: result.geometry.location.lng
            )
        }
    }
    
    private static func parseAddress(_ address: String) -> (String?, String?) {
        let components = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !components.isEmpty else { return (nil, nil) }
        
        let country = components.last
        let city = components.dropLast().last
        return (city, country)
    }
}

// TODO(LOCOLO): Testing the comments |Status: Uncompleted
struct GooglePlacesResponse: Codable {
    
    struct Result: Codable {
        let place_id: String
        let name: String
        let formatted_address: String
        let geometry: Geometry
        
        struct Geometry: Codable {
            let location: Location
            struct Location: Codable {
                let lat: Double
                let lng: Double
            }
        }
    }
    
    let results: [Result]
}


enum keys {
    static var googleAPIKey: String { Secrets.googleMapsAPIKey }
}
