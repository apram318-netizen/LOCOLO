//
//  CreateOfferView.swift
//  Locolo
//
//  Created by Apramjot Singh on 9/11/2025.
//
//  - This screen lets the user enter an offer amount for a digital asset.
//  - It also shows the current highest offer so users can compare their bid.
//  - Offers are submitted through the OfferViewModel, with basic validation.
//  - The view dismisses itself when the offer is successfully created.
//

import SwiftUI

struct CreateOfferView: View {
    let assetId: UUID
    
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = OfferViewModel()
    
    @State private var priceText = ""
    
    var body: some View {
        NavigationStack {
            
            // MARK: - Main Form
            // The form holds the offer input, highest offer display, and submit controls.
            Form {
                
                // MARK: Offer Input Section
                // Allows the user to type an offer and shows the highest recorded offer if available.
                Section {
                    HStack {
                        Text("Your offer")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    if let highest = vm.highestOffer {
                        HStack {
                            Label("Highest Offer", systemImage: "chart.line.uptrend.xyaxis")
                            Spacer()
                            Text("$\(highest, specifier: "%.2f")")
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    // MARK: Footer Message
                    // Displays either an error message or a short helpful note.
                    if let err = vm.errorMessage {
                        Text(err).foregroundColor(.red)
                    } else {
                        Text("If the owner accepts your offer, you will be notified to finish checkout.")
                    }
                }
                
                
                // MARK: Submit Button Section
                // Sends the offer to the backend and handles the loading state.
                Section {
                    Button {
                        submit()
                    } label: {
                        if vm.isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Submit Offer").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(vm.isSubmitting)
                }
            }
            .navigationTitle("Make Offer")
            
            
            // MARK: - Toolbar
            // A simple cancel button for dismissing the screen.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            
            
            // MARK: - Load highest offer
            // Fetches the highest offer when the screen appears.
            .task {
                await vm.loadHighestOffer(for: assetId)
            }
        }
    }
    
    
    // MARK: - Submit Handler
    // Validates the number input, calls the view model, and closes when successful.
    private func submit() {
        guard let buyerId = userVM.currentUser?.id else {
            vm.errorMessage = "Please log in to make an offer."
            return
        }
        guard let price = Double(priceText.replacingOccurrences(of: ",", with: ".")) else {
            vm.errorMessage = "Please enter a valid number."
            return
        }
        
        Task {
            let success = await vm.createOffer(assetId: assetId, buyerId: buyerId, price: price)
            if success { dismiss() }
        }
    }
}
