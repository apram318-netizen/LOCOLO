//
//  MarketplaceSheet.swift
//  Locolo
//
//  Phase A marketplace sheet: list / buy / cancel fixed-price listings
//  plus a provenance timeline for the asset.
//

import SwiftUI

struct MarketplaceSheet: View {
    let asset: DigitalAsset
    var onTradeComplete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userVM: UserViewModel
    @ObservedObject private var creators = CreatorCache.shared

    @State private var activeListing: AssetListing?
    @State private var provenance: [ProvenanceRecord] = []
    @State private var bids: [MarketplaceRepository.AssetBid] = []
    @State private var priceText = ""
    @State private var bidText = ""
    @State private var listAsAuction = false
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var confirmBuy = false
    @State private var celebrateSale = false

    private let repo = MarketplaceRepository.shared

    private var effectiveOwnerId: UUID { asset.effectiveOwnerId }
    private var isOwner: Bool { userVM.currentUser?.id == effectiveOwnerId }
    private var parsedPrice: Double? { Double(priceText.trimmingCharacters(in: .whitespaces)) }
    private var parsedBid: Double? { Double(bidText.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        NavigationStack {
            ZStack {
                ARDesign.screenBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading marketplace…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            tradeSection
                            provenanceSection
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Marketplace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
            .confirmationDialog(
                buyConfirmTitle,
                isPresented: $confirmBuy,
                titleVisibility: .visible
            ) {
                Button("Buy for \(buyPriceLabel)") { Task { await purchase() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Off-chain Phase A — no real money yet.")
            }
        }
    }

    // MARK: - Trade section

    @ViewBuilder
    private var tradeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trade")
                .font(.headline)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if isOwner {
                ownerTradeContent
            } else if let listing = activeListing, listing.kind == "fixed" {
                buyerTradeContent(listing)
            } else if let listing = activeListing, listing.kind == "auction" {
                auctionBuyerContent(listing)
            } else {
                Text("Not listed for sale.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .arGlassCard(cornerRadius: 20)
        .celebration(trigger: $celebrateSale, symbol: "dollarsign.circle.fill")
    }

    @ViewBuilder
    private var ownerTradeContent: some View {
        if let listing = activeListing {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(listing.kind == "auction" ? "Auction live" : "Listed")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text(currency(listing.price))
                            .font(.title2.bold())
                        if listing.kind == "auction", let ends = listing.endsAt {
                            Text("Ends \(ends.shortRelative)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await cancel() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.red)
                        } else {
                            Text("Cancel listing")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .disabled(isSubmitting)
                }
                if listing.kind == "auction" {
                    bidsList
                    if listing.endsAt.map({ $0 <= Date() }) == true {
                        Button {
                            Task { await settle() }
                        } label: {
                            Text(isSubmitting ? "Settling…" : "Settle auction")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppColors.purplePinkGradient)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isSubmitting)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Listing type", selection: $listAsAuction) {
                    Text("Fixed price").tag(false)
                    Text("Auction").tag(true)
                }
                .pickerStyle(.segmented)

                Text(listAsAuction
                     ? "Starting bid in USDC (shown as $). Runs 24 hours."
                     : "Set a fixed price in USDC (shown as $).")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Text("$")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.secondary)
                    TextField(listAsAuction ? "Starting bid" : "Price", text: $priceText)
                        .keyboardType(.decimalPad)
                        .font(.title3)
                        .textFieldStyle(.plain)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(ARDesign.headerButtonCircle))

                Button {
                    Task { await list() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(listAsAuction ? "Start auction" : "List for sale")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColors.purplePinkGradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isSubmitting || (parsedPrice ?? 0) <= 0)
            }
        }
    }

    private func auctionBuyerContent(_ listing: AssetListing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current high")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(currency(listing.price))
                .font(.title.bold())
            if let ends = listing.endsAt {
                Text("Ends \(ends.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            bidsList
            HStack(spacing: 10) {
                Text("$")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.secondary)
                TextField("Your bid", text: $bidText)
                    .keyboardType(.decimalPad)
                    .font(.title3)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(ARDesign.headerButtonCircle))

            Button {
                Task { await placeBid(on: listing) }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Place bid")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppColors.purplePinkGradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isSubmitting || (parsedBid ?? 0) <= listing.price)
        }
    }

    @ViewBuilder
    private var bidsList: some View {
        if !bids.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent bids")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                ForEach(bids.prefix(5)) { bid in
                    HStack {
                        Text(currency(bid.amount))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(bid.createdAt.shortRelative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func buyerTradeContent(_ listing: AssetListing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(currency(listing.price))
                .font(.title.bold())

            Button {
                confirmBuy = true
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Buy now")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppColors.purplePinkGradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isSubmitting)
        }
    }

    // MARK: - Provenance

    @ViewBuilder
    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Provenance")
                .font(.headline)

            if provenance.isEmpty {
                Text("No provenance records yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(provenance.enumerated()), id: \.element.id) { index, record in
                        provenanceRow(record, isLast: index == provenance.count - 1)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .arGlassCard(cornerRadius: 20)
    }

    private func provenanceRow(_ record: ProvenanceRecord, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(eventColor(record.eventType))
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
                if !isLast {
                    Rectangle()
                        .fill(ARDesign.hairline)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(eventLabel(record))
                    .font(.subheadline.weight(.semibold))
                if let actorId = record.actorId {
                    Text(actorHandle(actorId))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(record.createdAt.shortRelative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, isLast ? 0 : 14)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let listing = repo.activeListing(for: asset.id)
            async let records = repo.provenance(for: asset.id)
            activeListing = try await listing
            provenance = try await records
            if let listing = activeListing, listing.kind == "auction" {
                bids = (try? await repo.bids(for: listing.listingId)) ?? []
            } else {
                bids = []
            }
            let actorIds = records.compactMap(\.actorId)
            if !actorIds.isEmpty {
                await creators.load(actorIds)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func list() async {
        guard let price = parsedPrice, price > 0 else {
            errorMessage = "Enter a valid price."
            return
        }
        isSubmitting = true
        errorMessage = nil
        do {
            if listAsAuction {
                activeListing = try await repo.listAuction(assetId: asset.id, startingPrice: price)
            } else {
                activeListing = try await repo.listForSale(assetId: asset.id, price: price)
            }
            if let listing = activeListing, listing.kind == "auction" {
                bids = (try? await repo.bids(for: listing.listingId)) ?? []
            }
            provenance = (try? await repo.provenance(for: asset.id)) ?? provenance
            ARHaptics.success()
            onTradeComplete?()
        } catch {
            errorMessage = error.localizedDescription
            ARHaptics.warning()
        }
        isSubmitting = false
    }

    private func placeBid(on listing: AssetListing) async {
        guard let amount = parsedBid, amount > listing.price else {
            errorMessage = "Bid must beat the current high."
            return
        }
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await repo.placeBid(listingId: listing.listingId, amount: amount)
            activeListing = try await repo.activeListing(for: asset.id)
            if let listing = activeListing {
                bids = (try? await repo.bids(for: listing.listingId)) ?? []
            }
            bidText = ""
            ARHaptics.success()
            onTradeComplete?()
        } catch {
            errorMessage = error.localizedDescription
            ARHaptics.warning()
        }
        isSubmitting = false
    }

    private func settle() async {
        guard let listing = activeListing else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await repo.settleAuction(listingId: listing.listingId)
            celebrateSale = true
            activeListing = nil
            bids = []
            ARHaptics.success()
            onTradeComplete?()
        } catch {
            errorMessage = error.localizedDescription
            ARHaptics.warning()
        }
        isSubmitting = false
    }

    private func cancel() async {
        guard let listing = activeListing else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await repo.cancelListing(listingId: listing.listingId, assetId: asset.id)
            activeListing = nil
            ARHaptics.tick()
            onTradeComplete?()
        } catch {
            errorMessage = error.localizedDescription
            ARHaptics.warning()
        }
        isSubmitting = false
    }

    private func purchase() async {
        guard let listing = activeListing else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await repo.buyListing(listingId: listing.listingId)
            ARHaptics.success()
            onTradeComplete?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            ARHaptics.warning()
        }
        isSubmitting = false
    }

    // MARK: - Helpers

    private var buyPriceLabel: String {
        guard let listing = activeListing else { return "$0" }
        return currency(listing.price)
    }

    private var buyConfirmTitle: String {
        "Buy for \(buyPriceLabel)?"
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.0f", value)
    }

    private func actorHandle(_ id: UUID) -> String {
        if let creator = creators.creator(id) {
            return "@\(creator.username)"
        }
        return "Unknown"
    }

    private func eventLabel(_ record: ProvenanceRecord) -> String {
        switch record.eventType {
        case "mint": return "Minted"
        case "sale": return "Sold"
        case "transfer": return "Transferred"
        case "list": return "Listed for sale"
        case "delist": return "Delisted"
        default: return record.eventType.capitalized
        }
    }

    private func eventColor(_ type: String) -> Color {
        switch type {
        case "mint": return ARDesign.chartCategorical[4]
        case "sale": return ARDesign.chartCategorical[1]
        case "transfer": return ARDesign.chartCategorical[2]
        case "list", "delist": return ARDesign.chartCategorical[3]
        default: return ARDesign.accent
        }
    }
}
