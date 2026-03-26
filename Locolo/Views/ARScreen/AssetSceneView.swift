//
//  AssetSceneView.swift
//  Locolo
//


import Foundation
import SwiftUI
import SceneKit
import UIKit

struct AssetSceneView: UIViewRepresentable {
    let asset: DigitalAsset
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black   // I forced dark mode here because this screen only makes sense black and blends better too
        
        // make my whole scene
        let scene = makeScene()
        view.scene = scene
        
        view.autoenablesDefaultLighting = false  // I decided to do my own lights
        view.allowsCameraControl = false         // user not moving camera, allowing camera was feeling too dizzy
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X
        
        return view
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

//
// MARK: - building the scene
//
extension AssetSceneView {
    
    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        
        // I add everything layer by layer
        addBackdropPlane(to: scene)     // background wall image
        setupCamera(in: scene)          // camera
        addCinematicLights(to: scene)   // small dim lights
        addDeepFog(to: scene)           // distance fog
        addGroundShadow(to: scene)      // fake floor shadow
        addBottomFog(to: scene)         // my fog PNG drifting
        loadModel(into: scene)          // actual asset
        
        return scene
    }
    
    
    // MARK: - background wall
    private func addBackdropPlane(to scene: SCNScene) {
        guard let texture = UIImage(named: "local_bg") else {
            print("missing local_bg")
            return
        }
        
        // big rectangle behind everything
        let plane = SCNPlane(width: 35, height: 22)
        let mat = SCNMaterial()
        
        mat.diffuse.contents = texture
        mat.lightingModel = .constant
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        
        // I darken it a bit to blend better
        mat.multiply.contents = UIColor(white: 0.55, alpha: 1)
        
        plane.materials = [mat]
        
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, 2.3, -14)
        
