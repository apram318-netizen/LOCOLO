//
//  CreatePostViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 7/10/2025.
//

import Foundation
import SwiftUI

// This whole view model is designed to help upload posts in steps, we first upload the media added by the user and then we move on to create the post with the supabase link we get

// MARK: FILE: CreatePostViewModel
/// - Description: Handles the entire create-post flow — uploads media, manages place data,
/// builds post payloads, and publishes them to Supabase. Basically the heart of Locolo’s posting system.
@MainActor
class CreatePostViewModel: ObservableObject {

    // MARK: - Published State
    @Published var contributionType: ContributionType?
    @Published var selectedPlaceSource: DataSource?

    // Memory media (user-uploaded images)
    @Published var memoryImages: [UIImage] = []
    @Published var uploadedMemoryURLs: [URL] = []

    // Place info
    @Published var placeImage: UIImage?
    @Published var uploadedPlaceURL: URL?
    @Published var selectedPlace: Place?

    // Digital / real memory
    @Published var digitalMemoryImage: UIImage?
    @Published var uploadedDigitalMemoryURL: URL?
    @Published var realMemories: [RealMemory] = []

    // Text + metadata
    @Published var description: String = ""
    @Published var tags: [String] = []
    @Published var isUploading: Bool = false
    @Published var errorMessage: String?
    @Published var isPosted: Bool = false
    
    // MARK: EVENT POSTING FLOW - Added for event post functionality
    @Published var postType: PostType = .normal
    @Published var selectedEvent: Event?
    @Published var eventContext: EventContext?
    
    // MARK: EVENT POSTING FLOW - State for creating new events
    @Published var isCreatingNewEvent: Bool = false
    @Published var newEventName: String = ""
    @Published var newEventDescription: String = ""
    @Published var newEventStartDate: Date = Date()
    @Published var newEventEndDate: Date = Date().addingTimeInterval(3600) // 1 hour later
    @Published var newEventImage: UIImage?
    @Published var uploadedEventImageURL: URL?
    
    // MARK: EVENT POSTING FLOW - Pricing fields for constraint compliance
    @Published var newEventIsFree: Bool = true  // Default to free event
    @Published var newEventPrice: String = ""   // User input as string
    @Published var newEventCurrency: String = "AUD"  // Default currency

    private let storage = ObjStorageManager.shared
    private let postRepository: PostRepositoryProtocol
    private let placeRepository: PlacesRepositoryProtocol
    private let realMemoryRepo = RealMemoryRepository()
    private let eventsRepo = EventsDiscoverRepository()  // EVENT POSTING FLOW: Added for event creation
    private let loopVM: LoopViewModel
    private let userVM: UserViewModel

    // MARK: Init
    /// - Description: Injects dependencies and connects with the current user + active loop.
    init(
        loopVM: LoopViewModel,
        userVM: UserViewModel,
        postRepository: PostRepositoryProtocol = PostsRepository(),
        placeRepository: PlacesRepositoryProtocol = PlacesRepository()
    ) {
        self.loopVM = loopVM
        self.userVM = userVM
        self.postRepository = postRepository
        self.placeRepository = placeRepository
    }

    
    // MARK: FUNCTION: uploadImage
    /// - Description: Compresses and uploads a `UIImage` to object storage.
    ///
    /// - Parameters:
    ///   - image: The image to upload
    ///   - folder: The target folder path in storage
    /// - Returns: A public URL to the uploaded image
    private func uploadImage(_ image: UIImage, folder: String) async throws -> URL {
        let data = image.jpegData(compressionQuality: 0.8)!
        let path = "\(folder)/\(UUID().uuidString).jpg"
        let urlString = try await storage.uploadFile(path: path, fileData: data, contentType: "image/jpeg")
        return URL(string: urlString)!
    }
    
    

