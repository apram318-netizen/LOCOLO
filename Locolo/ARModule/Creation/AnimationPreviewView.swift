//
//  AnimationPreviewView.swift
//  Locolo
//
//  Non-AR RealityKit preview of the picked model, playing whichever
//  animation is currently selected. Uses RealityKit (not SceneKit) so the
//  animation indices shown here match exactly what plays in the AR session.
//

import SwiftUI
import RealityKit

struct AnimationPreviewView: UIViewRepresentable {
    @ObservedObject var vm: ARCreateViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.black)

        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)

        if let entity = vm.previewEntity {
            // Frame the model: center it and pull the camera back based on its size
            let bounds = entity.visualBounds(relativeTo: nil)
            let size = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            entity.position = -bounds.center
            anchor.addChild(entity)

            let camera = PerspectiveCamera()
            camera.position = [0, size * 0.3, max(size * 2, 0.5)]
            camera.look(at: .zero, from: camera.position, relativeTo: nil)
            anchor.addChild(camera)
        }

        playSelectedAnimation()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        playSelectedAnimation()
    }

    private func playSelectedAnimation() {
        guard let entity = vm.previewEntity else { return }
        entity.stopAllAnimations()
        if let index = vm.selectedAnimationIndex,
           entity.availableAnimations.indices.contains(index) {
            entity.playAnimation(entity.availableAnimations[index].repeat())
        }
    }
}
