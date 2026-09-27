//
//  ReportSheet.swift
//  Locolo
//
//  Report an AR asset or a creator. Filing a report hides the asset for the
//  reporter immediately; optionally blocks the creator in the same step.
//

import SwiftUI

struct ReportSheet: View {
    /// The asset being reported (nil when reporting a profile).
    let assetId: UUID?
    /// The creator behind the content.
    let userId: UUID
    var subjectName: String

    @EnvironmentObject private var userVM: UserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reason: SafetyService.ReportReason?
    @State private var details = ""
    @State private var alsoBlock = false
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var serverFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    confirmation
                } else {
                    form
                }
            }
            .navigationTitle(submitted ? "" : "Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(submitted ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var form: some View {
        Form {
            Section {
                ForEach(SafetyService.ReportReason.allCases) { option in
                    Button {
                        ARHaptics.tick()
                        reason = option
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.icon)
                                .frame(width: 24)
                                .foregroundStyle(AppColors.purplePinkGradient)
                            Text(option.title)
                                .foregroundColor(.primary)
                            Spacer()
                            if reason == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    .accessibilityAddTraits(reason == option ? .isSelected : [])
                }
            } header: {
                Text("What's wrong with \(subjectName)?")
            }

            Section {
                TextField("Add details (optional)", text: $details, axis: .vertical)
                    .lineLimit(3...6)
            }

            if userVM.currentUser?.id != userId {
                Section {
                    Toggle("Also block this creator", isOn: $alsoBlock)
                        .tint(.purple)
                } footer: {
                    Text("You won't see their assets in your feed, map, search, or AR.")
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit report").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(reason == nil || isSubmitting)
            } footer: {
                Text("Reports are never shown to the creator.")
            }
        }
    }

    private var confirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.purplePinkGradient)
            Text("Thanks for letting us know")
                .font(.title3.bold())
            Text(serverFailed
                 ? "We couldn't reach the server, but this content is now hidden for you. Please try reporting again later."
                 : "We've hidden this content for you and our team will review it.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() async {
        guard let reason, let me = userVM.currentUser?.id else { return }
        isSubmitting = true
        let ok = await SafetyService.shared.report(
            assetId: assetId, userId: userId, reason: reason,
            details: details, reporter: me
        )
        if alsoBlock {
            await SafetyService.shared.block(userId, by: me)
        }
        isSubmitting = false
        serverFailed = !ok
        ARHaptics.success()
        withAnimation(ARDesign.spring) { submitted = true }
    }
}
