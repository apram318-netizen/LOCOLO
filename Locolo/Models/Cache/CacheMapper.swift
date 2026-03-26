//
//  CacheMapper.swift
//  Locolo
//
//  Created by Apramjot Singh on 10/11/2025.
//

import CoreData
import Foundation

enum CacheMapper {
    private static let jsonDecoder = JSONDecoder()
    private static let jsonEncoder = JSONEncoder()
    
    
    // MARK: - Places

    // MARK: FUNCTION: Make Post
    /// - Description: Convert cached post data into the domain `Post` model, resolving local vs remote media URLs.
    ///
    ///  So this function is taking in the cached post and is using it to map to a Post struct that can be later used throughout the app
    ///  and it is compatable with the cloud decoding
    ///
    /// - Parameters: cached: CachedPost - The cached post entity from Core Data.
    /// - Returns: Post? - The domain Post model, or nil if conversion fails.
    static func makePost(from cached: CachedPost) -> Post? {
        let mediaURL = localOrRemote(path: cached.localMediaPath, remote: cached.remoteMediaURL)
        let placeMediaURL = localOrRemote(path: cached.localPlaceMediaPath, remote: cached.remotePlaceMediaURL)
        let realMemoryURL = localOrRemote(path: cached.localRealMemoryPath, remote: cached.remoteRealMemoryURL)

        let place = cached.place.flatMap { makePlace(from: $0) }
        let author = cached.author.map { makeAuthor(from: $0) }

        let tags = decodeTags(from: cached.tagsJSON)

        return Post(
            id: cached.postId,
            loopId: cached.loopId ?? UUID(),
            authorId: cached.authorId ?? UUID(),
            caption: cached.caption,
            media: mediaURL,
            placeMedia: placeMediaURL,
            realMemoryMedia: realMemoryURL,
            tags: tags,
            placeId: cached.placeId ?? cached.place?.placeId,
            visibility: cached.visibility,
            isDeleted: false,
            createdAt: cached.createdAt ?? Date(),
            updatedAt: cached.updatedAt,
            author: author,
            place: place,
            eventId: nil,
            eventContext: nil
        )
    }
    

    // MARK: FUNCTION: upsert Post
    /// - Description: It finds or creates a cached post and updates it with the latest post data
    ///
    ///  This function is taking a post struct and is either finding an existing cached post or creating a new one
    ///
    /// - Parameters: post: Post - The domain post model to be persisted.
    /// - Returns: CachedPost - The updated or newly created cached post entity.
    @discardableResult
    static func upsert(post: Post, in context: NSManagedObjectContext) -> CachedPost {
        let object = fetchOrInsert(entity: CachedPost.self,
                                   predicate: NSPredicate(format: "postId == %@", (post.id ?? UUID()) as CVarArg),
                                   in: context)

        if let postId = post.id {
            object.postId = postId
        } else {
            object.postId = UUID()
        }
        object.loopId = post.loopId
        object.authorId = post.authorId
        object.caption = post.caption
        object.createdAt = post.createdAt
        object.updatedAt = post.updatedAt
        object.visibility = post.visibility
        object.remoteMediaURL = post.media?.absoluteString
        object.remotePlaceMediaURL = post.placeMedia?.absoluteString
        object.remoteRealMemoryURL = post.realMemoryMedia?.absoluteString
        object.placeId = post.placeId
        object.tagsJSON = encodeTags(post.tags)
        object.syncedAt = Date()

        if let remote = post.media,
           let cached = MediaCache.shared.localURL(forRemoteURL: remote) {
            object.localMediaPath = cached.path
        }
        if let remote = post.placeMedia,
           let cached = MediaCache.shared.localURL(forRemoteURL: remote) {
            object.localPlaceMediaPath = cached.path
        }
        if let remote = post.realMemoryMedia,
           let cached = MediaCache.shared.localURL(forRemoteURL: remote) {
            object.localRealMemoryPath = cached.path
        }

        if let author = upsert(author: post.author, authorId: post.authorId, in: context) {
            object.author = author
        }

        if let place = post.place {
            object.place = upsert(place: place, in: context)
        } else {
            object.place = nil
        }

        return object
    }
    
    

