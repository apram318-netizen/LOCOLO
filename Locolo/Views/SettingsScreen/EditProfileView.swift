//
//  EditProfileView.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/11/2025.
//


import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) private var dismiss
    
    // MARK: Form State
    // State for editing user profile information
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var avatarImageUrl: URL?
    
    // MARK: Upload State
    // State for image upload and form submission
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false
    
    private let storageManager = ObjStorageManager.shared
    
    var body: some View {
        Form {
            // MARK: Avatar Section
            // Section for uploading and previewing avatar image
            Section {
                VStack(spacing: 16) {
                    // Avatar preview
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.purple, lineWidth: 3))
                    } else if let avatarUrl = avatarImageUrl ?? userVM.currentUser?.avatarUrl {
                        AsyncImage(url: avatarUrl) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 60))
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.purple, lineWidth: 3))
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                            )
                            .overlay(Circle().stroke(Color.purple, lineWidth: 3))
                    }
                    
                    // Photo picker button
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(selectedImage == nil && avatarImageUrl == nil && userVM.currentUser?.avatarUrl == nil ? "Add Avatar" : "Change Avatar", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    
                    if isUploading {
                        ProgressView("Uploading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } header: {
                Text("Profile Picture")
            }
            
            // MARK: Username Section
            // Section for editing username
            Section {
                TextField("Username", text: $username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            } header: {
                Text("Username")
            } footer: {
                Text("Your username is how others will find you on Locolo.")
            }
            
            // MARK: Bio Section
            // Section for editing bio
            Section {
                TextEditor(text: $bio)
                    .frame(minHeight: 100)
            } header: {
                Text("Bio")
            } footer: {
                Text("Tell others a little about yourself.")
            }
            
            // MARK: Save Button Section
            // Section with save button
            Section {
                Button {
                    Task {
                        await saveProfile()
                    }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("Save Changes")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .disabled(isSaving || isUploading || !hasChanges())
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCurrentProfile()
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                await handleImageSelection(newItem)
            }
        }
        .alert("Profile Updated!", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your profile has been successfully updated.")
        }
    }
    
    // MARK: - Load Current Profile
    // Loads existing user profile data into form fields
    private func loadCurrentProfile() {
        guard let user = userVM.currentUser else { return }
        username = user.username
        bio = user.bio ?? ""
        avatarImageUrl = user.avatarUrl
    }
    
    // MARK: - Handle Image Selection
    // Handles avatar image selection and upload with compression to 0.3 MB
    private func handleImageSelection(_ newItem: PhotosPickerItem?) async {
        guard let item = newItem else { return }
        
        do {
            // Load image data
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    errorMessage = "Failed to load image."
                }
                return
            }
            
            await MainActor.run {
                selectedImage = image
                errorMessage = nil
                isUploading = true
            }
            
            // Target: ≤ 0.3 MB (300 KB)
            let maxFileSize: Int = 300 * 1024
            
            // Start at decent quality and shrink as needed
            var compression: CGFloat = 0.8
            var imageData = image.jpegData(compressionQuality: compression)
            
            // If image too large, keep scaling down quality until under 0.3 MB
            while let data = imageData, data.count > maxFileSize, compression > 0.1 {
                compression -= 0.1
                imageData = image.jpegData(compressionQuality: compression)
            }
            
            // If still too large (e.g. very high-resolution image), scale down dimensions
            if let data = imageData, data.count > maxFileSize {
                // Resize to max 800x800 for avatars (maintains aspect ratio)
                let maxDimension: CGFloat = 800
                let scale: CGFloat
                
                if image.size.width > image.size.height {
                    scale = min(maxDimension / image.size.width, 1.0)
                } else {
                    scale = min(maxDimension / image.size.height, 1.0)
                }
                
                let newSize = CGSize(
                    width: image.size.width * scale,
                    height: image.size.height * scale
                )
                
                let renderer = UIGraphicsImageRenderer(size: newSize)
                let resized = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
                
                // Re-compress resized image
                imageData = resized.jpegData(compressionQuality: 0.6)
            }
            
            guard let compressedData = imageData else {
                await MainActor.run {
                    errorMessage = "Failed to process image."
                    isUploading = false
                }
                return
            }
            
            // Upload to storage
            let fileName = "\(UUID().uuidString).jpg"
            let filePath = "avatars/\(fileName)"
            
            let urlString = try await storageManager.uploadFile(
                path: filePath,
                fileData: compressedData,
                contentType: "image/jpeg"
            )
            
            guard let url = URL(string: urlString) else {
                await MainActor.run {
                    errorMessage = "Failed to get image URL."
                    isUploading = false
                }
                return
            }
            
            await MainActor.run {
                avatarImageUrl = url
                isUploading = false
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to upload image: \(error.localizedDescription)"
                isUploading = false
            }
        }
    }
    
    
    
    // MARK: - Check for Changes
    // Returns true if any profile fields have been modified
    private func hasChanges() -> Bool {
        guard let user = userVM.currentUser else { return false }
        
        let usernameChanged = username != user.username
        let bioChanged = bio != (user.bio ?? "")
        let avatarChanged = avatarImageUrl != user.avatarUrl
        
        return usernameChanged || bioChanged || avatarChanged
    }
    
    
    
    // MARK: - Save Profile
    // Saves all profile changes to the database
    private func saveProfile() async {
        guard let user = userVM.currentUser else {
            await MainActor.run {
                errorMessage = "User not found."
            }
            return
        }
        
        await MainActor.run {
            isSaving = true
            errorMessage = nil
        }
        
        // Validate username
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                errorMessage = "Username cannot be empty."
                isSaving = false
            }
            return
        }
        
        // Create updated user object
        let updatedUser = User(
            id: user.id,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            email: user.email,
            name: user.name,
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bio.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarUrl: avatarImageUrl,
            coverUrl: user.coverUrl,
            joinedAt: user.joinedAt,
            verifiedFlags: user.verifiedFlags,
            stats: user.stats
        )
        
        // Update profile
        await userVM.updateProfile(updatedUser)
        
        await MainActor.run {
            isSaving = false
            
            if userVM.errorMessage != nil {
                errorMessage = userVM.errorMessage
            } else {
                showSuccessAlert = true
            }
        }
    }
}
