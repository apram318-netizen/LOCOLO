//
//  OverpassAPI.swift
//  Locolo
//
//  Created by Apramjot Singh on 6/11/2025.
//

import Foundation
import MapKit

final class OverpassAPI {
    
    static let shared = OverpassAPI()
    private init() {}
    
    
    // MARK: FUNCTION: fetchBoundary
    /// - Description: Fetches an OSM administrative boundary by name with optional coordinate. Used for regional loop creation mostly
    ///
    /// I am using this to fetch the boundary from the overpass API by constructing the boundary by querying first using, name radius coordinates,
    /// Then we also add a relation of the place and the radiys and the coordinates. generate the URL from the  string and query+ pathstart the data Task to get the data
    /// and then decode to the polygon from the data
    ///
    /// - Parameter name: Name of the place
    /// - Parameter coordinate: the Core location 2D coordinates of the selected map location
    /// - Returns : A polygon of MKOverlay
    func fetchBoundary(for name: String, near coordinate: CLLocationCoordinate2D? = nil, completion: @escaping (Result<MKOverlay, Error>) -> Void)  {
        // Build query with location hint if provided
        var query: String
        
        if let coord = coordinate {
            // Search within ~100km radius of the selected location
            let radius = 100000  // meters
            query = """
            [out:json][timeout:25];
            (
              relation["boundary"="administrative"]["name"="\(name)"](around:\(radius),\(coord.latitude),\(coord.longitude));
              relation["place"="city"]["name"="\(name)"](around:\(radius),\(coord.latitude),\(coord.longitude));
            );
            out geom;
            """
        } else {
            // Fallback to name-only search
            query = """
            [out:json][timeout:25];
            (
              relation["boundary"="administrative"]["name"="\(name)"];
            );
            out geom;
            """
        }
        
        // Encodes the query intoa valid query for the API
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://overpass-api.de/api/interpreter?data=\(encodedQuery)") else {
            completion(.failure(NSError(domain: "Overpass", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Invalid URL"
            ])))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "Overpass", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No data returned from Overpass API"
                ])))
                return
            }
            
            do {
                let polygon = try Self.decodePolygon(from: data)
                completion(.success(polygon))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    


    // MARK: FUNCTION: decodePolygon
    /// - Description: Takes raw Overpass API data and converts it into a polygon overlay we can display on the map.
    ///
    /// Basically, this goes through the JSON we get back from Overpass, figures out which “relation” or “geometry” looks
    /// like the main boundary, filters out the inner parts (holes), connects the lines if they’re split, and finally
    /// returns an `MKPolygon` that represents the full boundary.
    ///
    /// - Parameter data: The raw JSON data returned from the Overpass API request
    /// - Returns: An MKOverlay (usually an MKPolygon) that outlines the selected region
    ///
    /// Here’s what’s happening step by step:
    /// - We parse the JSON and grab all the elements”(these can be relations or geometries)
    /// - Then we look for the biggest one (most members = most detailed boundary)
    /// - Collect all the outer members (ignore “inner” holes)
    /// - Stitch any broken segments together (rings that share endpoints)
    /// - Close the polygon if it’s not perfectly connected
    /// - Finally, return an MKPolygon that we can draw on the map
    private static func decodePolygon(from data: Data) throws -> MKOverlay {
        // Parse the JSON from Overpass
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let elements = json["elements"] as? [[String: Any]]
        else {
            throw NSError(domain: "Overpass", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure"])
        }

        print(" Processing \(elements.count) elements from Overpass")

        // Find the “best” element — the one with the most members (most detailed boundary)
        var bestElement: [String: Any]?
        var maxMembers = 0
        
        for element in elements {
            if let members = element["members"] as? [[String: Any]] {
                if members.count > maxMembers {
                    maxMembers = members.count
                    bestElement = element
                }
            } else if let geom = element["geometry"] as? [[String: Double]], geom.count > maxMembers {
                maxMembers = geom.count
                bestElement = element
            }
        }
        
        guard let targetElement = bestElement else {
            throw NSError(domain: "Overpass", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "No valid geometry found"])
        }
        
        print(" Selected best element with \(maxMembers) members/points")

        // Collect all outer rings (ignore inner ones)
        var outerRings: [[CLLocationCoordinate2D]] = []
        
        // Direct geometry case: sometimes the whole boundary is just one big geometry array
        if let geom = targetElement["geometry"] as? [[String: Double]] {
            let coords = geom.compactMap { d -> CLLocationCoordinate2D? in
                guard let lat = d["lat"], let lon = d["lon"] else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            if coords.count >= 4 {
                outerRings.append(coords)
                print("   Direct geometry: \(coords.count) points")
            }
        }
        
        // Relation members case: a boundary can also be split into multiple “ways”
        if let members = targetElement["members"] as? [[String: Any]] {
            for member in members {
                let role = member["role"] as? String ?? "outer"
                
                // Only keep outer boundaries (skip holes)
                guard role == "outer" || role == "" else {
                    print("  Skipping '\(role)' member")
                    continue
                }
                
                if let geom = member["geometry"] as? [[String: Double]] {
                    let coords = geom.compactMap { d -> CLLocationCoordinate2D? in
                        guard let lat = d["lat"], let lon = d["lon"] else { return nil }
                        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    }
                    if coords.count >= 2 {
                        outerRings.append(coords)
                        print("  Outer ring: \(coords.count) points")
                    }
                }
            }
        }

        guard !outerRings.isEmpty else {
            throw NSError(domain: "Overpass", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "No outer rings found"])
        }

        print(" Total outer rings: \(outerRings.count)")

        // If there are multiple segments, try to merge them into one continuous boundary
        var mergedCoords = outerRings[0]
        
        if outerRings.count > 1 {
            print(" Attempting to merge \(outerRings.count) ways into single boundary...")
            var remainingRings = Array(outerRings[1...])
            var merged = true
            
            // Keep merging while we find connecting points
            while merged && !remainingRings.isEmpty {
                merged = false
                
                for (index, ring) in remainingRings.enumerated() {
                    let lastPoint = mergedCoords.last!
                    let firstPoint = ring.first!
                    let ringLastPoint = ring.last!
                    
                    // If the end of one ring connects to the start of another (within 100m), merge them
                    if distance(lastPoint, firstPoint) < 100 {
                        mergedCoords.append(contentsOf: ring)
                        remainingRings.remove(at: index)
                        merged = true
                        print("   Connected ring (forward)")
                        break
                    }
                    // Or if it connects in reverse order
                    else if distance(lastPoint, ringLastPoint) < 100 {
                        mergedCoords.append(contentsOf: ring.reversed())
                        remainingRings.remove(at: index)
                        merged = true
                        print("   Connected ring (reversed)")
                        break
                    }
                }
            }
            
            if !remainingRings.isEmpty {
                print(" Could not merge all rings. \(remainingRings.count) remain disconnected")
            }
        }

        // Make sure the polygon closes (first and last point should match)
        if let first = mergedCoords.first, let last = mergedCoords.last {
            if distance(first, last) > 10 { // If gap > 10m, close it manually
                mergedCoords.append(first)
                print(" Closed polygon by adding first point")
            }
        }
        
        print(" Final polygon: \(mergedCoords.count) points")
        return MKPolygon(coordinates: mergedCoords, count: mergedCoords.count)
    }
    
    
    
    // MARK: FUNCTION: distance
    /// - Description: Quick helper to calculate distance between two map coordinates in meters.
    ///
    /// Just does a basic haversine formula to get the great-circle distance on Earth.
    /// Nothing fancy — used when connecting points while merging polygons.
    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6371000.0  // Earth radius in meters
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let hav = sin(dLat/2)*sin(dLat/2) + cos(lat1)*cos(lat2)*sin(dLon/2)*sin(dLon/2)
        return 2 * r * atan2(sqrt(hav), sqrt(1-hav))
    }



    // MARK: FUNCTION: fetchPolygon (by name)
    /// - Description: Async version of `fetchBoundary`. Wraps the completion-based call into Swift concurrency.
    /// Lets you just  await the polygon instead of using callbacks.
    func fetchPolygon(for name: String, near coordinate: CLLocationCoordinate2D? = nil) async throws -> MKOverlay? {
        try await withCheckedThrowingContinuation { continuation in
            fetchBoundary(for: name, near: coordinate) { result in
                switch result {
                case .success(let overlay):
                    continuation.resume(returning: overlay)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }



    // MARK: FUNCTION: fetchPolygon (by coordinate)
    /// - Description: Fetches the administrative boundary around a coordinate within a radius.
    /// Basically builds an Overpass query using the “around” filter and decodes it into an overlay.
    func fetchPolygon(around coordinate: CLLocationCoordinate2D, radiusMeters: Int = 50000) async throws -> MKOverlay? {
        let query = """
        [out:json][timeout:25];
        (
          relation["boundary"="administrative"]["admin_level"~"4|5|6|7"](around:\(radiusMeters),\(coordinate.latitude),\(coordinate.longitude));
        );
        out geom;
        """
        return try await executeOverlayQuery(query)
    }



    // MARK: FUNCTION: fetchUniversityPolygon (by name)
    /// - Description: Same idea as `fetchPolygon`, but specifically for university areas.
    /// It tries both “relation” and “way” tags and uses radius search first, then a fallback by name.
    func fetchUniversityPolygon(for name: String, near coordinate: CLLocationCoordinate2D? = nil) async throws -> MKOverlay? {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        var queries: [String] = []
        if let coord = coordinate {
            let radius = 20000
            queries.append("""
            [out:json][timeout:25];
            (
              relation["amenity"="university"]["name"="\(escapedName)"](around:\(radius),\(coord.latitude),\(coord.longitude));
              way["amenity"="university"]["name"="\(escapedName)"](around:\(radius),\(coord.latitude),\(coord.longitude));
            );
            out geom;
            """)
        }
        queries.append("""
        [out:json][timeout:25];
        (
          relation["amenity"="university"]["name"="\(escapedName)"];
          way["amenity"="university"]["name"="\(escapedName)"];
        );
        out geom;
        """)
        for query in queries {
            if let overlay = try await executeOverlayQuery(query) {
                return overlay
            }
        }
        return nil
    }



    // MARK: FUNCTION: fetchUniversityPolygon (by coordinate)
    /// - Description: Grabs the closest university-tagged boundary around a point.
    /// Just builds an Overpass query with a radius and returns whatever polygon it finds.
    func fetchUniversityPolygon(around coordinate: CLLocationCoordinate2D, radiusMeters: Int = 5000) async throws -> MKOverlay? {
        let query = """
        [out:json][timeout:25];
        (
          relation["amenity"="university"](around:\(radiusMeters),\(coordinate.latitude),\(coordinate.longitude));
          way["amenity"="university"](around:\(radiusMeters),\(coordinate.latitude),\(coordinate.longitude));
        );
        out geom;
        """
        return try await executeOverlayQuery(query)
    }
    


    // MARK: FUNCTION: executeOverlayQuery
    /// - Description: Sends any Overpass query string to the API, downloads the data,
    /// and passes it through `decodePolygon`.
    /// Returns nil if anything fails. Basically the shared helper all fetch functions use.
    private func executeOverlayQuery(_ query: String) async throws -> MKOverlay? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://overpass-api.de/api/interpreter?data=\(encoded)") else {
            return nil
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        do {
            return try Self.decodePolygon(from: data)
        } catch {
            print(" Overpass query failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    

    // MARK: FUNCTION: createDebugRectangle
    /// - Description: Just makes a simple rectangle polygon around a coordinate.
    /// Used for quick visualization when no real boundary data is found.
    static func createDebugRectangle(center: CLLocationCoordinate2D, radiusKm: Double = 20) -> MKPolygon {
        // Convert radius in km to degrees
        let latDelta = radiusKm / 111.0
        let lonDelta = radiusKm / (111.0 * cos(center.latitude * .pi / 180))
        
        var coords = [
            CLLocationCoordinate2D(latitude: center.latitude - latDelta, longitude: center.longitude - lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude + latDelta, longitude: center.longitude - lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude + latDelta, longitude: center.longitude + lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude - latDelta, longitude: center.longitude + lonDelta),
            CLLocationCoordinate2D(latitude: center.latitude - latDelta, longitude: center.longitude - lonDelta)
        ]
        
        return MKPolygon(coordinates: &coords, count: coords.count)
    }



    // MARK: FUNCTION: createCircle
    /// - Description: Builds a circular polygon around a point.
    /// If you give it too few segments, it just falls back to the rectangle version.
    /// Useful for radius visualizations like “X km around this point”.
    static func createCircle(center: CLLocationCoordinate2D, radiusMeters: Double = 300, segments: Int = 48) -> MKPolygon {
        guard segments >= 3 else { return createDebugRectangle(center: center, radiusKm: radiusMeters / 1000.0) }
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(center.latitude * .pi / 180)
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(segments + 1)
        for i in 0..<segments {
            let angle = Double(i) / Double(segments) * 2.0 * .pi
            let dx = cos(angle) * radiusMeters
            let dy = sin(angle) * radiusMeters
            let lat = center.latitude + (dy / metersPerDegreeLat)
            let lon = center.longitude + (dx / metersPerDegreeLon)
            coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        coords.append(coords.first ?? center)
        return MKPolygon(coordinates: coords, count: coords.count)
    }


}


// Learning Resources here:
// https://youtu.be/M_1Sas9l57o?si=EZt7AT1VgDf-PS0u
// https://wiki.openstreetmap.org/wiki/Overpass_API

//OSM element types (node, way, relation, admin boundaries)
//https://wiki.openstreetmap.org/wiki/Elements
//
//Boundary relations (exactly what your code fetches)
//https://wiki.openstreetmap.org/wiki/Relation:boundary
//
//Using around: in Overpass queries
//https://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL#By_location


// https://overpass-turbo.eu THis tool helped me a lot lot in visualising evrything and all the polygon's. Helped me cross check and debug a lot.


// Mk kit overlays:
// https://developer.apple.com/documentation/mapkit/mkoverlay

//MKPolygon
// https://developer.apple.com/documentation/mapkit/mkpolygon

// Creating overlays from coordinates

//Apple sample:
//https://developer.apple.com/documentation/mapkit/adding_overlays_and_annotations

// After all my research I was ready to impleement the over pass api but it was still very confusing and Ineeded a few more things

// The haversine formula: thoery got a bit too much out of my proceccing power here but the following resource is actually very helpful.
// https://www.movable-type.co.uk/scripts/latlong.html