    // MARK: - Places

    // MARK: FUNCTION: Make Place
    /// - Description: Convert cached place data into the domain `Place` model.
    ///
    /// So this function is taking in the cached  place and is using it to map to a place struct that can be later used throughout the app
    ///
    /// - Parameters : cached: CachedPlace - The cached place entity from Core Data.
    /// - Returns: Place - The domain Place model.
    static func makePlace(from cached: CachedPlace) -> Place {
        let location = cached.location.map { makeLocation(from: $0) }
        let imageString: String?
        if let localPath = cached.localImagePath {
            imageString = URL(fileURLWithPath: localPath).absoluteString
        } else {
            imageString = cached.remoteImageURL
        }

        return Place(
            id: cached.placeId ?? UUID(),
            loopID: cached.loopId,
            postedBy: cached.postedBy,
            name: cached.name ?? "",
            categoryId: cached.categoryId,
            description: cached.placeDescription,
            placeImageUrl: imageString,
            trailerMediaUrl: cached.trailerMediaURL,
            createdAt: cached.createdAt,
            locationId: cached.locationId ?? cached.location?.locationId,
            verificationStatus: cached.verificationStatus,
            score: cached.score,
            location: location
        )
    }
    


    // MARK: FUNCTION: upsert Place
    /// - Description: It finds or creates a cached place and updates it with the latest place data
    ///
    ///  This function is taking a place struct and is either finding an existing cached place or creating a new one
    ///
    /// - Parameters: place - The domain place model to be persisted.
    /// - Returns: CachedPlace - The updated or newly created cached place entity.
    @discardableResult
    static func upsert(place: Place, in context: NSManagedObjectContext) -> CachedPlace {
        let object = fetchOrInsert(entity: CachedPlace.self,
                                   predicate: NSPredicate(format: "placeId == %@", place.id as CVarArg),
                                   in: context)

        object.placeId = place.id
        object.loopId = place.loopID
        object.postedBy = place.postedBy
        object.name = place.name
        object.categoryId = place.categoryId
        object.placeDescription = place.description
        object.remoteImageURL = place.placeImageUrl
        object.trailerMediaURL = place.trailerMediaUrl
        object.createdAt = place.createdAt
        object.verificationStatus = place.verificationStatus
        object.score = place.score ?? object.score
        object.syncedAt = Date()
        object.locationId = place.locationId ?? object.locationId

        if let remoteString = place.placeImageUrl,
           let remoteURL = URL(string: remoteString),
           let cached = MediaCache.shared.localURL(forRemoteURL: remoteURL) {
            object.localImagePath = cached.path
        }

        if let location = place.location ?? fetchLocation(id: place.locationId, in: context) {
            object.location = upsert(location: location, in: context)
            object.locationId = location.id
        }

        if let postedBy = place.postedBy,
           let cachedUser = fetchUser(id: postedBy, in: context) {
            object.user = cachedUser
        }

        return object
    }
    
    

    // MARK: - Locations

    // MARK: FUNCTION: Make Location
    /// - Description: Convert cached place data into the domain `Locations` model.
    ///
    /// So this function is taking in the cached  Location and is using it to map to a Location struct that can be later used throughout the app
    ///
    /// - Parameters : cached: CachedLocation - The cached Location entity from Core Data.
    /// - Returns: Location - The domain Location model.
    static func makeLocation(from cached: CachedLocation) -> Location {
        Location(
            id: cached.locationId ?? UUID(),
            name: cached.name ?? "",
            address: cached.address ?? "",
            city: cached.city,
            country: cached.country,
            googlePlaceId: cached.googlePlaceId,
            geom: cached.geomWKT,
            similarityScore: cached.similarityScore,
            distMeters: cached.distMeters,
            latitude: cached.latitude,
            longitude: cached.longitude
        )
    }
    
    

