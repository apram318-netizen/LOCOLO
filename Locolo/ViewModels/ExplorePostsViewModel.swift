//
//  ExplorePostsViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import Foundation

class ExplorePostsViewModel: ObservableObject {
    
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    @Published var selectedPost: Post?
    @Published var showEchoSheet: Bool = false
    
    private let loopViewModel: LoopViewModel
    private let userVM: UserViewModel
    private let storageManager = ObjStorageManager.shared
    private let repository: PostRepositoryProtocol
    
    // MARK: Init
    /// - Description: Sets up the ExplorePosts view model, linking it to the current user and loop.
    /// Automatically triggers a feed load on init.
    init(loopViewModel: LoopViewModel, userViewModel: UserViewModel, repository: PostRepositoryProtocol = PostsRepository()) {
        self.userVM = userViewModel
        self.loopViewModel = loopViewModel
        self.repository = repository
        loadPosts()
    }
    
    
    // MARK: FUNCTION: createPost
    /// - Description: Handles raw post creation (upload + repo call).
    /// This is a legacy path used by older flows; the new flow uses `CreatePostViewModel`.
    ///
    /// - Parameters:
    ///   - id: Optional post UUID
    ///   - loopId: The loop the post belongs to
    ///   - authorId: The user creating the post
    ///   - caption: Caption text
    ///   - tags: Optional tag list
    ///   - placeId: Optional related place ID
    ///   - visibility: Visibility level (public, private, etc.)
    ///   - fileData: Binary media data
    ///   - fileName: Name of the uploaded file
    ///   - contentType: MIME type (e.g., image/jpeg)
    ///
    /// - Discussion:
    ///   Eventually this can merge into the main post creation flow to remove duplication.
    ///   Upload progress tracking and retry logic can be added here too.
    func createPost(
        id: UUID? = nil,
        loopId: UUID,
        authorId: UUID,
        caption: String,
        tags: [String] = [],
        placeId: UUID? = nil,
        visibility: String,
        fileData: Data,
        fileName: String,
        contentType: String
    ) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let filePath = "posts/\(UUID().uuidString)_\(fileName)"
            
            let mediaUrl = try await storageManager.uploadFile(
                path: filePath,
                fileData: fileData,
                contentType: contentType
            )
            
            let newPost = Post(
                id: id,
                loopId: loopId,
                authorId: authorId,
                caption: caption,
                media: URL(string: mediaUrl),
                tags: tags,
                placeId: placeId,
                visibility: visibility,
                isDeleted: false,
                createdAt: Date(),
                updatedAt: nil,
                author: nil,
                place: nil,
                eventId: nil,
                eventContext: nil
            )
            
            try await repository.createPost(newPost)
            isLoading = false
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                print(" Error creating post: \(error)")
            }
        }
    }
    
    
    
    // MARK: FUNCTION: loadPosts
    /// - Description: Loads posts for the currently active loop.
    /// Uses `PostsRepository` for caching and fetch logic.
    ///
    /// - Discussion:
    ///   • Should eventually include pagination and pull-to-refresh
    ///   • Could also support post filters (e.g., “most hyped” or “recent”)
    ///   • We might later need to integrate personalized or nearby post logic
    func loadPosts() {
        guard let loop = loopViewModel.activeLoop else {
            print("No active loop")
            return
        }
        
        repository.fetchPosts(forLoop: loop.id ?? "") { [weak self] result in
            switch result {
            case .success(let posts):
                DispatchQueue.main.async {
                    self?.posts = posts
                }
            case .failure(let error):
                print("Error fetching posts: \(error)")
            }
        }
    }
    
    
    
    // MARK: FUNCTION: createPostFromUI
    /// - Description: Simplified entry point for creating a post from the UI layer.
    /// uses the data from all the 3 view models and tries to combine them together `LoopViewModel` and `UserViewModel` before calling `createPost`.
    ///
    /// - Parameters:
    ///   - caption: Caption text for the post
    ///   - tags: Optional tag list
    ///   - placeId: Optional related place ID
    ///   - visibility: Post visibility level
    ///   - fileData: Uploaded media data
    ///   - fileName: Media file name
    ///   - contentType: File MIME type
    ///
    /// - Discussion:
    ///   This function is here for backward compatibility with older UI code.
    ///   Majorly getting everyuthinbg to createpost view model.. will delete the function after the transition
    func createPostFromUI(
        caption: String,
        tags: [String],
        placeId: UUID? = nil,
        visibility: Visibility,
        fileData: Data,
        fileName: String,
        contentType: String
    ) async {
        guard let loop = loopViewModel.activeLoop,
              let loopIdString = loop.id,
              let loopUUID = UUID(uuidString: loopIdString),
              let author = await userVM.currentUser else {
            await MainActor.run {
                errorMessage = " No active loop or logged-in user."
            }
            return
        }
        
        await createPost(
            loopId: loopUUID,
            authorId: author.id,
            caption: caption,
            tags: tags,
            placeId: placeId,
            visibility: visibility.rawValue,
            fileData: fileData,
            fileName: fileName,
            contentType: contentType
        )
    }
    
    
    
}
