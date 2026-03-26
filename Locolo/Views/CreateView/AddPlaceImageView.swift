//
//  AddPlaceImageView.swift
//  Locolo
//
//  Created by Apramjot Singh on 8/10/2025.
//


import SwiftUI
import PhotosUI

struct AddPlaceImageView: View {
    @ObservedObject var placeVM: PlaceViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: Selection State
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var uploadError: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // MARK: Preview Section
                imagePreviewSection
                // MARK: Picker Section
                photoPickerButton
                // MARK: Upload Status Section
                uploadStateSection
                Spacer()
                // MARK: Done Button
                doneButton
            }
            .navigationTitle("Add Image / Media")
            .onChange(of: selectedItem) { newItem in
                Task { await handleImageSelection(newItem) }
            }
        }
    }

    // MARK: - Subviews

    private var imagePreviewSection: some View {
        Group {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.pink)
                    Text("No image selected yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var photoPickerButton: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Select Image", systemImage: "photo")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(buttonGradient)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(radius: 3)
        }
        .padding(.horizontal)
    }

    private var buttonGradient: LinearGradient {
        LinearGradient(colors: [.pink, .purple],
                       startPoint: .leading,
                       endPoint: .trailing)
    }

    private var uploadStateSection: some View {
        VStack(spacing: 6) {
            if placeVM.isLoading {
                ProgressView("Uploading...")
                    .tint(.pink)
            }

            if let uploadError {
                Text(uploadError)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }
        }
    }

    private var doneButton: some View {
        let hasImage = placeVM.uploadedMediaUrl != nil

        return Button {
            dismiss()
        } label: {
            Text(hasImage ? "Done ✅" : "Skip for now")
                .bold()
                .frame(maxWidth: .infinity)
                .padding()
                .background(doneButtonBackground(hasImage: hasImage))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    private func doneButtonBackground(hasImage: Bool) -> some View {
        Group {
            if hasImage {
                LinearGradient(colors: [.blue, .purple],
                               startPoint: .leading,
                               endPoint: .trailing)
            } else {
                Color.gray.opacity(0.3)
            }
        }
    }

    // MARK: - Upload Handler

    private func handleImageSelection(_ newItem: PhotosPickerItem?) async {
        uploadError = nil

        guard let data = try? await newItem?.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            await MainActor.run { uploadError = "Failed to load image." }
            return
        }

        await MainActor.run { selectedImage = image }

        // Upload via your view model’s function
        await placeVM.uploadMedia(
            fileData: data,
            fileName: "place_image.jpg",
            contentType: "image/jpeg",
            storeIn: "places"
        )

        if let error = placeVM.errorMessage {
            await MainActor.run { uploadError = "Upload failed: \(error)" }
        }
    }
}