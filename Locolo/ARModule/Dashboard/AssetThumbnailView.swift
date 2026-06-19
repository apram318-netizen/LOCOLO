//
//  AssetThumbnailView.swift
//  Locolo
//
//  Reusable thumbnail for AR assets. Uses thumb_url first, then renders a
//  cached SceneKit snapshot from the USDZ model so gallery cards never try to
//  show a model file through AsyncImage.
//

import SwiftUI
import SceneKit
import UIKit

struct AssetThumbnailView: View {
    let asset: DigitalAsset
    var cornerRadius: CGFloat = 12

    @State private var generatedImage: UIImage?
    @State private var isGenerating = false
    @State private var shouldGenerateFallback = false

    var body: some View {
        ZStack {
            if let thumbUrl = asset.thumbUrl, let url = URL(string: thumbUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        generatedOrPlaceholder
                            .onAppear { shouldGenerateFallback = true }
                    case .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                generatedOrPlaceholder
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: asset.id) {
            await generateIfNeeded()
        }
        .task(id: shouldGenerateFallback) {
            await generateIfNeeded()
        }
    }

    @MainActor
    private func generateIfNeeded() async {
        guard (asset.thumbUrl == nil || shouldGenerateFallback),
              generatedImage == nil,
              !isGenerating
        else {
            return
        }

        isGenerating = true
        let image = await AssetThumbnailGenerator.thumbnail(for: asset)
        generatedImage = image
        isGenerating = false
    }

    @ViewBuilder
    private var generatedOrPlaceholder: some View {
        if let generatedImage {
            Image(uiImage: generatedImage)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.35),
                    Color.blue.opacity(0.22),
                    Color.black.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 6) {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(.white)
                }
            }
        }
    }

    private var placeholderIcon: String {
        switch asset.mediaType {
        case "audio":
            return "waveform"
        case "video":
            return "play.rectangle.fill"
        default:
            return "arkit"
        }
    }
}

enum AssetThumbnailGenerator {
    static func thumbnail(for asset: DigitalAsset, size: CGSize = CGSize(width: 320, height: 320)) async -> UIImage? {
        if let cached = cachedImage(for: asset.id) {
            return cached
        }

        guard asset.fileType.lowercased() == "usdz",
              let remoteURL = URL(string: asset.fileUrl)
        else {
            return nil
        }

        do {
            let localURL = try await localModelURL(for: asset.id, remoteURL: remoteURL)
            let image = await MainActor.run {
                renderSnapshot(modelURL: localURL, size: size)
            }
            if let image {
                cache(image: image, for: asset.id)
            }
            return image
        } catch {
            print("Asset thumbnail generation failed:", error.localizedDescription)
            return nil
        }
    }

    private static func localModelURL(for assetId: UUID, remoteURL: URL) async throws -> URL {
        let cacheURL = modelCacheURL(for: assetId, remoteURL: remoteURL)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: cacheURL, options: .atomic)
        return cacheURL
    }

    @MainActor
    private static func renderSnapshot(modelURL: URL, size: CGSize) -> UIImage? {
        let scene = SCNScene()

        guard let model = SCNReferenceNode(url: modelURL) else { return nil }
        model.load()

        let container = SCNNode()
        container.addChildNode(model)
        scene.rootNode.addChildNode(container)

        let (center, radius) = model.boundingSphere
        let safeRadius = max(radius, 0.001)
        let scale = Float(1.8 / safeRadius)
        model.scale = SCNVector3(scale, scale, scale)
        model.position = SCNVector3(
            -center.x * scale,
            -center.y * scale,
            -center.z * scale
        )

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 34
        camera.wantsHDR = true
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.1, 5.2)
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 450
        ambient.color = UIColor(white: 0.75, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .omni
        key.intensity = 900
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(2.5, 3.5, 4.5)
        scene.rootNode.addChildNode(keyNode)

        scene.background.contents = UIColor.black

        let view = SCNView(frame: CGRect(origin: .zero, size: size))
        view.scene = scene
        view.backgroundColor = .black
        view.pointOfView = cameraNode
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        return view.snapshot()
    }

    private static func cachedImage(for assetId: UUID) -> UIImage? {
        let url = imageCacheURL(for: assetId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    private static func cache(image: UIImage, for assetId: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: imageCacheURL(for: assetId), options: .atomic)
        } catch {
            print("Asset thumbnail cache write failed:", error.localizedDescription)
        }
    }

    private static func imageCacheURL(for assetId: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(assetId.uuidString)-thumb.jpg")
    }

    private static func modelCacheURL(for assetId: UUID, remoteURL: URL) -> URL {
        let ext = remoteURL.pathExtension.isEmpty ? "usdz" : remoteURL.pathExtension
        return cacheDirectory.appendingPathComponent("\(assetId.uuidString).\(ext)")
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocoloAssetThumbnails", isDirectory: true)
    }
}
