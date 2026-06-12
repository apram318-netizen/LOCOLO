//
//  ARCreateAssetFlowView.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//
//  Runs inside the AR dashboard's NavigationStack (pushed via ARRoute.create),
//  so it owns no NavigationStack of its own.

import SwiftUI

struct ARCreateAssetFlowView: View {
    @StateObject private var vm = ARCreateViewModel()
    let userId: UUID
    @EnvironmentObject var dashboardState: ARDashboardState

    var body: some View {
        VStack {
            stepIndicator

            // Always keep FileStepView in the hierarchy; overlay AR placement on top
            FileStepView(vm: vm)
                .opacity(vm.step == .file ? 1 : 0)
                .disabled(vm.step != .file)

            if vm.step == .animations {
                AnimationPickerStepView(vm: vm)
            }

            // Keep the placement view mounted through the details sheet so the
            // AR session isn't torn down mid-flow
            if vm.step == .ar || vm.step == .details {
                ARStepView(vm: vm)
                    .edgesIgnoringSafeArea(.all)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $vm.showDetails) {
            DetailsStepView(
                vm: vm,
                saveAction: { Task { await vm.saveAsset(userId: userId) } },
                onDone: {
                    vm.showDetails = false
                    dashboardState.path.removeAll()
                }
            )
        }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil },
            set: { _ in vm.error = nil })
        ) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            stepDot(active: vm.step == .file, text: "File")
            stepDot(active: vm.step == .animations, text: "Anim")
            stepDot(active: vm.step == .ar, text: "Place")
            stepDot(active: vm.step == .details, text: "Details")
        }
        .padding(.top, 8)
    }

    private func stepDot(active: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? .purple : .gray.opacity(0.3))
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption)
                .foregroundStyle(active ? .primary : .secondary)
        }
    }
}
