//
//  CacheStore.swift
//  Locolo
//
//  Created by Apramjot Singh on 10/11/2025.
//

import Foundation
import CoreData

final class CacheStore {
    static let shared = CacheStore()

    private let viewContext: NSManagedObjectContext

    private init(container: NSPersistentContainer = PersistenceController.shared) {
        self.viewContext = container.viewContext
    }

    // MARK: - Posts
    
    // MARK: FUNCTION: fetchPosts for loops
    /// - Description: It Returns cached posts for a loopId, which are sorted based on time
    /// - Parameters: - loopID: UUID - The unique identifier that matches supabase loop ID.
    /// - Returns: [Post] - An array of Post model structs, the standard I am using for app functionality
    func fetchPosts(loopID: UUID) -> [Post] {
        let request: NSFetchRequest<CachedPost> = CachedPost.fetchRequest()
        request.predicate = NSPredicate(format: "loopId == %@", loopID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        return (try? viewContext.fetch(request))?.compactMap(CacheMapper.makePost(from:)) ?? []
    }

    
    
    // MARK: FUNCTION: fetchPosts for places
    /// - Description: It Returns cached posts for a placeId, which are sorted based on time of creation
    /// - Parameters: -placeID: UUID - The unique identifier that matches supabase placeID .
    /// - Returns: [Post] - An array of Post model structs, the standard I am using for app functionality
    func fetchPosts(placeID: UUID) -> [Post] {
        let request: NSFetchRequest<CachedPost> = CachedPost.fetchRequest()
        request.predicate = NSPredicate(format: "place.placeId == %@", placeID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        return (try? viewContext.fetch(request))?.compactMap(CacheMapper.makePost(from:)) ?? []
    }
    
    
    // MARK: FUNCTION: upsertPosts
    /// - Description: It adds or updates cached posts for the posts that are passed in: It uses the cache mapper- upset to do so.
    /// - Parameters: Post Struct array - An array of Post model structs
    /// - Returns: nothing
    func upsertPosts(_ posts: [Post]) async {
        guard !posts.isEmpty else { return }

        let context = PersistenceController.newBackgroundContext()
        await context.perform {
            for post in posts {
                _ = CacheMapper.upsert(post: post, in: context)
            }
            context.saveIfNeeded()
        }
    }
    
    
    // MARK: - deletePosts not in
    /// - Description: It deletes cached posts for a loopID that are not in the passed list of UUIDs.
    /// - Parameters: - ids: [UUID] - An array of UUIDs representing post IDs that we want to keep. - loopID: UUID - The unique identifier that matches supabase loop ID.
    /// - Returns: nothing
    func deletePosts(notIn ids: [UUID], loopID: UUID) async {
    let context = PersistenceController.newBackgroundContext()
    await context.perform {
        let request: NSFetchRequest<NSFetchRequestResult> = CachedPost.fetchRequest()
        let predicates: [NSPredicate] = [
            NSPredicate(format: "loopId == %@", loopID as CVarArg),
            NSPredicate(format: "NOT (postId IN %@)", ids as [UUID] as CVarArg)
        ]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        if let result = try? context.execute(deleteRequest) as? NSBatchDeleteResult,
            let objectIDs = result.result as? [NSManagedObjectID], !objectIDs.isEmpty {
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs], into: [PersistenceController.viewContext])
        }
    }
}

    
    
    // MARK: - Places
    
    // MARK: - fetchPlaces
    /// - Description: It Returns cached places for each of the loops.
    /// - Parameters: - loopID: UUID? - The unique identifier that matches supabase loop ID. It is optional, if nil it fetches all places.
    /// - Returns: [Place] - An array of Place model structs
    func fetchPlaces(loopID: UUID?) -> [Place] {
        let request: NSFetchRequest<CachedPlace> = CachedPlace.fetchRequest()
        if let loopID = loopID {
            request.predicate = NSPredicate(format: "loopId == %@", loopID as CVarArg)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return (try? viewContext.fetch(request))?.compactMap(CacheMapper.makePlace(from:)) ?? []
    }
    
    
    // MARK: - fetchPlaces
    /// - Description: It Returns a single place for a perticular place id
    /// - Parameters: - id: UUID - The unique identifier that matches supabase place ID.
    /// - Returns: Place? - An optional Place model struct
    func fetchPlace(id: UUID) -> Place? {
        let request: NSFetchRequest<CachedPlace> = CachedPlace.fetchRequest()
        request.predicate = NSPredicate(format: "placeId == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first.flatMap(CacheMapper.makePlace(from:))
    }
    
    

    // MARK: - upsertPlaces
    /// - Description: It adds or updates cached places for the places that are passed in: It uses the cache mapper- upset to do so.
    /// - Parameters: - places: [Place] - An array of Place model structs
    /// - Returns: nothing
    func upsertPlaces(_ places: [Place]) async {
        guard !places.isEmpty else { return }
        let context = PersistenceController.newBackgroundContext()
        await context.perform {
            for place in places {
                _ = CacheMapper.upsert(place: place, in: context)
            }
            context.saveIfNeeded()
        }
    }

  
    // MARK: - Users
    
    
    // MARK: - fetchUser
    /// - Description: It Returns cached user for a particular user id.
    /// - Parameters: - id: UUID - The unique identifier that matches supabase user ID.
    /// - Returns: CachedUser? - An optional CachedUser managed object
    func fetchUser(id: UUID) -> CachedUser? {
        let request: NSFetchRequest<CachedUser> = CachedUser.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "userId == %@", id as CVarArg)
        return try? viewContext.fetch(request).first
    }
    
    
    // MARK: - fetchUserDomain
    /// - Description: It Returns cached user for a particular user id converted to domain model.
    /// - Parameters: - id: UUID - The unique identifier that matches supabase user ID
    /// - Returns: User? - An optional User model struct
    func fetchUserDomain(id: UUID) -> User? {
        fetchUser(id: id).map(CacheMapper.makeUser(from:))
    }

  
    
    // MARK: - fetchUser by username
    /// - Description: It Returns cached user for a particular username.
    /// - Parameters: - username: String - The unique username string.
    /// - Returns: CachedUser? - An optional CachedUser managed object
    func fetchUser(byUsername username: String) -> CachedUser? {
        let request: NSFetchRequest<CachedUser> = CachedUser.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "username == %@", username)
        return try? viewContext.fetch(request).first
    }

    
    // MARK: - fetchUserDomain by username
    /// - Description: It Returns cached user for a particular username converted to  the main model we are using
    /// - Parameters: - username: String - The unique username string.
    /// - Returns: User? - An optional User model struct
    func fetchUserDomain(username: String) -> User? {
        fetchUser(byUsername: username).map(CacheMapper.makeUser(from:))
    }
    
