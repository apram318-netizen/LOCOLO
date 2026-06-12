//
//  AddressConfirmationView.swift
//  Locolo
//
//  Sheet shown from DetailsStepView so the poster can confirm or correct
//  the exact street address attached to their AR asset.
//

import SwiftUI
import CoreLocation

struct AddressConfirmationView: View {
    @ObservedObject var vm: ARCreateViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedAddress: String = ""
    @State private var searchQuery: String = ""
    @State private var results: [ResolvedAddress] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Exact address") {
                    TextField("Street address", text: $editedAddress, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Search nearby") {
                    HStack {
                        TextField("Search for an address...", text: $searchQuery)
                            .onSubmit { Task { await search() } }
                        if isSearching {
                            ProgressView()
                        } else {
                            Button {
                                Task { await search() }
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .disabled(searchQuery.isEmpty)
                        }
                    }

                    ForEach(results.indices, id: \.self) { i in
                        Button {
                            editedAddress = results[i].formatted
                        } label: {
                            Text(results[i].formatted)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Confirm Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        vm.address = editedAddress
                        dismiss()
                    }
                    .disabled(editedAddress.isEmpty)
                }
            }
            .onAppear { editedAddress = vm.address }
        }
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }
        results = await AddressService.shared.searchAddresses(
            query: searchQuery,
            near: vm.location
        )
    }
}
