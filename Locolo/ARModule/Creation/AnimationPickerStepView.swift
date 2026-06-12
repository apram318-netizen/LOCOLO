//
//  AnimationPickerStepView.swift
//  Locolo
//
//  Step between File and Place: shown only when the picked USDZ contains
//  embedded animations. The poster previews them and picks the one that
//  plays when the asset's trigger fires in AR.
//

import SwiftUI

struct AnimationPickerStepView: View {
    @ObservedObject var vm: ARCreateViewModel

    var body: some View {
        VStack(spacing: 16) {
            Label("Choose an Animation", systemImage: "play.circle")
                .font(.headline)

            AnimationPreviewView(vm: vm)
                .frame(height: 280)
                .background(.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

            List {
                Button {
                    vm.selectedAnimationIndex = nil
                } label: {
                    row(title: "None (static)", selected: vm.selectedAnimationIndex == nil)
                }

                ForEach(vm.availableAnimations.indices, id: \.self) { index in
                    Button {
                        vm.selectedAnimationIndex = index
                    } label: {
                        row(title: vm.availableAnimations[index],
                            selected: vm.selectedAnimationIndex == index)
                    }
                }
            }
            .listStyle(.plain)

            Button("Continue to Placement") {
                vm.step = .ar
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 8)
        }
    }

    private func row(title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.purple)
            }
        }
    }
}
