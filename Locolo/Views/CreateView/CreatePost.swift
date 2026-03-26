//
//  CreatePost.swift
//  Locolo
//
//  Created by Apramjot Singh on 18/9/2025.
//



import SwiftUI
import PhotosUI
import CoreLocation

struct CreatePostView: View {
    
    
    // TODO(LOCOLO): Splitting of the create post view into multiple navigaible screens | Status: Uncompleted

    
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var postsVM: ExplorePostsViewModel
    @EnvironmentObject var placeVM: PlaceViewModel
    @EnvironmentObject var usersVM: UserViewModel
    
    // MARK: Image Selection State
    // Stores the selected image and PhotosPicker item for choosing photos from library
    @State private var selectedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    
    // MARK: Place Details State
    // Form fields for place name, address, category, and description
    @State private var locationName: String = ""
    @State private var address: String = ""
    @State private var selectedCategory: String?
    @State private var description: String = ""
    
    // MARK: Post Settings State
    // Privacy settings, hype toggle, and tag management for the post
    @State private var visibility: Visibility = .everyone
    @State private var allowHypes: Bool = true
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    
    @State private var isLoading = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Image Picker Section
                // Shows selected image or placeholder picker button for choosing photos
                VStack {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .cornerRadius(12)
                            .clipped()
                    } else {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            VStack {
                                Image(systemName: "camera")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("Add photos of the place")
                                    .foregroundColor(.gray)
                            }
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    .foregroundColor(.gray.opacity(0.4))
                            )
                        }
                    }
                }
                .onChange(of: photoItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            selectedImage = uiImage
                        }
                    }
                }
                // MARK: Place Details Section
                // Input fields for location name, address, and category selection
                Group {
                    Text("Place Details")
                        .font(.headline)
                    
                    TextField("e.g., The Coffee Bean", text: $locationName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("123 Main St, City, State", text: $address)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Picker("Category", selection: $selectedCategory) {
                        Text("Select category").tag(nil as String?)
                        Text("Restaurant").tag("restaurant")
                        Text("Café").tag("cafe")
                        Text("Gym").tag("gym")
                        Text("Sightseeing").tag("sightseeing")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                // MARK: Description Section
                // Text editor for post description and caption
                VStack(alignment: .leading) {
                    Text("Description").font(.headline)
                    TextEditor(text: $description)
                        .frame(height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
                }
                // MARK: Privacy Settings Section
                // Controls who can see the post and whether hypes are allowed
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy & Sharing").font(.headline)
                    
                    Picker("Who can see this post?", selection: $visibility) {
                        ForEach(Visibility.allCases, id: \.self) { vis in
                            Text(vis.rawValue.capitalized).tag(vis)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Toggle("Allow hypes", isOn: $allowHypes)
                }
                // MARK: Tags Section
                // Tag input field and horizontal scrolling list of added tags
                VStack(alignment: .leading) {
                    Text("Tags").font(.headline)
                    HStack {
                        TextField("Add a tag", text: $newTag)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("Add") {
                            if !newTag.isEmpty {
                                tags.append(newTag)
                                newTag = ""
                            }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                // MARK: Submit Button Section
                // Shows loading spinner during upload or submit button when ready
                if isLoading {
                    ProgressView("Uploading…")
                        .frame(maxWidth: .infinity)
                } else {
                    Button(action: sharePlace) {
                        Text("Share Place")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LinearGradient(colors: [.blue, .purple],
                                                       startPoint: .leading,
                                                       endPoint: .trailing))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
    }
    // MARK: Post Creation Logic
    // Handles image compression and calls view model to create post in backend
    private func sharePlace() {
        guard let selectedImage = selectedImage,
              let fileData = selectedImage.jpegData(compressionQuality: 0.3) else {
            print(" No image selected")
            return
        }
        
        Task {
            isLoading = true
            await postsVM.createPostFromUI(
                caption: description,
                tags: tags,
                placeId: nil,
                visibility: visibility,
                fileData: fileData,
                fileName: "upload.jpg",
                contentType: "image/jpeg"
            )
            isLoading = false
        }
    }
}

//// Come back and work on:
///Storing user ID: After authenticating a user
///Setting up and updating the current loop
///Adding the functionality to search places by name
///Search the categories
///Store images and create posts

// MARK: - Privacy Enum
enum Visibility: String, CaseIterable {
    case everyone
    case locos
    case exploros
    case sojos
}





