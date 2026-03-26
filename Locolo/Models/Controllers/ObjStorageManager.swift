//
//  ObjStorageManager.swift
//  Locolo
//
//  Created by Apramjot Singh on 19/9/2025.
//


import Foundation
import Supabase
import UIKit

class ObjStorageManager {
    static let shared = ObjStorageManager()
    private let client = SupabaseManager.shared.client
    
    // MARK: FUNCTION: Upload File
    /// - Description: adds the file to the supabase storage and returns the URL to the same
    ///
    /// Thiis one is more catered for media bucket for now which stores the posts, if youre trying to upload to another bucket using this then you may get errors
    ///
    /// - Parameter bucket :the storage bucket to upload to
    /// - Parameter path: The path to store it to
    /// - Parameter fileData: of the file you want to upload
    /// - Parameter contentType: A string type that tells the type of its file
    /// - Returns : returns a string with a url of the image
    func uploadFile( bucket: String = "media",path: String,fileData: Data, contentType: String = "application/octet-stream" ) async throws -> String {
        try await client.storage
               .from(bucket)
               .upload(
                 path ,
                 data: fileData,
                 options: FileOptions(contentType: contentType)
               )
        
        let publicURL = try client.storage
                .from(bucket)
                .getPublicURL(path: path)
                .absoluteString
                
        return publicURL
    }
    
    
    
    // MARK: FUNCTION: Upload place image
    /// - Description: adds the file to the supabase storage and returns the URL to the same
    ///
    /// Thiis one is only catered for place bucket for now which stores the images of the place, if youre trying to upload to another bucket using this then you may get errors
    ///this  also compresses the image to a quality of 0.3
    ///
    /// - Parameter image: image you want to upload
    /// - Parameter fileName: Name of the file that youre uplloading
    /// - Returns : returns a string with a url of the image
    func uploadPlaceImage(_ image: UIImage, fileName: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.3) else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not encode image"])
        }
        
        let path = "places/\(fileName).jpg"
        
        // Upload to storage
        try await client.storage
            .from("places")
            .upload(path: path, file: data, options: FileOptions(contentType: "image/jpeg"))
        
        // Get public URL
        
        let url = try client.storage
            .from("places")
            .getPublicURL(path: path)
        
        return url.absoluteString
    }
    
    
}
