//
//  ARCreateViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//

import Foundation
import SwiftUI
import Supabase
import CoreLocation
import RealityKit
import simd


// MARK: FILE: ARCreateViewModel
/// capturing transform + location, and saving it all as a digital asset.
/// Ties together Supabase uploads, local storage, ARKit data, and GPS tracking.
@MainActor
final class ARCreateViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Step { case file, animations, ar, details }

    // MARK: Published properties
    @Published var navDestination: String? = nil
    @Published var navPath: [String] = []
    @Published var step: Step = .file
    @Published var isBusy = false
    @Published var error: String?
    @Published var capturedTransform: Transform?
    @Published var showDetails = false
    @Published var isAssetSaved = false
    @Published var showSuccessAlert = false

    // MARK: File
    @Published var localFileURL: URL?        // user-picked model file (fbx/usdz)
    @Published var uploadedFileURL: URL?     // Supabase public URL after upload
    @Published var fileType: String = "usdz" // auto-inferred from file extension

    // MARK: AR capture
    @Published var transform: Transform?     // placement rotation/scale from AR
    @Published var location: CLLocation?     // current GPS location

    // MARK: Details
    @Published var name: String = ""
    @Published var descriptionText: String = ""
    @Published var visibility: String = "public"
    @Published var alsoMakePost: Bool = false

    // MARK: Exact address + altitude (captured at placement time)
    @Published var address: String = ""
    @Published var city: String?
    @Published var country: String?
    @Published var capturedAltitude: Double?
    @Published var altitudeAccuracy: Double?

    // MARK: Animations (embedded in the picked USDZ)
    @Published var availableAnimations: [String] = []
    @Published var selectedAnimationIndex: Int?
    var previewEntity: Entity?

    // MARK: Trigger (how the animation fires in the viewer's AR session)
    @Published var triggerType: TriggerType = .tap
    @Published var triggerDistance: Double = 10
    @Published var triggerPhrase: String = ""
    @Published var shakePattern: ShakePattern = .single

    private let client = SupabaseManager.shared.client
    private let storage = ObjStorageManager.shared
    private let locationManager = CLLocationManager()

    // MARK: Init
    /// - Description: Initializes the view model and starts location tracking immediately.
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // MARK: FUNCTION: setPickedFile
    /// - Description: Sets the local file and detects its type.
    /// - Parameter url: URL to the selected 3D model file (fbx/usdz)
    func setPickedFile(_ url: URL) {
        localFileURL = url
        fileType = url.pathExtension.lowercased()
    }
    
    
    

    // MARK: FUNCTION: secureFileData
    /// - Description: Accesses a user-selected file safely from the upload box, copying it to a random tempporary  folder.
    ///
    /// - Parameter url: URL of the original file
    /// - Returns: File data as `Data`
    /// - Throws: If the file cannot be copied or read
    private func secureFileData(from url: URL) throws -> Data {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
            return try Data(contentsOf: tempURL)
        } catch {
            throw NSError(domain: "FileAccess", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot read file: \(error.localizedDescription)"
            ])
        }
    }
    
    
    

    // MARK: FUNCTION: loadAnimations
    /// - Description: Loads the picked USDZ locally and enumerates the
    /// animations embedded in it, so the poster can pick which one plays.
    /// Runs on the local file — no need to wait for the cloud upload.
    func loadAnimations() async {
        guard let url = localFileURL else { return }

        do {
            let data = try secureFileData(from: url)
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".usdz")
            try data.write(to: temp)

            let entity = try await Entity(contentsOf: temp)
            previewEntity = entity
            availableAnimations = entity.availableAnimations.enumerated().map { index, animation in
                let name = animation.name ?? ""
                return name.isEmpty ? "Animation \(index + 1)" : name
            }
        } catch {
            print(" Failed to enumerate animations:", error.localizedDescription)
            previewEntity = nil
            availableAnimations = []
        }
        selectedAnimationIndex = nil
    }


    // MARK: FUNCTION: downloadToLocal
    /// - Description: Downloads a remote model file to local storage for preview or editing.
    /// - Parameter remoteURL: URL of the model on Supabase
    /// - Returns: Local temporary URL of the downloaded file
    func downloadToLocal(_ remoteURL: URL) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(remoteURL.lastPathComponent)
        try data.write(to: localURL)
        return localURL
    }
    

    // MARK: FUNCTION: uploadPickedFileToStorage
    /// - Description: Uploads the user-selected 3D model to Supabase Storage.
    /// Automatically sets the correct content type based on file extension.
    ///
    /// - Parameter bucket: The Supabase Storage bucket name (if not given I set it to digital assets by default)
    func uploadPickedFileToStorage(bucket: String = "digital_assets") async {
        guard let url = localFileURL else { return }
        isBusy = true; defer { isBusy = false }

        do {
            let data = try secureFileData(from: url)
            let contentType = (fileType == "usdz") ? "model/usdz" : "model/fbx"
            let fileName = UUID().uuidString + "-" + url.lastPathComponent
            let path = "DigitalArt/\(fileName)"

            print(" Uploading \(fileName) to bucket: \(bucket)")
            let publicURL = try await storage.uploadFile(
                bucket: bucket,
                path: path,
                fileData: data,
                contentType: contentType
            )
            uploadedFileURL = URL(string: publicURL)
            print(" Uploaded file available at: \(uploadedFileURL?.absoluteString ?? "nil")")
        } catch {
            self.error = "Upload failed: \(error.localizedDescription)"
            print(" Upload failed:", error)
        }
    }
    
    
    

    // MARK: FUNCTION: setPlacement
    /// - Description: Saves the AR transform, GPS location, altitude, and exact
    /// address after placement. Moves the flow to the Details step.
    /// - Parameter transform: The 3D transform captured in AR space
    func setPlacement(transform: Transform) {
        self.transform = transform
        location = location ?? locationManager.location

        // Altitude of the *poster* — stored so viewers anchor the asset at the
        // height it was placed, not at their own altitude.
        capturedAltitude = location?.altitude
        altitudeAccuracy = location?.verticalAccuracy

        // Resolve the exact street address in the background
        if let loc = location {
            Task { [weak self] in
                guard let self else { return }
                if let resolved = try? await AddressService.shared.reverseGeocode(loc) {
                    self.address = resolved.formatted
                    self.city = resolved.city
                    self.country = resolved.country
                }
            }
        }

        step = .details
        showDetails = true
    }
    
    
    

    // MARK: FUNCTION: saveAsset
    /// - Description: Saves the final asset by inserting both a new location and digital asset record in Supabase.
    /// Collects AR transform, GPS, and metadata to form a full record.
    ///
    /// - Parameter userId: The UUID of the logged-in user creating the asset
    func saveAsset(userId: UUID) async {
        print(" Starting digital asset upload (saveAsset)")

        guard let uploaded = uploadedFileURL else {
            error = "File has not been uploaded."
            print("  No uploaded file URL found.")
            return
        }
        guard let transformValue = transform else {
            error = "AR placement not confirmed."
            print("  No AR transform available.")
            return
        }

        let rotation = transformValue.rotation.toEulerAngles()
        let scale = transformValue.scale
        let coord = (location ?? locationManager.location)?.coordinate
        guard let lat = coord?.latitude, let lon = coord?.longitude else {
            error = "No GPS location available."
            print("  Missing GPS coordinates.")
            return
        }

        let hasAnimation = selectedAnimationIndex != nil
        if hasAnimation && triggerType == .speech
            && triggerPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Enter the phrase that should trigger the animation."
            return
        }

        print(" Location: lat=\(lat), lon=\(lon)")
        print("   Rotation:", rotation, "Scale:", scale)
        print("   User ID:", userId)

        isBusy = true
        defer {
            isBusy = false
            print(" Digital asset upload completed\n──────────────────────────────\n")
        }

        do {
            // 1. Create location row with exact address + altitude
            print(" Inserting location into 'locations' table...")
            let newLocation = NewLocation(
                name: name.isEmpty ? "AR Placement" : name,
                geom: "SRID=4326;POINT(\(lon) \(lat))",
                address: address.isEmpty ? nil : address,
                city: city,
                country: country,
                altitude_m: capturedAltitude,
                altitude_accuracy_m: altitudeAccuracy
            )
            let locRow: LocationInsertResponse = try await client
                .from("locations")
                .insert(newLocation)
                .select("location_id")
                .single()
                .execute()
                .value

            let locationId = locRow.location_id
            print(" Location row inserted → id:", locationId)

            // 2. Insert digital asset
            let newAsset = NewAsset(
                user_id: userId,
                name: name.isEmpty ? "Untitled Asset" : name,
                description: descriptionText,
                file_url: uploaded.absoluteString,
                file_type: fileType,
                category: "ar_model",
                visibility: visibility,
                location_id: locationId,
                rotation_x: Double(rotation.x),
                rotation_y: Double(rotation.y),
                rotation_z: Double(rotation.z),
                scale_x: Double(scale.x),
                scale_y: Double(scale.y),
                scale_z: Double(scale.z),
                animation_name: selectedAnimationIndex.flatMap { availableAnimations.indices.contains($0) ? availableAnimations[$0] : nil },
                animation_index: selectedAnimationIndex,
                trigger_type: hasAnimation ? triggerType.rawValue : nil,
                trigger_config: hasAnimation ? currentTriggerConfig() : nil
            )

            print(" Uploading asset to 'digital_assets' table...")
            try await client.from("digital_assets").insert(newAsset).execute()
            print("  Digital asset inserted successfully!")
            
            await MainActor.run {
                isAssetSaved = true
                showSuccessAlert = true
            }

            // 3. Optional post creation (future feature)
            if alsoMakePost {
                print(" (Skipped) Post creation flow — coming soon.")
            }

            // Reset state
            print(" Resetting form state for next asset...")
            step = .file
            localFileURL = nil
            uploadedFileURL = nil
            transform = nil
            name = ""
            descriptionText = ""
            visibility = "public"
            alsoMakePost = false
            address = ""
            city = nil
            country = nil
            capturedAltitude = nil
            altitudeAccuracy = nil
            availableAnimations = []
            selectedAnimationIndex = nil
            previewEntity = nil
            triggerType = .tap
            triggerDistance = 10
            triggerPhrase = ""
            shakePattern = .single

        } catch {
            print("  Failed during digital asset upload.")
            print("   ↳ Error:", error.localizedDescription)
            if let nsError = error as NSError? {
                print("   • Domain:", nsError.domain)
                print("   • Code:", nsError.code)
                print("   • Info:", nsError.userInfo)
            }
            self.error = "Save failed: \(error.localizedDescription)"
        }
    }
    
    

    // MARK: FUNCTION: currentTriggerConfig
    /// - Description: Builds the trigger_config payload for the chosen trigger type.
    private func currentTriggerConfig() -> TriggerConfig {
        switch triggerType {
        case .tap:
            return TriggerConfig()
        case .proximity:
            return TriggerConfig(distanceM: triggerDistance)
        case .speech:
            return TriggerConfig(phrase: triggerPhrase.trimmingCharacters(in: .whitespacesAndNewlines))
        case .shake:
            return TriggerConfig(shakePattern: shakePattern)
        }
    }


    // MARK: CLLocationManagerDelegate
    /// Updates user’s last known location whenever it changes.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }
}


