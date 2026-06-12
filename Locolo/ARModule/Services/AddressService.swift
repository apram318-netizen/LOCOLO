//
//  AddressService.swift
//  Locolo
//
//  Resolves GPS coordinates to exact street addresses for AR asset posting.
//  CLGeocoder is the default (no API key needed); MKLocalSearch backs the
//  text search in AddressConfirmationView. GooglePlacesService can slot in
//  later once a real API key is configured in Secrets.
//

import Foundation
import CoreLocation
import MapKit

struct ResolvedAddress {
    let formatted: String
    let street: String?
    let city: String?
    let country: String?
}

final class AddressService {
    static let shared = AddressService()
    private let geocoder = CLGeocoder()

    // MARK: Reverse geocode to street level
    /// - Description: Converts a GPS location into an exact street address.
    /// Builds "12 Example St, Suburb, City, Country" from the placemark.
    func reverseGeocode(_ location: CLLocation) async throws -> ResolvedAddress {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let place = placemarks.first else {
            throw NSError(domain: "AddressService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No address found for this location."
            ])
        }

        let street = [place.subThoroughfare, place.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")

        let parts = [
            street.isEmpty ? nil : street,
            place.locality ?? place.subLocality,
            place.administrativeArea,
            place.country
        ].compactMap { $0 }

        return ResolvedAddress(
            formatted: parts.joined(separator: ", "),
            street: street.isEmpty ? nil : street,
            city: place.locality ?? place.subLocality,
            country: place.country
        )
    }

    // MARK: Search addresses by text
    /// - Description: Free-text address search via MKLocalSearch, biased
    /// around the user's location. No API key required.
    func searchAddresses(query: String, near location: CLLocation?) async -> [ResolvedAddress] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let loc = location {
            request.region = MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: 5_000,
                longitudinalMeters: 5_000
            )
        }

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        return response.mapItems.compactMap { item in
            let place = item.placemark
            let street = [place.subThoroughfare, place.thoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            let parts = [
                item.name,
                street.isEmpty ? nil : street,
                place.locality,
                place.country
            ].compactMap { $0 }

            guard !parts.isEmpty else { return nil }
            return ResolvedAddress(
                formatted: parts.joined(separator: ", "),
                street: street.isEmpty ? nil : street,
                city: place.locality,
                country: place.country
            )
        }
    }
}
