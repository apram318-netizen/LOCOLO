//
//  PanoramaSceneView.swift
//  Locolo
//
//  Created by Apramjot Singh on 6/11/2025.
//

import SwiftUI
import SceneKit
import UIKit
import CoreImage

struct PanoramaSceneView: UIViewRepresentable {
    let asset: DigitalAsset

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = .black

        let scene = SCNScene()

        // MARK: - Camera setup (slightly zoomed-in)
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 85 // zoomed in a little for focus
        cameraNode.position = SCNVector3(0, 0, 15)
        scene.rootNode.addChildNode(cameraNode)

        let targetNode = SCNNode()
        targetNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(targetNode)
        cameraNode.constraints = [SCNLookAtConstraint(target: targetNode)]

        // MARK: - Panorama sphere
        let sphere = SCNSphere(radius: 50)
        sphere.firstMaterial?.isDoubleSided = true
        sphere.firstMaterial?.lightingModel = .constant
        sphere.firstMaterial?.diffuse.wrapS = .repeat
        sphere.firstMaterial?.diffuse.wrapT = .clamp
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.scale = SCNVector3(-1, 1, 1)
        scene.rootNode.addChildNode(sphereNode)

        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true

        scnView.gestureRecognizers?.removeAll(where: { gesture in
            gesture is UITapGestureRecognizer && (gesture as! UITapGestureRecognizer).numberOfTapsRequired == 2
        })
        // MARK: - Load panorama + asset
        Task {
            if let stitchedImage = await fetchAndStitchPanorama(lat: asset.latitude ?? 0.0,
                                                                lng: asset.longitude ?? 0.0) {
                sphere.firstMaterial?.diffuse.contents = stitchedImage
            } else {
                sphere.firstMaterial?.diffuse.contents = UIColor.darkGray
            }

            await spawnObject(in: scene, from: asset)
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - Panorama stitching with blurred poles
    private func fetchAndStitchPanorama(lat: Double, lng: Double) async -> UIImage? {
        let apiKey = keys.googleAPIKey
        let headings = [0, 90, 180, 270]
        var tiles: [UIImage] = []

        //  Fetch 4 panoramas
        for heading in headings {
            guard
                let url = URL(string:
                    "https://maps.googleapis.com/maps/api/streetview?size=1024x1024"
                    + "&location=\(lat),\(lng)"
                    + "&fov=90"
                    + "&heading=\(heading)"
                    + "&pitch=0"
                    + "&key=\(apiKey)"),
                let (data, _) = try? await URLSession.shared.data(from: url),
                let img = UIImage(data: data)
            else { continue }
            tiles.append(img)
        }

        guard !tiles.isEmpty else { return nil }

        //  Build stitched horizon strip
        let totalW = tiles.reduce(0) { $0 + Int($1.size.width) }
        let height = Int(tiles.first!.size.height)
        UIGraphicsBeginImageContextWithOptions(CGSize(width: CGFloat(totalW), height: CGFloat(height)), true, 1.0)
        UIColor.black.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: CGSize(width: CGFloat(totalW), height: CGFloat(height)))).fill()

        var xOffset: CGFloat = 0
        for img in tiles {
            img.draw(in: CGRect(x: xOffset, y: 0, width: img.size.width, height: img.size.height))
            xOffset += img.size.width
        }
        let horizonStrip = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let horizonStrip = horizonStrip else { return nil }

        //  Extract & blur top/bottom strips
        let cropFraction: CGFloat = 0.25
        let tileW = tiles.first!.size.width
        let tileH = tiles.first!.size.height
        let topRect = CGRect(x: 0, y: 0, width: tileW, height: tileH * cropFraction)
        let bottomRect = CGRect(x: 0, y: tileH * (1 - cropFraction), width: tileW, height: tileH * cropFraction)

        var topSlices: [UIImage] = []
        var bottomSlices: [UIImage] = []

