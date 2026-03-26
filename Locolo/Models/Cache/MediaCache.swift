//
//  MediaCache.swift
//  Locolo
//
//  Created by Apramjot Singh on 10/11/2025.
//

import Foundation
import CryptoKit

final class MediaCache {
    static let shared = MediaCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = base.appendingPathComponent("LocoloMediaCache", isDirectory: true)
        createDirectoryIfNeeded()
    }

    
    //MARK: - FUNCTION: localURL
    /// - Description: This function  just takes in the remore URLand gives the remote URL if it exists in cache.
    /// - Parameters: remoteURL: URL - The remote URL of the media file.
    ///  - Returns: URL? - The local URL of the cached media file if it exists or nil.
    func localURL(forRemoteURL remoteURL: URL) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent(key(for: remoteURL))
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    

   //MARK: - FUNCTION: store
    /// - Description: This function stores the given data in the cache directory with a filename derived from the remote URL.
    /// - Parameters: data: Data - The data to be stored.
    /// - Returns: URL? - The local URL of the cached media file if successful or nil.
    func store(data: Data, for remoteURL: URL, fileExtension: String? = nil) -> URL? {
        let key = key(for: remoteURL, customExtension: fileExtension ?? remoteURL.pathExtension)
        let destination = cacheDirectory.appendingPathComponent(key)
        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            print(" MediaCache write error:", error)
            return nil
        }
    }
    

    
    // MARK: - FUNCTION: storeFile
    /// - Description: This function stores the file located at sourceURL in the cache storage with a filenam that is takenfrom the remote URL.
    /// - Parameters: The sourceURL: URL - the url of the source we get it from - remoteURL: URL - The remote URL of the media file.
    /// - Returns: URL? - The local URL of the recently cached media file if successful or nil.
    func storeFile(from sourceURL: URL, for remoteURL: URL) -> URL? {
        do {
            let data = try Data(contentsOf: sourceURL)
            return store(data: data, for: remoteURL, fileExtension: sourceURL.pathExtension)
        } catch {
            print(" MediaCache copy error:", error)
            return nil
        }
    }
    
    

    // MARK: - FUNCTION: Remove
    /// - Description: This function removes the cached file for a remote url
    /// - Parameters: remoteURL: URL - its just a remote URL
    /// - Returns: Nothing
    func remove(for remoteURL: URL) {
        guard let local = localURL(forRemoteURL: remoteURL) else { return }
        try? fileManager.removeItem(at: local)
    }
    
    // MARK: - FUNCTION: Clear
    /// - Description:This just clears the cache in future I iwll use it to load different posts and refresh.
    func clear() {
        try? fileManager.removeItem(at: cacheDirectory)
        createDirectoryIfNeeded()
    }

    // MARK: - Helpers

    private func createDirectoryIfNeeded() {
        guard !fileManager.fileExists(atPath: cacheDirectory.path) else { return }
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func key(for remoteURL: URL, customExtension: String? = nil) -> String {
        let hash = SHA256.hash(data: Data(remoteURL.absoluteString.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        if let ext = customExtension, !ext.isEmpty {
            return "\(hash).\(ext)"
        }
        return hash
    }
}

