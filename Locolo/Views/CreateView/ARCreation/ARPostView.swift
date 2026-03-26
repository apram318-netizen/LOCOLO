//
//  ARPostView.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//

import SwiftUI
import UniformTypeIdentifiers
import RealityKit

struct ARPostView: View {
    @StateObject private var vm = ARCreateViewModel()
    @State private var showFilePicker = false
    @Binding var selectedTab: Int
    @EnvironmentObject var userVM: UserViewModel

    var body: some View {
        NavigationStack(path: $vm.navPath) {
            VStack(spacing: 24) {
                Text("Create AR Asset")
                    .font(.title2.bold())

                // STEP 1: Pick File
                Button {
                    showFilePicker = true
                } label: {
                    Label("Select 3D Model (.usdz or .fbx)", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(12)
                }

                if let file = vm.localFileURL {
                    Text("Selected: \(file.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                // STEP 2: Upload
                if vm.localFileURL != nil {
                    Button {
                        Task { await vm.uploadPickedFileToStorage() }
                    } label: {
                        Label(vm.isBusy ? "Uploading…" : "Upload File", systemImage: "icloud.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(vm.isBusy ? Color.gray.opacity(0.3) : Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(vm.isBusy)
                }

                // STEP 3: Preview in AR
                if let uploaded = vm.uploadedFileURL {
                    NavigationLink(value: "ar") {
                        
                        Label("Preview in AR", systemImage: "arkit")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("AR Creator")
            // File Picker
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [
                    UTType(filenameExtension: "usdz")!,
                    UTType(filenameExtension: "fbx")!
                ],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    vm.setPickedFile(url)
                } catch {
                    print(" File pick failed:", error.localizedDescription)
                }
            }
            // Navigation destinations
            .navigationDestination(for: String.self) { route in
                switch route {
                case "ar":
                    if let modelURL = vm.uploadedFileURL {
                        ARPlacementView(modelURL: modelURL, vm: vm)
                            .edgesIgnoringSafeArea(.all)
                    } else {
                        Text(" Upload a model first.")
                            .font(.headline)
                    }

                case "details":
                    DetailsStepView(
                        vm: vm,
                        saveAction: {
                            Task { await vm.saveAsset(userId: userVM.currentUser?.id ?? UUID()) }
                        },
                        selectedTab: $selectedTab 
                    )

                default:
                    EmptyView()
                }
            }
        }
    }
}

