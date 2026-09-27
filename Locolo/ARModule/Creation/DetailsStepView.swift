//
//  DetailsStepView.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//


import SwiftUI
import UniformTypeIdentifiers

struct DetailsStepView: View {
    @ObservedObject var vm: ARCreateViewModel
    let saveAction: () -> Void
    let onDone: () -> Void
    @State private var showAddressSheet = false
    @State private var showMediaPicker = false
    @State private var showShareSheet = false

    var body: some View {
        Form {
            Section("Info") {
                TextField("Name", text: $vm.name)
                TextField("Description", text: $vm.descriptionText, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Location") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.address.isEmpty ? "Resolving exact address..." : vm.address)
                            .font(.subheadline)
                            .foregroundStyle(vm.address.isEmpty ? .secondary : .primary)
                        if vm.capturedAltitude != nil {
                            Text("Altitude captured for precise AR placement")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Edit") { showAddressSheet = true }
                        .font(.subheadline)
                }
            }

            if vm.selectedAnimationIndex != nil || vm.localMediaURL != nil {
                Section("Interaction") {
                    TriggerConfigView(vm: vm)
                }
            }

            Section("Audio / Video") {
                if let media = vm.localMediaURL {
                    HStack(spacing: 10) {
                        Image(systemName: vm.mediaType == "video" ? "play.rectangle.fill" : "waveform")
                            .foregroundStyle(vm.mediaType == "video" ? .purple : .pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(media.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(vm.mediaType == "video" ? "MP4/video trigger media" : "Audio trigger media")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove") {
                            vm.clearPickedMediaFile()
                        }
                        .font(.caption)
                    }
                } else {
                    Text("Attach an MP4 or audio clip to play when this asset is triggered.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showMediaPicker = true
                } label: {
                    Label(vm.localMediaURL == nil ? "Add Media" : "Change Media",
                          systemImage: "music.note.list")
                }
            }

            Section {
                Picker("Visibility", selection: $vm.visibility) {
                    Text("Public").tag("public")
                    Text("Private").tag("private")
                    Text("Friends").tag("friends")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Privacy")
            } footer: {
                switch vm.visibility {
                case "private": Text("Only you can see this asset.")
                case "friends": Text("Only people who follow you can see this asset.")
                default:        Text("Anyone exploring nearby can find this asset.")
                }
            }

            Section {
                Button {
                    saveAction()
                } label: {
                    HStack {
                        if vm.isBusy { ProgressView().padding(.trailing, 6) }
                        Text("Upload")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .disabled(vm.isBusy || vm.uploadedFileURL == nil || vm.transform == nil)
            }
        }
        .sheet(isPresented: $showAddressSheet) {
            AddressConfirmationView(vm: vm)
        }
        .fileImporter(
            isPresented: $showMediaPicker,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    vm.setPickedMediaFile(url)
                }
            case .failure(let error):
                vm.error = error.localizedDescription
            }
        }
        .alert("Asset Uploaded!", isPresented: $vm.showSuccessAlert) {
            Button("Back to Gallery") {
                onDone()
            }
            if vm.savedAssetShareURL != nil {
                Button("Share it") {
                    showShareSheet = true
                }
            }
        } message: {
            Text("Your digital asset has been successfully uploaded and is now available in AR.")
        }
        // Post-save share: a locolo:// deep link straight to the new asset. (WS7.4)
        .sheet(isPresented: $showShareSheet, onDismiss: { onDone() }) {
            if let url = vm.savedAssetShareURL {
                ShareSheet(items: [
                    "Check out \"\(vm.savedAssetName)\" in AR on Locolo!",
                    url
                ])
                .presentationDetents([.medium])
            }
        }
    }
}

/// Thin UIKit share-sheet wrapper (ShareLink can't be presented imperatively
/// from an alert action).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