    // MARK: FUNCTION: upsert Location
    /// - Description: It finds or creates a cached Location and updates it with the latest Location data
    ///
    ///  This function is taking a place struct and is either finding an existing cached Location or creating a new one
    ///
    /// - Parameters: Location - The  Location model to be persisted.
    /// - Returns: CachedLocation - The updated or newly created cached Location entity.
    @discardableResult
    static func upsert(location: Location, in context: NSManagedObjectContext) -> CachedLocation {
        let object = fetchOrInsert(entity: CachedLocation.self,
                                   predicate: NSPredicate(format: "locationId == %@", location.id as CVarArg),
                                   in: context)

        object.locationId = location.id
        object.name = location.name
        object.address = location.address
        object.city = location.city
        object.country = location.country
        object.googlePlaceId = location.googlePlaceId
        object.geomWKT = location.geom
        if let similarity = location.similarityScore {
            object.similarityScore = similarity
        }
        if let dist = location.distMeters {
            object.distMeters = dist
        }
        if let latitude = location.latitude {
            object.latitude = latitude
        }
        if let longitude = location.longitude {
            object.longitude = longitude
        }
        object.syncedAt = Date()

        return object
    }
    
    
    

    // MARK: - Users

    // MARK: FUNCTION: Make author
    /// - Description: Convert cached Users data into the domain `author` model.
    ///
    /// So this function is taking in the cached author and is using it to map to a author struct that can be later used throughout the app
    ///
    /// - Parameters : cached: Cachedauthor - The cached Users entity from Core Data.
    /// - Returns: Users - The domain author model.
    static func makeAuthor(from cached: CachedUser) -> Post.Author {
        let avatar = cached.localAvatarPath.flatMap { URL(fileURLWithPath: $0) } ?? cached.avatarURL.flatMap(URL.init(string:))
        return Post.Author(
            username: cached.username ?? "",
            avatarUrl: avatar, loopTimeCounters: nil
        )
    }
    
    
    

    // MARK: FUNCTION: upsert author
    /// - Description: It finds or creates a cached author and adds to the users fields
    ///
    /// This function is taking a Users struct and is either finding an existing cached User or creating a new one
    /// The author is a further derived field for lightweight actions of current user profile basics access
    ///
    ///-  Warning: the author id is a newly generated UUID or not present in supabase can result in mismatched databases( Learned it the hard way)
    /// - Parameters: author - The  Users model to be persisted.
    /// - Returns: CachedUsers- The updated or newly created cached Users entity.
    @discardableResult
    static func upsert(author: Post.Author?, authorId: UUID, in context: NSManagedObjectContext) -> CachedUser? {
        
        guard let author else {
            return fetchUser(id: authorId, in: context)
        }
        let cached = fetchOrInsert(entity: CachedUser.self,
                                   predicate: NSPredicate(format: "userId == %@", authorId as CVarArg),
                                   in: context)
        cached.userId = authorId
        cached.username = author.username
        cached.avatarURL = author.avatarUrl?.absoluteString
        cached.syncedAt = Date()
        if let remote = author.avatarUrl,
           let local = MediaCache.shared.localURL(forRemoteURL: remote) {
            cached.localAvatarPath = local.path
        }
        return cached
    }
    
    
    

    // MARK: FUNCTION: Make Users
    /// - Description: Convert cached Users data into the domain `Users` model.
    ///
    /// So this function is taking in the cached Users and is using it to map to a Users struct that can be later used throughout the app
    ///
    /// - Parameters : cached: CachedUsers - The cached Users entity from Core Data.
    /// - Returns: Users - The domain Users model.
    static func makeUser(from cached: CachedUser) -> User {
        
        User(
            id: cached.userId ?? UUID(),
            username: cached.username ?? "",
            email: cached.email ?? "",
            name: cached.name,
            bio: cached.bio,
            avatarUrl: cached.localAvatarPath.flatMap { URL(fileURLWithPath: $0) } ?? cached.avatarURL.flatMap(URL.init(string:)),
            coverUrl: cached.coverURL.flatMap(URL.init(string:)),
            joinedAt: cached.joinedAt,
            verifiedFlags: cached.verificationStatus == nil ? nil : ["verified": cached.verificationStatus == "verified"],
            stats: nil
        )
    }
    
    

