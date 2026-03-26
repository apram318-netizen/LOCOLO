//
//  FileStepView.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//


import SwiftUI
import UniformTypeIdentifiers

struct FileStepView: View {
    @ObservedObject var vm: ARCreateViewModel
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 16) {
            Label("Upload 3D Asset", systemImage: "square.and.arrow.up.on.square")
                .font(.headline)

            if let url = vm.localFileURL {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(url.lastPathComponent).font(.caption)
                    Spacer()
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text("Choose a .usdz (preferred) or .fbx file from Files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Choose File") { showPicker = true }

            Button("Upload & Continue") {
                Task {
                    await vm.uploadPickedFileToStorage()
                    if vm.uploadedFileURL != nil {
                        // FBX note: can be uploaded, but AR preview requires USDZ
                        if vm.fileType == "usdz" {
                            vm.step = .ar
                        } else {
                            vm.error = "FBX uploaded. To preview in AR, please use a USDZ file."
                            
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.localFileURL == nil || vm.isBusy)

            if vm.isBusy { ProgressView().padding(.top, 8) }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.usdz],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let u = urls.first { vm.setPickedFile(u) }
            case .failure(let err):
                vm.error = err.localizedDescription
            }
        }
    }
}