    // MARK: - upsertUser
    /// - Description: It adds or updates cached user for the user that is passed in:
    /// - Parameters: - user: User - A User model struct
    /// - Returns: nothing
    func upsertUser(_ user: User) async {
        let context = PersistenceController.newBackgroundContext()
        await context.perform {
            _ = CacheMapper.upsert(user: user, in: context)
            context.saveIfNeeded()
        }
    }
    
    
    // MARK: FUNCTION: fetchActivities
    /// - Description: It Returns cached activities optionally limited by count.
    /// - Parameters: - limit: Int? - An optional integer to limit the number of activities returned.
    /// - Returns: [Activity] - An array of Activity model structs
    func fetchActivities(limit: Int? = nil) -> [Activity] {
        let request: NSFetchRequest<CachedActivity> = CachedActivity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        if let limit = limit {
            request.fetchLimit = limit
        }
        return (try? viewContext.fetch(request))?.compactMap(CacheMapper.makeActivity(from:)) ?? []
    }
    
    
    //  MARK: - upsertActivities
    /// - Description: It adds or updates cached activities for the activities that are passed in: It uses the cache mapper- upset to do so.
    /// - Parameters: - activities: [Activity] - An array of Activity model structs
    /// - Returns: nothing
    func upsertActivities(_ activities: [Activity]) async {
        guard !activities.isEmpty else { return }
        let context = PersistenceController.newBackgroundContext()
        await context.perform {
            for activity in activities {
                _ = CacheMapper.upsert(activity: activity, in: context)
            }
            context.saveIfNeeded()
        }
    }
    
    
    //  MARK: - upsertActivities
    /// - Description: Just a clear cache function that I am majorly using during logout only.
    /// - Parameters:none
    /// - Returns: nothing
    func clearAllCache() {
        let context = self.viewContext
        let entities = [
            "CachedDigitalAsset",
            "CachedLocation",
            "CachedPlace",
            "CachedPost",
            "CachedUser",
            "CachedActivity"
        ]
        
        for entity in entities {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetch)
            do {
                try context.execute(deleteRequest)
            } catch {
                print(" Failed clearing \(entity):", error)
            }
        }
        
        do {
            try context.save()
        } catch {
            print(" Cache save error:", error)
        }
        
        print(" CoreData cache fully cleared")
    }
    
   // MARK: - Digital Assets
    
    // MARK: Function: fetchDigitalAssets with limit
    /// Description: Return cached digital assets, optionally limited by count.
    /// Parameters: - limit: Int? - An optional integer to limit the number of digital assets returned.
    /// Returns: [DigitalAsset] - An array of DigitalAsset model structs
    func fetchDigitalAssets(limit: Int? = nil) -> [DigitalAsset] {
        let request: NSFetchRequest<CachedDigitalAsset> = CachedDigitalAsset.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        if let limit = limit {
            request.fetchLimit = limit
        }
        return (try? viewContext.fetch(request))?.map(CacheMapper.makeDigitalAsset(from:)) ?? []
    }

    
    //MARK: Function: fetchDigitalAssets for user
    /// Description: Return cached digital assets for a specific user.
    /// Parameters: - userId: UUID - The unique identifier that matches supabase user ID
    /// Returns: [DigitalAsset] - An array of DigitalAsset model structs
    func fetchDigitalAssets(for userId: UUID) -> [DigitalAsset] {
        let request: NSFetchRequest<CachedDigitalAsset> = CachedDigitalAsset.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return (try? viewContext.fetch(request))?.map(CacheMapper.makeDigitalAsset(from:)) ?? []
    }

    
    
    // MARK: Function: upsertDigitalAssets
    /// Description: It adds or updates cached digital assets for the assets that are passed in: It uses the cache mapper- upsert to do so.
    /// Parameters: - assets: [DigitalAsset] - An array of DigitalAsset model structs
    /// Returns: nothing
    func upsertDigitalAssets(_ assets: [DigitalAsset]) async {
        guard !assets.isEmpty else { return }
        let context = PersistenceController.newBackgroundContext()
        await context.perform {
            for asset in assets {
                _ = CacheMapper.upsert(digitalAsset: asset, in: context)
            }
            context.saveIfNeeded()
        }
    }
    
    
    
    
}

// MARK: - Helpers

// MARK: NSManagedObjectContext Save If Needed
/// - Description: It only saves if the changes are there in the context.
private extension NSManagedObjectContext {
    func saveIfNeeded() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            print(" Core Data save error: \(error)")
        }
    }
}