    // MARK: FUNCTION: upsert user
    /// - Description: It finds or creates a cached user and updates it with the latest user data
    ///
    ///  This function is taking a user struct and is either finding an existing cached user or creating a new one
    ///
    /// - Parameters: user - The  user model to be persisted.
    /// - Returns: Cacheduser- The updated or newly created cached user entity.
    @discardableResult
    static func upsert(user: User, in context: NSManagedObjectContext) -> CachedUser {
        
        let cached = fetchOrInsert(entity: CachedUser.self,
                                   predicate: NSPredicate(format: "userId == %@", user.id as CVarArg),
                                   in: context)
        cached.userId = user.id
        cached.username = user.username
        cached.email = user.email
        cached.name = user.name
        cached.bio = user.bio
        cached.avatarURL = user.avatarUrl?.absoluteString
        cached.coverURL = user.coverUrl?.absoluteString
        cached.joinedAt = user.joinedAt
        cached.verificationStatus = user.verifiedFlags?["verified"] == true ? "verified" : nil
        cached.syncedAt = Date()
        if let remote = user.avatarUrl,
           let local = MediaCache.shared.localURL(forRemoteURL: remote) {
            cached.localAvatarPath = local.path
        }
        return cached
    }
    
    
    

    // MARK: - Activities

    // MARK: FUNCTION: Make Activities
    /// - Description: Convert cached Activities data into the domain `Activities` model.
    ///
    /// So this function is taking in the cached Activities and is using it to map to a Activities struct that can be later used throughout the app
    ///
    /// - Parameters : cached: CachedActivities- The cached Activities entity from Core Data.
    /// - Returns: Activities - The domain Activities model.
    static func makeActivity(from cached: CachedActivity) -> Activity {
        
        Activity(
            id: cached.activityId ?? UUID(),
            placeID: cached.placeId,
            loopID: cached.loopId ?? UUID(),
            postedBy: cached.postedBy ?? UUID(),
            name: cached.name ?? "",
            description: cached.activityDescription,
            categoryId: cached.categoryId,
            activityDateTime: cached.activityDateTime,
            activityImageUrl: cached.activityImageURL,
            isUserHidden: cached.isUserHidden,
            createdAt: cached.createdAt ?? Date()
        )
    }
    
    
    

    // MARK: FUNCTION:  upsert Activities
    /// - Description: It finds or creates a cached Activities and updates it with the latest Activities data
    ///
    ///  This function is taking a Activities struct and is either finding an existing cached Activities or creating a new one
    ///
    /// - Parameters: Activities - The  Activities model to be persisted.
    /// - Returns: CachedActivities- The updated or newly created cached Activities entity.
    @discardableResult
    static func upsert(activity: Activity, in context: NSManagedObjectContext) -> CachedActivity {
        
        let cached = fetchOrInsert(entity: CachedActivity.self,
                                   predicate: NSPredicate(format: "activityId == %@", activity.id as CVarArg),
                                   in: context)
        cached.activityId = activity.id
        cached.placeId = activity.placeID
        cached.loopId = activity.loopID
        cached.postedBy = activity.postedBy
        cached.name = activity.name
        cached.activityDescription = activity.description
        cached.categoryId = activity.categoryId
        cached.activityDateTime = activity.activityDateTime
        cached.activityImageURL = activity.activityImageUrl
        cached.isUserHidden = activity.isUserHidden
        cached.createdAt = activity.createdAt
        cached.syncedAt = Date()
        return cached
    }
    
    
    