    // MARK: FUNCTION: uploadMemoryImages
    /// - Description: Uploads all selected post photos (user’s memories) to Supabase storage.
    /// Uses smart compression + downscaling to keep images under 2 MB.
    /// Here important thing is even if I downscale it to 2 mb still storage bucket  may throw error , Json structure probabably adds a proportion of info to it
    /// So it is just better to keep fire base almost 50 percent more if scaling down to 2 mb then 3 mb is the ideal restriction for the bucket I guess.
    func uploadMemoryImages() async {
        isUploading = true
        defer { isUploading = false }

        do {
            var urls: [URL] = []
            for (index, img) in memoryImages.enumerated() {
                print(" [Image Upload \(index + 1)] Starting compression...")
                let maxBytes = 1_500_000
                var lower: CGFloat = 0.05
                var upper: CGFloat = 1.0
                var bestData: Data? = img.jpegData(compressionQuality: upper)

                while lower <= upper {
                    let mid = (lower + upper) / 2
                    guard let data = img.jpegData(compressionQuality: mid) else { break }
                    if data.count > maxBytes {
                        upper = mid - 0.05
                    } else {
                        bestData = data
                        lower = mid + 0.05
                    }
                    if abs(Double(data.count - maxBytes)) < 50_000 { break }
                }

                var finalData = bestData ?? Data()
                if finalData.count > maxBytes {
                    let targetScale = sqrt(Double(maxBytes) / Double(finalData.count))
                    let newSize = CGSize(width: img.size.width * targetScale, height: img.size.height * targetScale)
                    UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
                    img.draw(in: CGRect(origin: .zero, size: newSize))
                    let resized = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    if let resizedData = resized?.jpegData(compressionQuality: 0.8) {
                        finalData = resizedData
                    }
                }

                guard let finalImage = UIImage(data: finalData) else { continue }
                let url = try await uploadImage(finalImage, folder: "posts/memories")
                urls.append(url)
                print(" [Image \(index + 1)] Uploaded successfully → \(url)")
            }

            uploadedMemoryURLs = urls
        } catch {
            errorMessage = "Failed to upload memories: \(error.localizedDescription)"
        }
    }
    
    

    // MARK: FUNCTION: uploadPlaceImageIfNeeded
    /// - Description: Uploads the main image for a new place (if not already uploaded).
    func uploadPlaceImageIfNeeded() async {
        guard let img = placeImage, selectedPlace == nil else { return }
        isUploading = true
        do {
            uploadedPlaceURL = try await uploadImage(img, folder: "places")
        } catch {
            errorMessage = "Failed to upload place image: \(error.localizedDescription)"
        }
        isUploading = false
    }
    
    

