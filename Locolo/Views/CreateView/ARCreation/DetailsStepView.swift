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
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: Int

    var body: some View {
        Form {
            Section("Info") {
                TextField("Name", text: $vm.name)
                TextField("Description", text: $vm.descriptionText, axis: .vertical)
                    .lineLimit(3...6)
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
        .alert("Asset Uploaded!", isPresented: $vm.showSuccessAlert) {
            Button("Move to AR Screen") {
                selectedTab = 3
                dismiss()
            }
        } message: {
            Text("Your digital asset has been successfully uploaded and is now available in AR.")
        }
    }
}