    // MARK: - Digital Assets

    // MARK: FUNCTION: Make Digital Assets
    /// - Description: Convert cached Digital Assets data into the domain `DigitalAssets` model.
    ///
    /// So this function is taking in the cached Activities and is using it to map to a Activities struct that can be later used throughout the app
    ///
    /// - Parameters : cached: CachedDigitalAssets- The cached Digital Assets entity from Core Data.
    /// - Returns: Digital Assets - The domain Digital Assets model.
    static func makeDigitalAsset(from cached: CachedDigitalAsset) -> DigitalAsset {
        
        let fileURLString: String
        if let localPath = cached.localFilePath {
            fileURLString = URL(fileURLWithPath: localPath).absoluteString
        } else {
            fileURLString = cached.fileURL ?? ""
        }

        
        // Adding strict cheks here to make sure the url exists in any case, either locally or cloud
        // Currently I  have the flow of uploading it/ thats why
        let thumbURLString: String?
        if let localThumb = cached.localThumbPath {
            let url = URL(fileURLWithPath: localThumb)
            if FileManager.default.fileExists(atPath: url.path),
               (try? Data(contentsOf: url))?.isEmpty == false {
                thumbURLString = url.absoluteString
            } else {
                thumbURLString = cached.thumbURL
            }
        } else {
            thumbURLString = cached.thumbURL
        }

        let hypeCountValue = (cached.value(forKey: "hypeCount") as? Int32).map(Int.init) ?? 0
        let viewCountValue = (cached.value(forKey: "viewCount") as? Int32).map(Int.init) ?? 0
        let latitude = cached.value(forKey: "latitude") as? Double
        let longitude = cached.value(forKey: "longitude") as? Double
        let rotationX = cached.value(forKey: "rotationX") as? Double
        let rotationY = cached.value(forKey: "rotationY") as? Double
        let rotationZ = cached.value(forKey: "rotationZ") as? Double
        let scaleX = cached.value(forKey: "scaleX") as? Double
        let scaleY = cached.value(forKey: "scaleY") as? Double
        let scaleZ = cached.value(forKey: "scaleZ") as? Double
        let isForSale = cached.value(forKey: "isForSale") as? Bool
        let acceptsOffers = cached.value(forKey: "acceptsOffers") as? Bool
        let currentValue = cached.value(forKey: "currentValue") as? Double
        let boughtPrice = cached.value(forKey: "boughtPrice") as? Double
        let activeOffersValue = cached.value(forKey: "activeOffers") as? Int32

        return DigitalAsset(
            id: cached.assetId ?? UUID(),
            name: cached.name,
            userId: cached.userId ?? UUID(),
            locationId: nil,
            fileUrl: fileURLString,
            thumbUrl: thumbURLString,
            fileType: cached.fileType ?? "",
            category: cached.category,
            description: cached.descriptionText,
            hypeCount: hypeCountValue,
            viewCount: viewCountValue,
            createdAt: cached.createdAt ?? Date(),
            panoramaUrl: cached.localPanoramaPath.flatMap { URL(fileURLWithPath: $0).absoluteString } ?? cached.panoramaURL,
            visibility: cached.visibility ?? "",
            interactionType: cached.interactionType,
            locationName: cached.locationName,
            latitude: latitude,
            longitude: longitude,
            rotationX: rotationX,
            rotationY: rotationY,
            rotationZ: rotationZ,
            scaleX: scaleX,
            scaleY: scaleY,
            scaleZ: scaleZ,
            isForSale: isForSale,
            acceptsOffers: acceptsOffers,
            currentValue: currentValue,
            boughtPrice: boughtPrice,
            highestOffer: nil,
            activeOffers: activeOffersValue == nil ? nil : Int(activeOffersValue!)
        )
    }
    
    
    

