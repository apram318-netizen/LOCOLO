//
//  LoopViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//


//How this Works for now :
//Queries Overpass API with name/coordinate filters
//Parses JSON response
//Selects the most detailed boundary (most points)
//Collects outer rings (ignores inner holes)
//Merges disconnected segments (within 100m)
//Closes polygon if needed
//Returns MKPolygon for map display


//Geofencing Flow Summary
//LocationManager continuously tracks location (10m distance filter)
//On update, LocationUploader uploads ping to Firestore
//LocationUploader checks for nearby places
//If places found, VisitMonitor performs visit check:
//Creates visit entry if new
//Tracks time spent is less than 10 mins that means  waiting, and if 10 min - 1 hour we confirm , > 1 hour = reset) It'[s like this for testing for now. to test multiple times so I reset after an houer

//For loop creation, OverpassAPI fetches real geographic boundaries
//Loop boundaries are stored as GeoJSON in Supabase for overlap detection
//Key Geofence Parameters
//Place visit radius: 150 meters
//Visit confirmation time: 10 minutes (600 seconds)
//Location update distance filter: 10 meters
//Significant location change: ~500 meters (iOS default

// References:
// https://datatracker.ietf.org/doc/html/rfc7946#section-3.1.6
// https://datatracker.ietf.org/doc/html/rfc7946#section-3.1.7
// https://en.wikipedia.org/wiki/Point_in_polygon // Not very useful but was good for knowledge
// https://postgis.net/docs/ST_Intersects.html // Highly depended on this for detection
// https://postgis.net/docs/ST_GeomFromGeoJSON.html // This too



import Foundation
import MapKit

enum LoopCreationType: String, CaseIterable, Identifiable {
    case university = "University Loop"
    case regional = "Regional Loop"
    var id: String { rawValue }
}

class LoopViewModel: ObservableObject {
    @Published var userLoops: [Loop] = []
    @Published var allLoops: [Loop] = []
    @Published var recentLoops: [Loop] = []
    @Published var searchQuery: String = ""
    @Published var expanded: Bool = false
    @Published var  activeLoop: Loop? {
        didSet {
            // Save to UserDefaults immediately when active loop changes
            if let loopId = activeLoop?.id {
                UserDefaults.standard.set(loopId, forKey: "selectedLoopId")
                print(" Active loop saved to UserDefaults:", loopId)
            }
            refreshActiveLoopTag(for: activeLoop)
        }
    }
    
    @Published var selectedPolygon: MKPolygon?
    @Published var loopBoundaryPolygon: MKOverlay?
    
    @Published var activeUserTag: String?
    