        for img in tiles {
            guard let cg = img.cgImage else { continue }

            if let top = cg.cropping(to: topRect.scaled(to: img.scale)) {
                topSlices.append(UIImage(cgImage: top, scale: img.scale, orientation: img.imageOrientation))
            }
            if let bottom = cg.cropping(to: bottomRect.scaled(to: img.scale)) {
                bottomSlices.append(UIImage(cgImage: bottom, scale: img.scale, orientation: img.imageOrientation))
            }
        }

        func stitch(_ imgs: [UIImage]) -> UIImage? {
            guard !imgs.isEmpty else { return nil }
            let w = imgs.reduce(0) { $0 + Int($1.size.width) }
            let h = Int(imgs.first!.size.height)
            UIGraphicsBeginImageContext(CGSize(width: CGFloat(w), height: CGFloat(h)))
            var x: CGFloat = 0
            for img in imgs {
                img.draw(in: CGRect(x: x, y: 0, width: img.size.width, height: img.size.height))
                x += img.size.width
            }
            let result = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return result
        }

        var topStrip = stitch(topSlices)
        var bottomStrip = stitch(bottomSlices)

        // Apply Gaussian blur for smooth blending
        
        func blur(_ image: UIImage?, radius: Double) -> UIImage? {
            guard
                let image = image,
                let ci = CIImage(image: image)
            else { return image }
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = ci
            filter.radius = Float(radius)
            let ctx = CIContext()
            guard let output = filter.outputImage,
                  let cg = ctx.createCGImage(output, from: ci.extent)
            else { return image }
            return UIImage(cgImage: cg)
        }

        topStrip = blur(topStrip, radius: 15)
        bottomStrip = blur(bottomStrip, radius: 15)

        //  Combine all layers
        let topH = Int(topStrip?.size.height ?? 0)
        let bottomH = Int(bottomStrip?.size.height ?? 0)
        let finalH = topH + height + bottomH
        UIGraphicsBeginImageContext(CGSize(width: CGFloat(totalW), height: CGFloat(finalH)))
        UIColor.black.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: CGSize(width: CGFloat(totalW), height: CGFloat(finalH)))).fill()

        if let topStrip = topStrip {
            topStrip.draw(in: CGRect(x: 0, y: 0, width: topStrip.size.width, height: topStrip.size.height))
        }
        horizonStrip.draw(in: CGRect(x: 0, y: CGFloat(topH), width: horizonStrip.size.width, height: horizonStrip.size.height))
        if let bottomStrip = bottomStrip {
            bottomStrip.draw(in: CGRect(x: 0, y: CGFloat(topH + height),
                                        width: bottomStrip.size.width, height: bottomStrip.size.height))
        }

        let final = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return final
    }

    // MARK: - Object spawn logic
    private func spawnObject(in scene: SCNScene, from asset: DigitalAsset) async {
        let urlString = asset.fileUrl
        let modelURL = URL(string: urlString) ?? URL(string: "https://developer.apple.com/augmented-reality/quick-look/models/teapot/teapot.usdz")
        

        do {
            let (data, _) = try await URLSession.shared.data(from: modelURL! )
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
            try data.write(to: tmpURL)

            if let refNode = SCNReferenceNode(url: tmpURL) {
                refNode.load()
                refNode.position = SCNVector3(0, 0, 0)
                refNode.scale = SCNVector3(0.1, 0.1, 0.1)
                await MainActor.run {
                    scene.rootNode.addChildNode(refNode)
                }
            } else {
                await addFallbackNode(to: scene)
            }
        } catch {
            print(" Failed to load model from \(modelURL): \(error)")
            await addFallbackNode(to: scene)
        }
    }

    // MARK: - Fallback cube
    private func addFallbackNode(to scene: SCNScene) async {
        let fallback = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.1)
        fallback.firstMaterial?.diffuse.contents = UIColor.red
        let node = SCNNode(geometry: fallback)
        node.position = SCNVector3(0, 0, 0)
        await MainActor.run {
            scene.rootNode.addChildNode(node)
        }
    }
}

// helper for scaling crop rects
private extension CGRect {
    func scaled(to scale: CGFloat) -> CGRect {
        CGRect(x: origin.x * scale, y: origin.y * scale,
               width: size.width * scale, height: size.height * scale)
    }
}