    // MARK: FUNCTION:  upsert Digital Assets
    /// - Description: It finds or creates a cached Digital Assets and updates it with the latest Digital Assets data
    ///
    ///  This function is taking a Digital Assets struct and is either finding an existing cached Digital Assets or creating a new one
    ///
    /// - Parameters: Digital Assets - The  Digital Assets model to be persisted.
    /// - Returns: CachedDigital Assets- The updated or newly created cached Digital Assets entity.
    @discardableResult
    static func upsert(digitalAsset: DigitalAsset, in context: NSManagedObjectContext) -> CachedDigitalAsset {
        let cached = fetchOrInsert(entity: CachedDigitalAsset.self,
                                   predicate: NSPredicate(format: "assetId == %@", digitalAsset.id as CVarArg),
                                   in: context)
        cached.assetId = digitalAsset.id
        cached.name = digitalAsset.name
        cached.userId = digitalAsset.userId
        cached.fileURL = digitalAsset.fileUrl
        cached.thumbURL = digitalAsset.thumbUrl
        cached.fileType = digitalAsset.fileType
        cached.category = digitalAsset.category
        cached.descriptionText = digitalAsset.description
        cached.setValue(Int32(digitalAsset.hypeCount), forKey: "hypeCount")
        cached.setValue(Int32(digitalAsset.viewCount), forKey: "viewCount")
        cached.visibility = digitalAsset.visibility
        cached.createdAt = digitalAsset.createdAt
        cached.syncedAt = Date()
        cached.interactionType = digitalAsset.interactionType
        cached.locationName = digitalAsset.locationName
        cached.setValue(digitalAsset.latitude, forKey: "latitude")
        cached.setValue(digitalAsset.longitude, forKey: "longitude")
        cached.setValue(digitalAsset.rotationX, forKey: "rotationX")
        cached.setValue(digitalAsset.rotationY, forKey: "rotationY")
        cached.setValue(digitalAsset.rotationZ, forKey: "rotationZ")
        cached.setValue(digitalAsset.scaleX, forKey: "scaleX")
        cached.setValue(digitalAsset.scaleY, forKey: "scaleY")
        cached.setValue(digitalAsset.scaleZ, forKey: "scaleZ")
        cached.setValue(digitalAsset.isForSale, forKey: "isForSale")
        cached.setValue(digitalAsset.acceptsOffers, forKey: "acceptsOffers")
        cached.setValue(digitalAsset.currentValue, forKey: "currentValue")
        cached.setValue(digitalAsset.boughtPrice, forKey: "boughtPrice")
        cached.setValue(digitalAsset.activeOffers.map { Int32($0) }, forKey: "activeOffers")

        if let remote = URL(string: digitalAsset.fileUrl),
           let local = MediaCache.shared.localURL(forRemoteURL: remote) {
            cached.localFilePath = local.path
        }
        if let thumbString = digitalAsset.thumbUrl,
           let remoteThumb = URL(string: thumbString),
           let localThumb = MediaCache.shared.localURL(forRemoteURL: remoteThumb) {
            cached.localThumbPath = localThumb.path
        }
        if let panorama = digitalAsset.panoramaUrl,
           let remotePanorama = URL(string: panorama),
           let localPanorama = MediaCache.shared.localURL(forRemoteURL: remotePanorama) {
            cached.localPanoramaPath = localPanorama.path
        }

        if let owner = fetchUser(id: digitalAsset.userId, in: context) {
            cached.owner = owner
        }

        return cached
    }

    
    
