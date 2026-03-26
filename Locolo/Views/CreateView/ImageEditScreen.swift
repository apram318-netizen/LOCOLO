//
//  ImageEditScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 7/10/2025.
//

import SwiftUI



struct ImageEditScreen: View {
    @ObservedObject var vm: ImageEditViewModel
    let onSave: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // MARK: Preview Section
            Image(uiImage: vm.editedImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 400)
                .cornerRadius(16)
                .shadow(radius: 5)
                .padding(.horizontal)
            
            // MARK: Edit Controls Section
            VStack(spacing: 16) {
                slider("Brightness", value: $vm.brightness, range: -0.5...0.5)
                slider("Contrast", value: $vm.contrast, range: 0.5...2.0)
                slider("Saturation", value: $vm.saturation, range: 0.0...2.0)
                slider("Exposure", value: $vm.exposure, range: -1.0...1.0)
            }
            .onChange(of: vm.brightness) { _ in vm.applyFilters() }
            .onChange(of: vm.contrast) { _ in vm.applyFilters() }
            .onChange(of: vm.saturation) { _ in vm.applyFilters() }
            .onChange(of: vm.exposure) { _ in vm.applyFilters() }
            
            Spacer()
            
            // MARK: Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                
                Button("Save ✨") {
                    onSave(vm.editedImage)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .navigationTitle("Edit Image")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label).font(.caption).bold()
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
        }
        .padding(.horizontal)
    }
}
