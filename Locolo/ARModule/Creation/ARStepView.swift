//
//  ARStepView.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//



import SwiftUI
import RealityKit

struct ARStepView: View {
    @ObservedObject var vm: ARCreateViewModel

    var body: some View {
        // MARK: AR Placement View
        ZStack(alignment: .bottom) {
            if let modelURL = vm.uploadedFileURL {
                ARPlacementView(modelURL: modelURL, vm: vm)   // ← pass vm
                    .id("arPlacement")                        // keep stable
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text(" No model URL found").foregroundColor(.red)
            }

            Text("Move/rotate/scale the model, then tap & hold to confirm")
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 16)
        }
    }
}