    // MARK: FUNCTION: uploadDigitalMemoryImage
    /// - Description: Uploads the optional real memory” (like BeReal-style add-ons) to storage.
    /// Compresses image under 2 MB before uploading.
    func uploadDigitalMemoryImage() async {
        guard let img = digitalMemoryImage else { return }
        isUploading = true
        defer { isUploading = false }

        do {
            guard var data = img.jpegData(compressionQuality: 1.0) else {
                throw NSError(domain: "ImageConversion", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG."])
            }

            let maxSize = 2_000_000.0
            var compression: CGFloat = 0.9
            while Double(data.count) > maxSize && compression > 0.1 {
                compression -= 0.1
                if let newData = img.jpegData(compressionQuality: compression) { data = newData }
            }

            guard let compressed = UIImage(data: data) else {
                throw NSError(domain: "ImageConversion", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create UIImage from compressed data."])
            }

            uploadedDigitalMemoryURL = try await uploadImage(compressed, folder: "real_memories")
            print(" Digital memory uploaded successfully:", uploadedDigitalMemoryURL ?? URL(filePath: ""))
        } catch {
            errorMessage = "Failed to upload digital memory: \(error.localizedDescription)"
        }
    }
    
    

    // MARK: FUNCTION: publish
    /// - Description: Runs the full post creation process  uploads all assets,
    /// creates a new place if needed, inserts the post, and attaches any real memories.
    func publish() async {
        guard let author = userVM.currentUser,
              let loop = loopVM.activeLoop else {
            errorMessage = "Missing author or loop."
            return
        }

        isUploading = true
        errorMessage = nil

        do {
            // A) Get active loop ID safely (no random UUID generation)
            let activeLoopId = UUID(uuidString: loop.id ?? "")
            
            if !memoryImages.isEmpty && uploadedMemoryURLs.isEmpty { await uploadMemoryImages() }
            if placeImage != nil && uploadedPlaceURL == nil { await uploadPlaceImageIfNeeded() }
            if digitalMemoryImage != nil && uploadedDigitalMemoryURL == nil { await uploadDigitalMemoryImage() }

            // Create or reuse place
            var placeId: UUID? = selectedPlace?.id
            if selectedPlaceSource == .appleMap, let place = selectedPlace {
                let newPlace = PostPlace(
                    id: UUID(),
                    loopID: place.loopID ?? activeLoopId,
                    postedBy: place.postedBy ?? author.id,
                    name: place.name,
                    categoryId: place.categoryId,
                    description: place.description,
                    placeImageUrl: place.placeImageUrl ?? uploadedPlaceURL?.absoluteString,
                    trailerMediaUrl: nil,
                    createdAt: Date(),
                    locationId: place.locationId,
                    verificationStatus: place.verificationStatus ?? "pending"
                )
                try await placeRepository.addPlace(newPlace)
                placeId = newPlace.id
            }
            
            // EVENT POSTING FLOW: Create event if user is creating a new event
            var eventId: UUID? = nil
            if postType == .event {
                if isCreatingNewEvent {
                    // Upload event image if provided
                    if let eventImage = newEventImage, uploadedEventImageURL == nil {
                        uploadedEventImageURL = try await uploadImage(eventImage, folder: "events")
                    }
                    
                    // Validation: Event name cannot be empty
                    let trimmedName = newEventName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty else {
                        throw NSError(
                            domain: "EventCreation",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Event name cannot be empty"]
                        )
                    }
                    
                    // Validation: End time must be after start time
                    guard newEventEndDate > newEventStartDate else {
                        throw NSError(
                            domain: "EventCreation",
                            code: -4,
                            userInfo: [NSLocalizedDescriptionKey: "End time must be after start time"]
                        )
                    }
                    
                    // Create new event with proper constraint handling
                    // Constraint: is_free = true → price must be NULL or 0
                    //            is_free = false → price must be NOT NULL and > 0
                    let finalPrice: Double?
                    let finalIsFree: Bool
                    let finalCurrency: String?
                    
                    if newEventIsFree {
                        // Free event: set is_free = true, price = nil, currency = nil
                        finalPrice = nil
                        finalIsFree = true
                        finalCurrency = nil
                    } else {
                        // Paid event: require price > 0 and currency
                        guard let priceValue = Double(newEventPrice.trimmingCharacters(in: .whitespaces)),
                              priceValue > 0 else {
                            throw NSError(
                                domain: "EventCreation",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Paid events require a price greater than 0"]
                            )
                        }
                        
                        // B) Currency validation for paid events
                        let trimmedCurrency = newEventCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard !trimmedCurrency.isEmpty else {
                            throw NSError(
                                domain: "EventCreation",
                                code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "Paid events require a currency (e.g., AUD)"]
                            )
                        }
                        
                        finalPrice = priceValue
                        finalIsFree = false
                        finalCurrency = trimmedCurrency
                    }
                    
                    // C) Compute locationMode using available info
                    let derivedLocationMode: String = {
                        if placeId != nil { return "real_world" }
                        if activeLoopId != nil { return "virtual" }
                        // If you later add an online URL input for event creation, switch this when onlineUrl is set:
                        // if (someOnlineUrl != nil) { return "online" }
                        return "real_world"
                    }()
                    
                    // D) Create PostEvent with all fixes
                    let newEvent = PostEvent(
                        id: UUID(),
                        placeID: placeId,
                        loopID: activeLoopId,  // ✅ no random UUID
                        postedBy: author.id,
                        name: trimmedName,  // ✅ trimmed name
                        description: newEventDescription.isEmpty ? nil : newEventDescription,
                        categoryId: nil,
                        eventImageUrl: uploadedEventImageURL?.absoluteString,
                        trailerMediaUrl: nil,
                        createdAt: Date(),
                        startAt: newEventStartDate,
                        endAt: newEventEndDate,
                        price: finalPrice,
                        isFree: finalIsFree,
                        maxAttendees: nil,
                        eventType: nil,  // optional legacy; fine to leave nil
                        timezone: TimeZone.current.identifier,
                        officialUrl: nil,
                        officialUrlLabel: nil,
                        locationMode: derivedLocationMode,  // ✅ filled
                        onlineUrl: nil,  // optional for non-online; ok
                        visibility: "public",
                        status: "scheduled",
                        currency: finalCurrency
                    )
                    let createdEvent = try await eventsRepo.createEvent(newEvent)
                    eventId = createdEvent.id
                    selectedEvent = createdEvent
                } else {
                    // Use selected existing event
                    eventId = selectedEvent?.id
                }
            }

            // Create the post
            // EVENT POSTING FLOW: Include eventId and eventContext when postType is .event
            let post = Post(
                id: UUID(),
                loopId: UUID(uuidString: loop.id ?? "") ?? UUID(),
                authorId: author.id,
                caption: description,
                media: uploadedMemoryURLs.first,
                placeMedia: uploadedPlaceURL,
                realMemoryMedia: uploadedDigitalMemoryURL,
                tags: tags,
                placeId: placeId,
                visibility: "public",
                isDeleted: false,
                createdAt: Date(),
                updatedAt: nil,
                author: nil,
                place: nil,
                eventId: eventId,  // EVENT POSTING FLOW: Use eventId from created or selected event
                eventContext: postType == .event ? eventContext?.rawValue : nil
            )
            try await postRepository.createPost(post)

            // Add real memory record if present
            if let realURL = uploadedDigitalMemoryURL {
                let realMemory = RealMemory(
                    id: UUID(),
                    postId: post.id,
                    authorId: author.id,
                    loopId: UUID(uuidString: loop.id ?? ""),
                    placeId: placeId,
                    mediaUrl: realURL,
                    caption: description,
                    createdAt: Date(),
                    updatedAt: nil
                )
                try await realMemoryRepo.createRealMemory(realMemory)
                realMemories.append(realMemory)
            }

            isPosted = true
        } catch {
            errorMessage = "Failed to publish post: \(error.localizedDescription)"
        }

        isUploading = false
    }
    
    

    // MARK: FUNCTION: reset
    /// - Description: Clears all current form state to restart the create-post flow.
    func reset() {
        memoryImages = []
        uploadedMemoryURLs = []
        placeImage = nil
        uploadedPlaceURL = nil
        digitalMemoryImage = nil
        uploadedDigitalMemoryURL = nil
        description = ""
        tags = []
        selectedPlace = nil
        isUploading = false
        isPosted = false
        errorMessage = nil
        // Event posting fields (added for event post flow)
        postType = .normal
        selectedEvent = nil
        eventContext = nil
        isCreatingNewEvent = false
        newEventName = ""
        newEventDescription = ""
        newEventStartDate = Date()
        newEventEndDate = Date().addingTimeInterval(3600)
        newEventImage = nil
        uploadedEventImageURL = nil
        newEventIsFree = true
        newEventPrice = ""
        newEventCurrency = "AUD"
    }
    
    
    
}

// MARK: ========================================
// MARK: EVENT POSTING FLOW - ADDED RECENTLY
// MARK: ========================================
// The following code was added to support event posting functionality:
// - Users can toggle between Normal post and Event post
// - When Event post is selected, users can pick an event and select context (Announcement/Hype/Memory)
// - Event ID and context are saved with the post when published

// MARK: - Event Posting Enums
enum PostType {
    case normal
    case event
}

enum EventContext: String, CaseIterable {
    case event_announcement = "event_announcement"
    case hype = "hype"
    case memory = "memory"
    
    var displayName: String {
        switch self {
        case .event_announcement: return "Announcement"
        case .hype: return "Hype"
        case .memory: return "Memory"
        }
    }
}
