//
//  ARCreateAssetFlowView.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//

import SwiftUI

struct ARCreateAssetFlowView: View {
    @StateObject private var vm = ARCreateViewModel()
    let userId: UUID
    @Binding var selectedTab: Int
    
    var body: some View {
        NavigationStack {
            VStack {
                stepIndicator

                // Always keep ARStepView in the hierarchy; navigate instead of replacing
                FileStepView(vm: vm)
                    .opacity(vm.step == .file ? 1 : 0)
                    .disabled(vm.step != .file)

                NavigationLink(
                    destination: DetailsStepView(
                        vm: vm,
                        saveAction: { Task { await vm.saveAsset(userId: userId) } },
                        selectedTab: $selectedTab
                    ),
                    isActive: .constant(vm.step == .details)
                ) {
                    EmptyView()
                }
                .hidden()

                if vm.step == .ar {
                    ARStepView(vm: vm, selectedStep: $selectedTab)
                        .edgesIgnoringSafeArea(.all)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: Binding(
                get: { vm.error != nil },
                set: { _ in vm.error = nil })
            ) {
                Button("OK") { vm.error = nil }
            } message: {
                Text(vm.error ?? "")
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            stepDot(active: vm.step == .file, text: "File")
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
