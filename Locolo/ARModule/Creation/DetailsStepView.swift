//
//  DetailsStepView.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//


import SwiftUI
import UniformTypeIdentifiers
import RealityKit
import UIKit

struct DetailsStepView: View {
    @ObservedObject var vm: ARCreateViewModel
    let saveAction: () -> Void
    let onDone: () -> Void
    @State private var showAddressSheet = false
    @State private var showMediaPicker = false
    @State private var showShareSheet = false

    // Mint paywall
    @State private var couponText = ""
    @State private var quote: MintingService.FeeQuote?
    @State private var couponValid = false
    @State private var couponMessage: String?
    @State private var isPreviewing = false
    @State private var isMinting = false
    @ObservedObject private var purchases = MintPurchaseService.shared

    /// The App Store's localized price wins over the server's USD quote.
    private var feeLabel: String {
        purchases.product?.displayPrice ?? "$\(String(format: "%.2f", quote?.total ?? 2.99))"
    }

    private var mintButtonTitle: String {
        if let q = quote, q.total <= 0 { return "Mint for free" }
        if quote != nil { return "Mint · \(feeLabel)" }
        return "Mint"
    }

    var body: some View {
        Form {
            Section("Info") {
                TextField("Name", text: $vm.name)
                TextField("Description", text: $vm.descriptionText, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Tags (e.g. streetart, sculpture)", text: $vm.tagsText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                CollabPickerRow()
            } header: {
                Text("Featuring")
            } footer: {
                Text("Credit collab partners on this drop.")
            }

            Section {
                TextField("Poll question (optional)", text: $vm.pollQuestion)
                TextField("Option A", text: $vm.pollOptionA)
                TextField("Option B", text: $vm.pollOptionB)
                TextField("Option C (optional)", text: $vm.pollOptionC)
            } header: {
                Text("Poll")
            } footer: {
                Text("Leave blank to skip.")
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
                    if vm.previewEntity != nil {
                        AnimationPreviewView(vm: vm)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button {
                            ARHaptics.tick()
                            // Re-play selected animation as a live trigger preview.
                            if let entity = vm.previewEntity,
                               let idx = vm.selectedAnimationIndex,
                               entity.availableAnimations.indices.contains(idx) {
                                entity.playAnimation(entity.availableAnimations[idx].repeat(count: 1))
                            }
                            if let url = vm.localMediaURL {
                                // Preview sidecar audio via system player when present.
                                TriggerPreviewAudio.shared.play(url: url)
                            }
                        } label: {
                            Label("Preview trigger", systemImage: "play.circle.fill")
                        }
                    }
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

            // Mint paywall: fee + coupon → creates a mint order, then mints.
            Section {
                HStack {
                    Text("Mint fee")
                    Spacer()
                    if let q = quote, q.discount > 0 {
                        Text("$\(q.fee, specifier: "%.2f")").strikethrough().foregroundStyle(.secondary)
                        Text(q.total <= 0 ? "FREE" : "$\(q.total, specifier: "%.2f")")
                            .fontWeight(.bold)
                            .foregroundStyle(q.total <= 0 ? Color.green : Color.primary)
                    } else {
                        Text(feeLabel).fontWeight(.semibold)
                    }
                }

                #if DEBUG
                // QA only: App Review 3.1.1 forbids unlocking paid features
                // with our own codes in the shipping app.
                HStack {
                    TextField("Coupon code", text: $couponText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Apply") { Task { await applyCoupon() } }
                        .disabled(couponText.trimmingCharacters(in: .whitespaces).isEmpty || isPreviewing)
                }
                #endif
                if let couponMessage {
                    Text(couponMessage)
                        .font(.caption)
                        .foregroundStyle(couponValid ? .green : .red)
                }

                Button {
                    Task { await mint() }
                } label: {
                    HStack {
                        if vm.isBusy || isMinting { ProgressView().padding(.trailing, 6) }
                        Text(mintButtonTitle).frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .disabled(vm.isBusy || isMinting || vm.uploadedFileURL == nil || vm.transform == nil)
            } header: {
                Text("Mint")
            } footer: {
                Text("Minting registers your creation on Locolo's authenticity ledger — signed by you and tamper-evident. The mint fee is charged to your Apple Account.")
            }
        }
        .task {
            if quote == nil { quote = await MintingService.shared.preview(coupon: nil) }
            await purchases.loadProduct()
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

extension DetailsStepView {
    private func applyCoupon() async {
        isPreviewing = true; defer { isPreviewing = false }
        let code = couponText.trimmingCharacters(in: .whitespaces)
        let q = await MintingService.shared.preview(coupon: code)
        quote = q
        couponValid = q?.valid ?? false
        if let q {
            couponMessage = q.valid
                ? (q.total <= 0 ? "Coupon applied — mint is free 🎉" : "Coupon applied")
                : (q.reason ?? "Invalid code")
        } else {
            couponMessage = "Couldn't check that code"
        }
    }

    private func mint() async {
        isMinting = true; defer { isMinting = false }
        #if DEBUG
        let code = couponText.trimmingCharacters(in: .whitespaces)
        #else
        let code = ""
        #endif
        do {
            let order = try await MintingService.shared.createOrder(coupon: code.isEmpty ? nil : code)
            if order.status != "waived" && order.total > 0 {
                couponMessage = nil
                // App Store purchase; the server marks the order paid once
                // Apple's signed transaction checks out.
                guard try await MintPurchaseService.shared.purchase(orderId: order.order_id) else { return }
            }
            vm.mintOrderId = order.order_id
            ARHaptics.success()
            saveAction()   // proceeds to upload + sign + insert (provenance auto)
        } catch {
            couponValid = false
            couponMessage = error.localizedDescription
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

// MARK: - Collab picker

private struct CollabPickerRow: View {
    @ObservedObject private var collabs = CollabStore.shared
    @State private var query = ""
    @State private var results: [ARCreator] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !collabs.pendingCollabIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(collabs.pendingCollabIds, id: \.self) { id in
                            let creator = CreatorCache.shared.creator(id)
                            HStack(spacing: 6) {
                                Text("@\(creator?.username ?? String(id.uuidString.prefix(6)))")
                                    .font(.caption.weight(.semibold))
                                Button {
                                    collabs.removePending(id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.purple.opacity(0.14)))
                        }
                    }
                }
            }

            HStack {
                TextField("Search @handle", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await runSearch() } }
                if searching { ProgressView() }
            }

            ForEach(results.prefix(6)) { person in
                Button {
                    collabs.addPending(person.id)
                    query = ""
                    results = []
                } label: {
                    HStack(spacing: 10) {
                        ARAvatarView(url: person.avatarUrl, name: person.displayName, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.displayName).font(.subheadline.weight(.semibold))
                            Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(.purple)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: query) { _, q in
            guard q.count >= 2 else { results = []; return }
            Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard query == q else { return }
                await runSearch()
            }
        }
    }

    private func runSearch() async {
        searching = true
        defer { searching = false }
        results = await PeopleSearch.search(query, limit: 8)
    }
}