    // loop creation state
    @Published var creatingNewLoop: Bool = false
    @Published var selectedCreationType: LoopCreationType?
    @Published var locationSearchQuery: String = ""
    @Published var locationResults: [MKMapItem] = []
    @Published var selectedLocation: MKMapItem?
    @Published var mapRegion: MKCoordinateRegion = .init(
        center: CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @Published var newLoopName: String = ""
    @Published var newLoopDescription: String = ""
    @Published var isSavingLoop: Bool = false
    @Published var creationErrorMessage: String?
    
    @Published var newLoopCoverImage: UIImage?
    
    
    private let repository: LoopRepositoryProtocol
    private var mapSearch: MKLocalSearch?

    init(repository: LoopRepositoryProtocol = LoopsRepository()) {
        self.repository = repository
        loadLoops()
    }
    
    
    // MARK: - Load Loops
    /// Loads all loops linked to the current user and marks the active one.
    /// Called at initialization and after a new loop is created.
    func loadLoops() {
        repository.fetchUserLoops { [weak self] result in
            switch result {
            case .success(let loops):

                DispatchQueue.main.async {
                    guard let self = self else { return }

                    self.userLoops = loops

                    // no loops available
                    guard !loops.isEmpty else { return }

                    // Read saved loopId from UserDefaults
                    let savedId = UserDefaults.standard.string(forKey: "selectedLoopId")

                    if let savedId,
                       let savedLoop = loops.first(where: { $0.id == savedId }) {

                        //  Use previously selected loop as active
                        self.activeLoop = savedLoop

                        //  Update recents:
                        // Move saved loop to the start
                        var recents = loops
                        
                        // Remove it from wherever it is
                        if let idx = recents.firstIndex(where: { $0.id == savedId }) {
                            let selected = recents.remove(at: idx)
                            recents.insert(selected, at: 0)
                        }

                        // Keep only max 5
                        self.recentLoops = Array(recents.prefix(5))

                    } else {
                        //  No saved loop present → choose the first one
                        let first = loops[0]
                        // Setting activeLoop will automatically save to UserDefaults via didSet
                        self.activeLoop = first

                        // Default recents = first 5 loops
                        self.recentLoops = Array(loops.prefix(5))
                    }

                    // Fetch the user's tag for the now-active loop
                    self.refreshActiveLoopTag(for: self.activeLoop)
                }

            case .failure(let error):
                print("Error fetching loops:", error)
            }
        }
    }

    
    
    
    // MARK: - Loop Search
    /// Searches for loops matching the query from Supabase.
    /// Called whenever a user enters text in the loop search bar.
    func searchLoops(_ query: String) {
        guard !query.isEmpty else {
            allLoops = []
            return
        }
        // basic text search from Supabase
        repository.searchLoops(query: query) { [weak self] result in
            switch result {
            case .success(let loops):
                DispatchQueue.main.async { self?.allLoops = loops }
            case .failure(let error):
                print("Search error: \(error)")
            }
        }
    }
    
    
    
    // MARK: - Location Search (for Loop Creation)
    /// Searches for locations on Apple Maps when the user types into the search bar.
    /// Helps during the loop creation process.
    func searchLocations() {
        // use Apple Maps search when user types a place name
        guard !locationSearchQuery.isEmpty else {
            locationResults = []
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = locationSearchQuery
        mapSearch = MKLocalSearch(request: request)
        mapSearch?.start { [weak self] response, _ in
            DispatchQueue.main.async {
                self?.locationResults = response?.mapItems ?? []
            }
        }
    }
    
    

    func setActiveLoop(_ loop: Loop) {
        // mark the selected loop as active
        for i in userLoops.indices {
            userLoops[i].isActive = (userLoops[i].id == loop.id)
        }

        // Setting activeLoop will automatically save to UserDefaults via didSet
        activeLoop = loop
    }
    
    // MARK: - Select Location
    /// Sets the selected location, updates map region, and fills loop name if empty.
    /// Discussion: Adjusts map zoom level to give better visual context.
    func selectLocation(_ place: MKMapItem) {
        // save the chosen location and update map
        selectedLocation = place
        if let displayName = place.name, newLoopName.isEmpty {
            newLoopName = displayName // auto fill loop name if empty
        }
        if let coordinate = place.placemark.location?.coordinate {
            // zoom in a bit for context
            mapRegion = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }
    
    
    
    // MARK: - Loop Expansion and Selection
    /// Expands or collapses the loops list in the UI.
    func toggleExpanded() { expanded.toggle() }
    

    
    
    /// Joins a loop and marks it as a member + active loop.
    func joinLoop(_ loop: Loop) {
        // mark membership locally and activate it
        if let index = userLoops.firstIndex(where: { $0.id == loop.id }) {
            userLoops[index].isMember = true
            setActiveLoop(loop)
        }
    }
    
    
}

extension LoopViewModel {
    
    
    
    // MARK: - Fetch Loop Boundary
    /// Fetches a geographic boundary for the given loop name using Overpass API.
    /// Discussion: Falls back to simpler shapes (circle or rectangle) if polygon data isn’t available.
    @MainActor
    func fetchLoopBoundary(for name: String) async {
        // tries to fetch the actual map boundary for the loop (Overpass first, then fallback)
        let coordinate = selectedLocation?.placemark.location?.coordinate
        var overlay: MKOverlay?
        let loopType = selectedCreationType == .university ? "university" : "regional"
        if loopType == "university" {
            // first try full university polygon
            do {
                overlay = try await OverpassAPI.shared.fetchUniversityPolygon(for: name, near: coordinate)
            } catch {
                print(" University boundary fetch failed: \(error.localizedDescription)")
            }
            // fallback by coordinate
            if overlay == nil, let coordinate = coordinate {
                do {
                    overlay = try await OverpassAPI.shared.fetchUniversityPolygon(around: coordinate)
                } catch {
                    print(" University coordinate fetch failed: \(error.localizedDescription)")
                }
            }
            // fallback to a small circle if all else fails
            if overlay == nil, let coordinate = coordinate {
                overlay = OverpassAPI.createCircle(center: coordinate, radiusMeters: 300)
            }
        } else {
            // same idea but for regional loops
            do {
                overlay = try await OverpassAPI.shared.fetchPolygon(for: name, near: coordinate)
            } catch {
                print(" Overpass name fetch failed: \(error.localizedDescription)")
            }
            // fallback by coordinate search
            if overlay == nil, let coordinate = coordinate {
                do {
                    overlay = try await OverpassAPI.shared.fetchPolygon(around: coordinate, radiusMeters: 40000)
                } catch {
                    print(" Overpass coordinate fetch failed: \(error.localizedDescription)")
                }
            }
            // fallback rectangle for safety
            if overlay == nil, let coordinate = coordinate {
                overlay = OverpassAPI.createDebugRectangle(center: coordinate, radiusKm: 25)
            }
        }
        guard let overlay else {
            creationErrorMessage = "Unable to fetch boundary for \(name)."
            return
        }
        // update map overlay if successful
        creationErrorMessage = nil
        loopBoundaryPolygon = overlay
        selectedPolygon = overlay as? MKPolygon
        mapRegion = MKCoordinateRegion(overlay.boundingMapRect)
    }
    
    
    
    
    // MARK: - Submit Loop Creation
    /// Handles the final step of loop creation — validates input, checks overlap,
    /// and inserts a new loop into Supabase.
    /// Discussion: Checks for duplicate university loops and prevents overlaps.
    @MainActor
    func submitLoopCreation() async {
        // validates everything and pushes new loop to backend
        guard let overlay = loopBoundaryPolygon else {
            creationErrorMessage = "Select a region first."
            return
        }
        guard let targetLocation = selectedLocation,
              let coordinate = targetLocation.placemark.location?.coordinate else {
            creationErrorMessage = "Missing loop location."
            return
        }
        
        let trimmedName = newLoopName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            creationErrorMessage = "Give your loop a name."
            return
        }
        
        guard let geoJSON = Self.geoJSONGeometry(from: overlay) else {
            creationErrorMessage = "Unable to serialise loop boundary."
            return
        }
        
        let loopType = (selectedCreationType == .university) ? "university" : "regional"
        creationErrorMessage = nil
        isSavingLoop = true
        
        do {
            // check duplicates or overlaps depending on loop type
            if loopType == "university" {
                let hasDuplicate = try await repository.hasUniversityDuplicate(center: coordinate, name: trimmedName)
                if hasDuplicate {
                    creationErrorMessage = "This university already has a loop at this location."
                    isSavingLoop = false
                    return
                }
            } else {
                let conflicts = try await repository.checkLoopOverlap(center: coordinate, boundary: geoJSON)
                if let conflict = conflicts.first {
                    creationErrorMessage = "Overlaps with '\(conflict.name)'. Try a different area."
                    isSavingLoop = false
                    return
                }
            }
            
            var coverUrl: String? = nil
            if let image = newLoopCoverImage {
                do {
                    coverUrl = try await repository.uploadLoopCoverImage(image)
                } catch {
                    creationErrorMessage = "Failed to upload cover: \(error.localizedDescription)"
                    print("Cover upload failed: \(error)")
                }
            }
            
            // prepare final payload and create the loop
            let payload = CreateLoopPayload(
                name: trimmedName,
                description: newLoopDescription.isEmpty ? nil : newLoopDescription,
                coverImageUrl: coverUrl,
                locationName: targetLocation.placemark.title ?? trimmedName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                memberCount: 1,
                isMember: true,
                isActive: true,
                loopType: loopType,
                boundary: nil,
                boundaryRaw: geoJSON
            )
            
            try await repository.createLoop(payload: payload)
            loadLoops() // reload after save
            resetCreationState()
            creatingNewLoop = false
        } catch {
            creationErrorMessage = error.localizedDescription
            print(" Loop creation failed: \(error)")
        }
        
        isSavingLoop = false
    }
    
    
    
    // MARK: - Reset Creation State
    /// Clears all temporary state after loop creation or cancellation.
    func resetCreationState() {
        // resets everything back to initial
        newLoopName = ""
        newLoopDescription = ""
        selectedLocation = nil
        selectedPolygon = nil
        loopBoundaryPolygon = nil
        creationErrorMessage = nil
    }
    
    
    
    
    // MARK: - GeoJSON Helpers
    /// Converts an MKPolygon into GeoJSON format for backend storage.
    private static func geoJSONGeometry(from polygon: MKPolygon) -> GeoJSONGeometry? {
        // converts MKPolygon into GeoJSON format
        var rings: [[[Double]]] = []
        
        let outer = linearRing(from: polygon)
        guard outer.count >= 4 else { return nil }
        rings.append(outer)
        
        if let holes = polygon.interiorPolygons {
            for hole in holes {
                let ring = linearRing(from: hole)
                if ring.count >= 4 {
                    rings.append(ring)
                }
            }
        }
        
        return GeoJSONGeometry(polygonRings: rings)
    }
    
    
    
    /// Converts polygon points into coordinate pairs formatted for GeoJSON.
    private static func linearRing(from polygon: MKPolygon) -> [[Double]] {
        // takes polygon points and converts to [lon, lat] pairs
        var ring: [[Double]] = []
        let pointCount = polygon.pointCount
        guard pointCount > 0 else { return ring }
        
        let points = polygon.points()
        for index in 0..<pointCount {
            let coord = points[index].coordinate
            ring.append([coord.longitude, coord.latitude])
        }
        
        // make sure it closes properly
        if let first = ring.first {
            if let last = ring.last, !coordinatesEqual(first, last) {
                ring.append(first)
            }
        }
        
        return ring
    }
    
    
    
    
    /// Compares two coordinates to see if they’re identical within tolerance.
    private static func coordinatesEqual(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        // used for checking if first and last coordinate are same
        guard lhs.count == 2, rhs.count == 2 else { return false }
        let epsilon = 1e-8
        return abs(lhs[0] - rhs[0]) < epsilon && abs(lhs[1] - rhs[1]) < epsilon
    }
    
    
    
    
    /// Converts overlays into a single GeoJSON geometry object.
    private static func geoJSONGeometry(from overlay: MKOverlay) -> GeoJSONGeometry? {
        // handles multi and single polygons properly
        if let polygon = overlay as? MKPolygon {
            let rings = buildPolygonRings(from: polygon)
            guard !rings.isEmpty else { return nil }
            return GeoJSONGeometry(polygonRings: rings)
        }
        
        if let multi = overlay as? MKMultiPolygon {
            var polygons: [[[[Double]]]] = []
            for poly in multi.polygons {
                let rings = buildPolygonRings(from: poly)
                if !rings.isEmpty { polygons.append(rings) }
            }
            guard !polygons.isEmpty else { return nil }
            return GeoJSONGeometry(polygons: polygons)
        }
        
        return nil
    }
    
    
    
    
    /// Builds the list of polygon rings (outer and inner) for a GeoJSON object.
    private static func buildPolygonRings(from polygon: MKPolygon) -> [[[Double]]] {
        // rebuilds all polygon rings (outer + holes)
        var rings: [[[Double]]] = []
        let outer = linearRing(from: polygon)
        if outer.count >= 4 {
            rings.append(outer)
        }
        if let holes = polygon.interiorPolygons {
            for hole in holes {
                let ring = linearRing(from: hole)
                if ring.count >= 4 {
                    rings.append(ring)
                }
            }
        }
        return rings
    }
    
    
    
    /// JUst fetches from the loop counter table and sets the tag  the current user
    private func refreshActiveLoopTag(for loop: Loop?) {
        activeUserTag = nil

        guard
            let loopIdString = loop?.id,
            let loopUUID = UUID(uuidString: loopIdString),
            let userIdString = SupabaseManager.shared.currentUserId,
            let userUUID = UUID(uuidString: userIdString)
        else { return }

        Task {
            do {
                let tag = try await repository.fetchLoopTag(userId: userUUID, loopId: loopUUID)
                await MainActor.run { self.activeUserTag = tag }
            } catch {
                print("Failed to fetch loop tag:", error)
            }
        }
    }

    
//    // MARK: - Currently unused functions
    
//    /// Fetches a polygon boundary from Overpass or Nominatim APIs.
//    private static func fetchPolygon(for name: String) async throws -> MKPolygon? {
//        // generic fetch function for fallback Overpass/Nominatim polygon
//        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
//        
//        let overpassQuery = """
//        [out:json][timeout:25];
//        (
//          relation["boundary"="administrative"]["name"="\(escaped)"];
//          relation["type"="boundary"]["name"="\(escaped)"];
//          relation["admin_level"]["name"="\(escaped)"];
//          area[name="\(escaped)"];
//        );
//        out geom;
//        """
//        
//        let overpassURLString = "https://overpass-api.de/api/interpreter?data=\(overpassQuery)"
//        guard let overpassURL = URL(string: overpassURLString) else { return nil }
//        
//        do {
//            let (data, _) = try await URLSession.shared.data(from: overpassURL)
//            if let polygon = try decodePolygon(from: data) {
//                return polygon
//            }
//        } catch {
//            print(" Overpass failed: \(error.localizedDescription). Falling back to Nominatim…")
//        }
//        
//        // fallback to Nominatim if Overpass fails
//        let nominatimURL = URL(string: "https://nominatim.openstreetmap.org/search?city=\(escaped)&format=json&polygon_geojson=1")!
//        let (nData, _) = try await URLSession.shared.data(from: nominatimURL)
//        return try decodePolygonFromNominatim(data: nData)
//    }
    

//    /// Decodes unordered Overpass API data into an MKPolygon usable by MapKit.
//    private static func decodePolygon(from data: Data) throws -> MKPolygon? {
//        // quick decoder for messy Overpass data (spiderweb style)
//        guard
//            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
//            let elements = json["elements"] as? [[String: Any]]
//        else { return nil }
//        
//        var allCoords: [CLLocationCoordinate2D] = []
//        for element in elements {
//            if let geom = element["geometry"] as? [[String: Double]] {
//                for dict in geom {
//                    if let lat = dict["lat"], let lon = dict["lon"] {
//                        allCoords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
//                    }
//                }
//            } else if let members = element["members"] as? [[String: Any]] {
//                for member in members {
//                    if let geom = member["geometry"] as? [[String: Double]] {
//                        for dict in geom {
//                            if let lat = dict["lat"], let lon = dict["lon"] {
//                                allCoords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
//                            }
//                        }
//                    }
//                }
//            }
//        }
//        
//        guard allCoords.count > 3 else { return nil }
//        return MKPolygon(coordinates: allCoords, count: allCoords.count)
//    }
//    

//    /// Parses Nominatim JSON data into an MKPolygon for map rendering.
//    private static func decodePolygonFromNominatim(data: Data) throws -> MKPolygon? {
//        // handles json response from nominatim fallback
//        guard
//            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
//            let first = json.first,
//            let geojson = first["geojson"] as? [String: Any]
//        else { return nil }
//        
//        if geojson["type"] as? String == "Polygon",
//           let coordSets = geojson["coordinates"] as? [[[Double]]] {
//            let coords = coordSets.first?.compactMap { pair -> CLLocationCoordinate2D? in
//                guard pair.count == 2 else { return nil }
//                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
//            } ?? []
//            if coords.count > 3 {
//                return MKPolygon(coordinates: coords, count: coords.count)
//            }
//        }
//        
//        if geojson["type"] as? String == "MultiPolygon",
//           let multiSets = geojson["coordinates"] as? [[[[Double]]]] {
//            var polygons: [MKPolygon] = []
//            for set in multiSets {
//                let coords = set.first?.compactMap { pair -> CLLocationCoordinate2D? in
//                    guard pair.count == 2 else { return nil }
//                    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
//                } ?? []
//                if coords.count > 3 {
//                    polygons.append(MKPolygon(coordinates: coords, count: coords.count))
//                }
//            }
//            if !polygons.isEmpty {
//                return polygons.first
//            }
//        }
//        
//        return nil
//    }
    
    
    
}