        scene.rootNode.addChildNode(node)
    }
    
    
    // MARK: - camera
    private func setupCamera(in scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.name = "mainCamera"
        
        let cam = SCNCamera()
        cam.fieldOfView = 36
        cam.zFar = 700
        cam.wantsHDR = true
        cam.exposureOffset = -0.1
        
        // I give some soft blur for depth
        cam.wantsDepthOfField = true
        cam.fStop = 16
        cam.focalBlurRadius = 3
        
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 1.35, 12.5)  // I moved closer
        
        scene.rootNode.addChildNode(cameraNode)
    }
    
    
    // MARK: - lights
    private func addCinematicLights(to scene: SCNScene) {
        // ambient light
        let amb = SCNLight()
        amb.type = .ambient
        amb.color = UIColor(white: 0.10, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)
        
        // key light
        let key = SCNLight()
        key.type = .omni
        key.intensity = 100
        key.color = UIColor(white: 0.88, alpha: 1)
        let keyNode = SCNNode()
        keyNode.position = SCNVector3(3, 3.2, 9)
        scene.rootNode.addChildNode(keyNode)
        
        // back light
        let back = SCNLight()
        back.type = .omni
        back.intensity = 170
        back.color = UIColor(white: 0.32, alpha: 1)
        let backNode = SCNNode()
        backNode.position = SCNVector3(-4, 4.8, -8)
        scene.rootNode.addChildNode(backNode)
        
        // fill light
        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 40
        fill.color = UIColor(white: 0.22, alpha: 1)
        let fillNode = SCNNode()
        fillNode.position = SCNVector3(0, 1.2, 6)
        scene.rootNode.addChildNode(fillNode)
    }
    
    
    // MARK: - built-in SceneKit fog
    private func addDeepFog(to scene: SCNScene) {
        scene.fogStartDistance = 3.5    // fog starts close
        scene.fogEndDistance = 20       // full fog
        scene.fogDensityExponent = 1.55
        
        scene.fogColor = UIColor.black.withAlphaComponent(0.95)
    }
    
    
    // MARK: - fake shadow plane
    private func addGroundShadow(to scene: SCNScene) {
        let plane = SCNPlane(width: 10, height: 10)
        
        let mat = SCNMaterial()
        mat.diffuse.contents = radialShadowImage(size: CGSize(width: 900, height: 900))
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        mat.lightingModel = .constant
        
        plane.materials = [mat]
        
        let node = SCNNode(geometry: plane)
        
        // I move it down and forward
        node.position = SCNVector3(0, -1.5, 2.5)
        node.scale = SCNVector3(1.6, 1.6, 1)
        node.eulerAngles.x = -.pi / 2
        
        scene.rootNode.addChildNode(node)
    }
    
    
    // simple radial shadow
    private func radialShadowImage(size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let ctx = UIGraphicsGetCurrentContext()!
        
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.black.withAlphaComponent(0.24).cgColor,
                UIColor.black.withAlphaComponent(0).cgColor
            ] as CFArray,
            locations: [0, 1]
        )!
        
        let c = CGPoint(x: size.width/2, y: size.height/2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: size.width/2,
                               options: [])
        
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }
    
    
    // MARK: - load model
    private func loadModel(into scene: SCNScene) {
        guard let url = URL(string: asset.fileUrl) else {
            addFallbackCube(to: scene)
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".usdz")
                try data.write(to: temp)
                
                guard let refNode = SCNReferenceNode(url: temp) else {
                    await MainActor.run { addFallbackCube(to: scene) }
                    return
                }
                
                refNode.load()
                
                // get bounds and scale properly
                let (center, radius) = refNode.boundingSphere
                let safeRadius = max(radius, 0.001)
                
                let desired: Float = 1.1
                let scale = desired / safeRadius
                refNode.scale = SCNVector3(scale, scale, scale)
                
                let cent = SCNVector3(center.x * scale,
                                      center.y * scale,
                                      center.z * scale)
                
                // I reposition the model nicely
                let pos = SCNVector3(-cent.x, -cent.y + 1.15, -cent.z)
                
                await MainActor.run {
                    let rot = SCNNode()
                    rot.position = pos
                    scene.rootNode.addChildNode(rot)
                    
                    rot.addChildNode(refNode)
                    animateEntrance(refNode)
                    startRotation(on: rot)
                }
                
            } catch {
                print("load error:", error)
                await MainActor.run { addFallbackCube(to: scene) }
            }
        }
    }
    
    
    // fallback block
    private func addFallbackCube(to scene: SCNScene) {
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.2)
        box.firstMaterial?.diffuse.contents = UIColor.red
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(0, 0.6, 0)
        scene.rootNode.addChildNode(node)
    }
    
    
    // entrance fade + slide
    private func animateEntrance(_ node: SCNNode) {
        node.opacity = 0
        node.position.y -= 0.25
        
        node.runAction(
            .group([
                .fadeIn(duration: 0.9),
                .moveBy(x: 0, y: 0.25, z: 0, duration: 0.9)
            ])
        )
    }
    
    
    // slow rotation
    private func startRotation(on node: SCNNode) {
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 20)
        node.runAction(.repeatForever(spin))
    }
    
    
    // MARK: - bottom drifting fog PNG
    private func addBottomFog(to scene: SCNScene) {
        DispatchQueue.main.async {
            
            guard let fogImg = UIImage(named: "fog_1") else {
                print("missing fog_1")
                return
            }
            
            let fogPlane = SCNPlane(width: 14, height: 5)
            let mat = SCNMaterial()
            
            mat.diffuse.contents = fogImg
            mat.transparency = 0.85
            mat.blendMode = .add
            mat.isDoubleSided = true
            mat.lightingModel = .constant
            mat.writesToDepthBuffer = false
            mat.readsFromDepthBuffer = false
            
            fogPlane.materials = [mat]
            
            let fogNode = SCNNode(geometry: fogPlane)
            fogNode.name = "fogNode"
            
            // I placed fog low and a bit front
            fogNode.position = SCNVector3(0, -1.5, 2.5)
            fogNode.eulerAngles.x = -.pi / 2
            
            scene.rootNode.addChildNode(fogNode)
            
            // left-right drifting animation
            let moveRight = SCNAction.moveBy(x: 0.5, y: 0, z: 0, duration: 5)
            let moveLeft = moveRight.reversed()
            let seq = SCNAction.sequence([moveRight, moveLeft])
            
            fogNode.runAction(.repeatForever(seq))
        }
    }
}


// https://youtu.be/Jr9OduLBd5A?si=-TUzU6tOQ77lxoGW // This tutorial series is nice, however this included a lot of unneccessary things as well and wasnt for the swift UI but still it helped me to grab the scene kit concepts well. It just gets better by video 4 only
// https://developer.apple.com/documentation/scenekit
// https://developer.apple.com/documentation/scenekit/scncamera
// https://developer.apple.com/documentation/scenekit/scnlight Lights are actually documented well and worked too

//No matter my multiple attempts to add fog.. but nothing worked so I just have the code still that it may or may not. Just dont want to break anything by taking it out. these are the discussions I used to get an idea from
// https://developer.apple.com/documentation/scenekit/scnscene/fogenddistance
// https://developer.apple.com/documentation/scenekit/scnscene/fogcolor
// https://developer.apple.com/documentation/ARKit/creating-a-fog-effect-using-scene-depth
// https://stackoverflow.com/questions/61737837/how-can-i-set-fog-in-scenekit-to-follow-a-curve

// This was nice gave me a few more ideas for shadows:
// https://www.youtube.com/watch?v=8z2OKhReD3k



