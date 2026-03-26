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
    @EnvironmentObject var userVM: UserViewModel
    @Binding var selectedStep: Int

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
        .sheet(isPresented: $vm.showDetails) {
            DetailsStepView(
                vm: vm,
                saveAction: {
                    Task {
                        do {
                            let userId = userVM.currentUser?.id ?? UUID()
                            print(" Starting saveAsset for user:", userId)
                            try await vm.saveAsset(userId: userId)
                            print(" saveAsset completed successfully")
                        } catch {
                            print(" saveAsset threw error:", error.localizedDescription)
                            await MainActor.run {
                                vm.error = "Save failed: \(error.localizedDescription)"
                            }
                        }
                    }
                },
                selectedTab: $selectedStep
            )
        }
    }
}

