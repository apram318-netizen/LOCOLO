//
//  PostsRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import Foundation
import CoreLocation

protocol PostRepositoryProtocol {
    func fetchPosts(forLoop loopID: String, completion: @escaping (Result<[Post], Error>) -> Void)
    func fetchPosts(forPlaceId placeId: UUID) async throws -> [Post]
    func createPost(_ post: Post) async throws
    func refreshPosts(forLoop loopID: String) async throws -> [Post]
}

private let postsSelectColumns = """
    *,
    users:author_id (
        username,
        avatar_url,
        loop_time_counters!inner (
            status,
            total_hours,
            first_arrived_at,
            last_arrived_at,
            updated_at
        )
    ),
    places:place_id (
        place_id,
        name,
        description,
        place_image_url,
        category_id,
        loop_id,
        posted_by,
        location_id,
        locations:location_id (
            location_id,
            name,
            city,
            country,
            address,
            geom,
            google_place_id,
            latitude,
            longitude
        )
    )
"""


/// Connects directly to Supabase and keeps a local cache for smooth feed loading and offline use.
class PostsRepository: PostRepositoryProtocol {
    private let client = SupabaseManager.shared.client
    private let cacheStore = CacheStore.shared

    // MARK: FUNCTION: fetchPosts (forLoop)
    /// - Description: Loads posts for a specific loop, preferring cached data first.
    /// Updates cache in the background once new data arrives.
    ///
    /// - Parameters:
    ///   - loopID: The ID of the loop to fetch posts for
    ///   - completion: A closure returning `[Post]` on success or `Error` on failure
    func fetchPosts(forLoop loopID: String, completion: @escaping (Result<[Post], Error>) -> Void) {
        var cached: [Post] = []
        if let uuid = UUID(uuidString: loopID) {
            cached = cacheStore.fetchPosts(loopID: uuid)
            if !cached.isEmpty {
                completion(.success(cached))
            }
        }

        Task {
            do {
                let posts: [Post] = try await client
                    .from("posts")
                    .select(postsSelectColumns)
                    .eq("loop_id", value: loopID)
                    .eq("users.loop_time_counters.loop_id", value: loopID)
                    .order("created_at", ascending: false)
                    .execute()
                    .value

                await cacheMedia(for: posts)
                await cacheStore.upsertPosts(posts)
                completion(.success(posts))
            } catch {
                print(" Error fetching posts:", error)
                if cached.isEmpty {
                    completion(.failure(error))
                }
            }
        }
    }
    
    

    // MARK: FUNCTION: fetchPosts (forPlace)
    /// - Description: Loads posts tied to a specific place.
    /// Pulls from cache first and refreshes from Supabase when available.
    ///
    /// - Parameter placeId: The UUID of the place
    /// - Returns: A list of posts for that place
    func fetchPosts(forPlaceId placeId: UUID) async throws -> [Post] {
        let cached = cacheStore.fetchPosts(placeID: placeId)

        do {
            let posts: [Post] = try await client
                .from("posts")
                .select(postsSelectColumns)
                .eq("place_id", value: placeId)
                .order("created_at", ascending: false)
                .execute()
                .value

            await cacheMedia(for: posts)
            await cacheStore.upsertPosts(posts)
            return posts
        } catch {
            if !cached.isEmpty { return cached }
            throw error
        }
    }
    
    

    // MARK: FUNCTION: fetchPostsForAuthor
    /// - Description: Loads all posts created by a specific user.
    /// Used mainly in profile views or creator timelines.
    ///
    /// - Parameters:
    ///   - authorID: The user’s ID
    ///   - completion: A closure returning `[Post]` or `Error`
    func fetchPostsForAuthor(authorID: String, completion: @escaping (Result<[Post], Error>) -> Void) {
        Task {
            do {
                let posts: [Post] = try await client
                    .from("posts")
                    .select(postsSelectColumns)
                    .eq("author_id", value: authorID)
                    .order("created_at", ascending: false)
                    .execute()
                    .value

                await cacheMedia(for: posts)
                await cacheStore.upsertPosts(posts)
                completion(.success(posts))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    

    // MARK: FUNCTION: createPost
    /// - Description: Creates a new post in Supabase and mirrors it in cache.
    /// Also downloads and stores any linked media for offline display.
    ///
    /// - Parameter post: The `Post` model to insert
    /// - Throws: If the Supabase insert fails
    func createPost(_ post: Post) async throws {
        try await client
            .from("posts")
            .insert(post)
            .execute()

        await cacheMedia(for: [post])
        await cacheStore.upsertPosts([post])
    }
    
    

    // MARK: FUNCTION: refreshPosts
    /// - Description: Forces a full refresh of posts for a loop, updating local cache.
    ///
    /// - Parameter loopID: The ID of the loop to refresh posts for
    /// - Returns: A fresh list of posts for that loop
    func refreshPosts(forLoop loopID: String) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("posts")
            .select(postsSelectColumns)
            .eq("loop_id", value: loopID)
            .order("created_at", ascending: false)
            .execute()
            .value

        await cacheMedia(for: posts)
        await cacheStore.upsertPosts(posts)
        return posts
    }
    
    

    // MARK: Helper: cacheMedia
    /// - Description: Downloads and caches all media (post media, place images, avatars).
    /// Runs in parallel using a task group to speed things up.
    ///
    /// - Parameter posts: The posts whose media should be cached
    private func cacheMedia(for posts: [Post]) async {
        guard !posts.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for post in posts {
                for url in [post.media, post.placeMedia, post.realMemoryMedia].compactMap({ $0 }) where shouldDownload(url: url) {
                    group.addTask { await self.downloadAndCache(url: url) }
                }

                if let placeImage = post.place?.placeImageUrl,
                   let remote = URL(string: placeImage),
                   shouldDownload(url: remote) {
                    group.addTask { await self.downloadAndCache(url: remote) }
                }

                if let avatar = post.author?.avatarUrl,
                   shouldDownload(url: avatar) {
                    group.addTask { await self.downloadAndCache(url: avatar) }
                }
            }
        }
    }
    
    

    // MARK: Helper: shouldDownload
    /// - Description: Checks whether a URL’s media is already cached or not.
    ///
    /// - Parameter url: The media URL to check
    /// - Returns: `true` if it needs to be downloaded, otherwise false
    private func shouldDownload(url: URL) -> Bool {
        guard url.scheme != "file" else { return false }
        return MediaCache.shared.localURL(forRemoteURL: url) == nil
    }
    
    

    
    // MARK: Helper: downloadAndCache
    /// - Description: Fetches media data from the web and stores it locally by using  MediaCache.
    ///
    /// - Parameter url: The URL of the remote file
    private func downloadAndCache(url: URL) async {
        guard shouldDownload(url: url) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            _ = MediaCache.shared.store(data: data, for: url)
        } catch {
            print(" Media cache download failed for \(url): \(error.localizedDescription)")
        }
    }
}