// MARK: EXTENSION: simd_quatf
/// Converts quaternion rotations to Euler angles (roll, pitch, yaw).
/// This included some basic calculations that I just learned from a coding exaple I found
/// https://automaticaddison.com/how-to-convert-a-quaternion-into-euler-angles-in-python/
/// technically I treated it more as a template
/// when I forced triedtouse without conversion I learned how important maths is.
extension simd_quatf {
    func toEulerAngles() -> SIMD3<Float> {
        let q = self.vector
        let sinr_cosp = 2 * (q.w * q.x + q.y * q.z)
        let cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y)
        let roll = atan2(sinr_cosp, cosr_cosp)

        let sinp = 2 * (q.w * q.y - q.z * q.x)
        let pitch: Float = abs(sinp) >= 1 ? copysign(.pi / 2, sinp) : asin(sinp)

        let siny_cosp = 2 * (q.w * q.z + q.x * q.y)
        let cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z)
        let yaw = atan2(siny_cosp, cosy_cosp)

        return SIMD3<Float>(roll, pitch, yaw)
    }
}



// MARK: STRUCT: NewLocation
/// - Description: Insert payload for the locations table, carrying the exact
/// street address and the poster's altitude alongside the PostGIS point.
struct NewLocation: Encodable {
    let name: String
    let geom: String
    let address: String?
    let city: String?
    let country: String?
    let altitude_m: Double?
    let altitude_accuracy_m: Double?
}


// MARK: STRUCT: NewAsset
/// - Description: a comparatively smaller struct for inserting a new digital asset into Supabase.
struct NewAsset: Encodable {
    let user_id: UUID
    let name: String?
    let description: String?
    let file_url: String
    let file_type: String
    let category: String
    let visibility: String
    let location_id: UUID
    let rotation_x, rotation_y, rotation_z: Double
    let scale_x, scale_y, scale_z: Double
    let animation_name: String?
    let animation_index: Int?
    let trigger_type: String?
    let trigger_config: TriggerConfig?
}
