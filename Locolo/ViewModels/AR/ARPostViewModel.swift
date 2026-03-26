//
//  ARPostViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//

//import Foundation
//import Supabase
//import RealityKit
//import CoreLocation
//
//@MainActor
//final class ARPostViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var selectedFile: URL?
//    @Published var uploadedFileURL: URL?
//    @Published var isUploading = false
//    @Published var isPlacing = false
//    @Published var error: String?
//
//    private let client = SupabaseManager.shared.client
//    private let locationManager = CLLocationManager()
//    @Published var currentLocation: CLLocation?
//
//    override init() {
//        super.init()
//        locationManager.delegate = self
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    // MARK: - Upload 3D Model
//    func uploadFile() async {
//        guard let fileURL = selectedFile else { return }
//        isUploading = true
//        defer { isUploading = false }
//
//        let fileName = UUID().uuidString + "-" + fileURL.lastPathComponent
//
//        do {
//            let data = try Data(contentsOf: fileURL)
//            let path = "uploads/\(fileName)"
//
//            try await client.storage.from("digital_assets").upload(
//                path: path,
//                file: data,
//                options: FileOptions(contentType: "model/usdz")
//            )
//
//            let publicURL = try client.storage.from("digital_assets").getPublicUrl(path)
//            uploadedFileURL = URL(string: publicURL)
//        } catch {
//            self.error = "Upload failed: \(error.localizedDescription)"
//            print(" Upload failed:", error)
//        }
//    }
//
//    // MARK: - Save placement metadata to DB
//    func savePlacement(modelURL: URL, transform: Transform) async {
//        guard let loc = currentLocation else {
//            error = "No GPS location available."
//            return
//        }
//
//        let rotation = simd_eulerAngles(transform.rotation)
//        let scale = transform.scale
//        let lat = loc.coordinate.latitude
//        let lon = loc.coordinate.longitude
//
//        do {
//            // 1. Create new location
//            let location = try await client.from("locations")
//                .insert([
//                    "name": "AR Placement",
//                    "geom": "SRID=4326;POINT(\(lon) \(lat))"
//                ])
//                .select("location_id")
//                .single()
//                .execute()
//                .value
//
//            // 2. Create linked digital asset
//            try await client.from("digital_assets").insert( [
//                "file_url": modelURL.absoluteString,
//                "location_id": location["location_id"]!,
//                "visibility": "public",
//                "rotation_x": rotation.x,
//                "rotation_y": rotation.y,
//                "rotation_z": rotation.z,
//                "scale_x": scale.x,
//                "scale_y": scale.y,
//                "scale_z": scale.z
//            ]).execute()
//
//            print(" Placement saved successfully!")
//        } catch {
//            self.error = error.localizedDescription
//            print(" Failed to save placement:", error)
//        }
//    }
//
//    // MARK: - CLLocationManager
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        currentLocation = locations.last
//    }
//}