    // MARK: - Helpers

    
    // MARK: FUNCTION:  fetchLocation
    /// - Description: It returns a location from core data based on the id passed
    ///
    ///  This function is technically using the id and requesting core data , if you get nil it is not cached yet or the id is incorrect
    ///
    /// - Parameters: id - The  Location id to be fetched.
    /// - Returns: Location? - The Location model if found else nil.
    private static func fetchLocation(id: UUID?, in context: NSManagedObjectContext) -> Location? {
        guard let id else { return nil }
        let request: NSFetchRequest<CachedLocation> = CachedLocation.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "locationId == %@", id as CVarArg)
        guard let cached = try? context.fetch(request).first else { return nil }
        return makeLocation(from: cached)
    }
    
    

    // MARK: FUNCTION:  fetchUser
    /// - Description: It returns a user from core data based on the id passed
    ///
    ///  This function is technically using the id and requesting core data , if you get nil it is not cached yet or the id is incorrect
    ///   this function  gives you the cached user anthe user model
    ///
    /// - Parameters: id - The  user id to be fetched.
    /// - Returns: this returns the cachedUser instead.
    private static func fetchUser(id: UUID, in context: NSManagedObjectContext) -> CachedUser? {
        let request: NSFetchRequest<CachedUser> = CachedUser.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "userId == %@", id as CVarArg)
        return try? context.fetch(request).first
    }
    
    
    
    // MARK: FUNCTION:  localOrRemote
    /// - Description: Decide whether to use the cached local URL or the remote URL for media.
    ///
    /// basically every mapper that reconstructs media (posts, places, assets) is currently using this,
    /// it just checks what is avaailable locally first
    ///
    /// - Parameters: path - The local file path if available, remote - The remote URL string if available.
    /// - Returns: URL? - The resolved URL to use, or nil if neither is available.
    private static func localOrRemote(path: String?, remote: String?) -> URL? {
        if let path, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let remote, let url = URL(string: remote) {
            return url
        }
        return nil
    }
    
    
    
    // MARK: FUNCTION: DecodeTags
    /// - Description:Decode JSON stored tags into a `[String]`.
    ///
    /// Currently the tags are not well set up with the cloud but in future the tags will  be utilised for algorithms
    /// In future from string it will help me even if some other structure is needed for algorithms
    ///
    /// - Parameters: string - The JSON string representing the tags.
    /// - Returns: [String]? - The decoded array of tags, or nil if decoding fails.
    private static func decodeTags(from string: String?) -> [String]? {
        guard let string,
              let data = string.data(using: .utf8),
              let tags = try? jsonDecoder.decode([String].self, from: data) else {
            return nil
        }
        return tags
    }
    
    
    
    // MARK: FUNCTION: EncodeTags
    /// - Description:Serialize tags into JSON for Core Data storage.
    ///
    /// Currently the tags are not well set up with the cloud but in future the tags will  be utilised for algorithms
    /// In future from string it will help me even if some other structure is needed for algorithms
    ///
    /// - Parameters: tags - The array of tags to encode.
    /// - Returns: String? - The JSON string representing the tags, or nil if encoding fails.
    private static func encodeTags(_ tags: [String]?) -> String? {
        guard let tags,
              let data = try? jsonEncoder.encode(tags),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    

    // MARK: FUNCTION: fetchOrInsert
    /// - Description: Grab an existing managed object or create a fresh one when missing.
    ///
    /// This is a generic helper to reduce boilerplate when upserting entities in Core Data.
    /// It tries to fetch an existing object matching the predicate I usually pass in
    ///
    /// - Parameters: entity - The NSManagedObject subclass type, predicate - The fetch predicate, context - The managed object context.
    /// - Returns: T - The fetched or newly created managed object.
    /// - Warning: This function will crash if the entity description is missing.
    /// - Note: This function uses `try?` for fetching, so any errors during fetch are silently ignored.
    private static func fetchOrInsert<T: NSManagedObject>(entity: T.Type,
                                                          predicate: NSPredicate,
                                                          in context: NSManagedObjectContext) -> T {
        let request = T.fetchRequest()
        request.predicate = predicate
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first as? T {
            return existing
        }
        let entityName = String(describing: entity)
        guard let description = NSEntityDescription.entity(forEntityName: entityName, in: context) else {
            fatalError(" Missing entity description for \(entityName)")
        }
        return T(entity: description, insertInto: context)
    }
    
    
}

