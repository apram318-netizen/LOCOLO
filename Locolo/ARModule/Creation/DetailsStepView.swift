//
//  DetailsStepView.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//


import SwiftUI

struct DetailsStepView: View {
    @ObservedObject var vm: ARCreateViewModel
    let saveAction: () -> Void
    let onDone: () -> Void
    @State private var showAddressSheet = false

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

            if vm.selectedAnimationIndex != nil {
                Section("Interaction") {
                    TriggerConfigView(vm: vm)
                }
            }

            Section("Privacy") {
                Picker("Visibility", selection: $vm.visibility) {
                    Text("Public").tag("public")
                    Text("Private").tag("private")
                    Text("Friends").tag("friends")
                }
                .pickerStyle(.segmented)
                Toggle("Also make this a post", isOn: $vm.alsoMakePost)
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
        .alert("Asset Uploaded!", isPresented: $vm.showSuccessAlert) {
            Button("Back to Gallery") {
                onDone()
            }
        } message: {
            Text("Your digital asset has been successfully uploaded and is now available in AR.")
        }
    }
}
