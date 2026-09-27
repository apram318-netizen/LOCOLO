//
//  ARSettingsView.swift
//  Locolo
//
//  Account, privacy, and safety controls for the standalone AR app. Covers the
//  App Store must-haves that had no home once the legacy SettingsView left the
//  boot path: sign out, in-app account deletion (5.1.1(v)), and managing
//  blocked creators (1.2). Also surfaces the chat safety code and cache size.
//

import SwiftUI
import Supabase

struct ARSettingsView: View {
    @EnvironmentObject private var userVM: UserViewModel
    @ObservedObject private var safety = SafetyService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var email: String?
    @State private var blockedUsers: [User] = []
    @State private var cacheBytes: Int64 = 0
    @State private var showOnboarding = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let usersRepo = UsersRepository()

    var body: some View {
        List {
            accountSection
            safetySection
            privacySection
            appSection
            dangerSection
            footer
        }
        .scrollContentBackground(.hidden)
        .background(ARDesign.screenBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
        .onChange(of: safety.blockedUserIds) { Task { await loadBlockedUsers() } }
        .fullScreenCover(isPresented: $showOnboarding) {
            AROnboardingView { showOnboarding = false }
        }
        .confirmationDialog("Sign out of Locolo?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await signOut() } }
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete Permanently", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile, AR assets, placements, follows, and wishlist are removed for good. This can't be undone.")
        }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay {
            if isWorking {
                ProgressView()
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            if let user = userVM.currentUser {
                HStack(spacing: 14) {
                    ARAvatarView(url: user.avatarUrl, name: user.name ?? user.username, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name ?? user.username)
                            .font(.headline)
                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let email {
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Account")
        }
    }

    private var safetySection: some View {
        Section {
            if blockedUsers.isEmpty && safety.blockedUserIds.isEmpty {
                Label("You haven't blocked anyone", systemImage: "hand.raised")
                    .foregroundColor(.secondary)
            } else {
                ForEach(blockedUsers) { user in
                    HStack {
                        ARAvatarView(url: user.avatarUrl, name: user.name ?? user.username, size: 32)
                        VStack(alignment: .leading) {
                            Text(user.name ?? user.username).font(.subheadline.weight(.medium))
                            Text("@\(user.username)").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Unblock") { unblock(user.id) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                let unresolved = safety.blockedUserIds.count - blockedUsers.count
                if unresolved > 0 {
                    Text("\(unresolved) more blocked account\(unresolved == 1 ? "" : "s") (no longer available)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if !safety.hiddenAssetIds.isEmpty {
                Label("\(safety.hiddenAssetIds.count) reported asset\(safety.hiddenAssetIds.count == 1 ? "" : "s") hidden",
                      systemImage: "eye.slash")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Blocked creators")
        } footer: {
            Text("Blocked creators' assets disappear from your feeds, map, search, and AR view.")
        }
    }

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("End-to-end encrypted messages", systemImage: "lock.shield.fill")
                    .foregroundColor(.primary)
                Text("Your safety code")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(CryptoService.shared.myPublicKeyBase64.map(CryptoService.safetyCode(forPublicKeyBase64:)) ?? "Unavailable — unlock your phone")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .accessibilityLabel("Safety code")
            }
            .padding(.vertical, 4)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Compare this code in person with a friend's view of your profile to confirm messages between you can't be intercepted. It changes if you reinstall the app or switch phones.")
        }
    }

    private var appSection: some View {
        Section {
            Button {
                showOnboarding = true
            } label: {
                Label("Replay welcome tour", systemImage: "sparkles")
            }
            Button {
                MediaCache.shared.clear()
                cacheBytes = MediaCache.shared.diskUsage()
                ARHaptics.success()
            } label: {
                HStack {
                    Label("Clear downloaded models", systemImage: "externaldrive.badge.minus")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))
                        .foregroundColor(.secondary)
                }
            }
            .disabled(cacheBytes == 0)
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: settingsURL) {
                    Label("Camera, location & notifications", systemImage: "gear")
                }
            }
        } header: {
            Text("App")
        }
    }

    private var dangerSection: some View {
        Section {
            Button {
                confirmSignOut = true
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete account", systemImage: "trash")
            }
        }
    }

    private var footer: some View {
        Section {
            EmptyView()
        } footer: {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "—"
            let build = info?["CFBundleVersion"] as? String ?? "—"
            Text("Locolo \(version) (\(build))")
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func load() async {
        email = try? await SupabaseManager.shared.client.auth.session.user.email
        cacheBytes = MediaCache.shared.diskUsage()
        await loadBlockedUsers()
    }

    private func loadBlockedUsers() async {
        var resolved: [User] = []
        for id in safety.blockedUserIds {
            if let user = try? await usersRepo.getUser(by: id) {
                resolved.append(user)
            }
        }
        blockedUsers = resolved.sorted { ($0.name ?? $0.username) < ($1.name ?? $1.username) }
    }

    private func unblock(_ id: UUID) {
        guard let me = userVM.currentUser?.id else { return }
        ARHaptics.tick()
        Task { await safety.unblock(id, by: me) }
    }

    private func signOut() async {
        isWorking = true
        defer { isWorking = false }
        safety.resetForSignOut()
        await userVM.logout()
        if let message = userVM.errorMessage, userVM.isAuthenticated {
            errorMessage = "Couldn't sign out: \(message)"
        }
    }

    private func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await safety.deleteMyAccount()
            await userVM.logout()
        } catch {
            errorMessage = "We couldn't delete your account right now. Check your connection and try again — if it keeps failing, contact support and we'll remove it for you."
        }
    }
}
