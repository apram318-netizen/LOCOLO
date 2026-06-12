//
//  OfferListView.swift
//  Locolo
//
//  Created by Apramjot Singh on 9/11/2025.
//


//  View Summary:
//  - Shows all offers made on a digital asset.
//  - Lets the owner accept or reject offers, and lets buyers withdraw their own offers.
//  - Supports sorting, pull-to-refresh, loading states, and basic error handling.
//  - Uses OfferViewModel for all data operations.
//

import SwiftUI

struct OfferListView: View {
    let assetId: UUID
    var ownerId: UUID? = nil
    
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = OfferViewModel()
    
    private var currentUserId: UUID? { userVM.currentUser?.id }
    private var isOwner: Bool { ownerId != nil && ownerId == currentUserId }
    
    var body: some View {
        NavigationStack {
            
            // MARK: - Content Handling
            // This group shows loading, errors, empty state, or the offer list.
            Group {
                if vm.isLoading {
                    ProgressView("Loading offers...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                } else if let err = vm.errorMessage {
                    VStack(spacing: 10) {
                        Text("Couldn’t load offers")
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await vm.loadOffers(for: assetId) }
                        }
                    }
                    
                } else if vm.offers.isEmpty {
                    Text("No offers yet")
                        .font(.headline)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                } else {
                    // MARK: - Offer List
                    // Displays the offers with sorting options and action buttons.
                    List {
                        Section {
                            sortHeader
                        }
                        
                        ForEach(vm.offers) { offer in
                            OfferRow(
                                offer: offer,
                                isOwner: isOwner,
                                isBuyer: offer.buyerId == currentUserId,
                                onAccept: { Task { await vm.updateOfferStatus(offer.id, to: "accepted", for: assetId) } },
                                onReject: { Task { await vm.updateOfferStatus(offer.id, to: "rejected", for: assetId) } },
                                onWithdraw: { Task { await vm.withdrawOffer(offer.id, for: assetId) } }
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await vm.loadOffers(for: assetId) }
                }
            }
            
            // MARK: - Navigation and Setup
            .navigationTitle("Offers")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await vm.loadOffers(for: assetId)
            }
        }
    }
    
    
    // MARK: - Sort Header
    // Shows total offer count and a menu to change sorting.
    private var sortHeader: some View {
        HStack {
            Text("\(vm.offers.count) \(vm.offers.count == 1 ? "offer" : "offers")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            
            Menu {
                ForEach(OfferViewModel.SortMode.allCases, id: \.self) { mode in
                    Button {
                        vm.setSort(mode)
                    } label: {
                        if mode == vm.sortMode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
            } label: {
                Label(vm.sortMode.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline)
            }
        }
    }
}


// MARK: - Offer Row
// Displays one offer with price, date, status, and action buttons based on the user role.

private struct OfferRow: View {
    let offer: Offer
    let isOwner: Bool
    let isBuyer: Bool
    let onAccept: () -> Void
    let onReject: () -> Void
    let onWithdraw: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            HStack {
                Text("$\(offer.price, specifier: "%.2f")")
                    .font(.headline)
                Spacer()
                StatusPill(status: offer.status)
            }
            
            Text(offer.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundColor(.secondary)
            
            
            // Pending offers allow actions from owner or buyer.
            if offer.status == "pending" {
                HStack {
                    if isOwner {
                        GradientButton(title: "Accept", colors: [.green, .teal], action: onAccept)
                        GradientButton(title: "Reject", colors: [.red, .orange], action: onReject)
                    }
                    if isBuyer {
                        Button(action: onWithdraw) {
                            Text("Withdraw")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .cornerRadius(10)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

//
// MARK: - Reusable UI Components
//

private struct GradientButton: View {
    let title: String
    let colors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }
}

private struct StatusPill: View {
    let status: String
    
    var body: some View {
        let (bg, fg): (Color, Color) = {
            switch status {
            case "pending": return (Color.yellow.opacity(0.2), .yellow)
            case "accepted": return (Color.green.opacity(0.2), .green)
            case "rejected": return (Color.red.opacity(0.2), .red)
            case "withdrawn": return (Color.gray.opacity(0.2), .gray)
            default: return (Color.gray.opacity(0.2), .gray)
            }
        }()
        
        return Text(status.capitalized)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundColor(fg)
            .cornerRadius(20)
    }
}
