//
//  ARProfileView.swift
//  Locolo
//
//  The AR dashboard's profile. Header matches the main app's ProfileView,
//  but instead of posts/places it shows only AR content: the user's own
//  digital assets and the assets they've explored in AR sessions.
//

import SwiftUI

struct ARProfileView: View {
    @EnvironmentObject var userVM: UserViewModel
    @StateObject private var vm = ARProfileViewModel()

    @State private var selectedTab: Int = 0
    @State private var selectedAsset: DigitalAsset?

    var body: some View {
        if let user = userVM.currentUser {
            VStack(spacing: 20) {
                // MARK: - Profile Header
                headerView(for: user)
                    .padding(.top, 12)

                // MARK: - Tabs
                Picker("", selection: $selectedTab) {
                    Text("My Assets").tag(0)
                    Text("Explored").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // MARK: - Content
                if vm.isLoading {
                    ProgressView("Loading assets…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = vm.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                    Spacer()
                } else {
                    assetList(
                        selectedTab == 0 ? vm.ownAssets : vm.exploredAssets,
                        emptyText: selectedTab == 0
                            ? "You haven't posted any assets yet."
                            : "Nothing explored yet — open the AR viewer and discover assets around you."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColors.screenBackground.ignoresSafeArea())
            .navigationTitle("AR Profile")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await vm.load(userId: user.id)
            }
            .sheet(item: $selectedAsset) { asset in
                AssetDetailSheet(asset: asset)
            }
        } else {
            Text("User not logged in")
        }
    }

    // MARK: - Asset List
    private func assetList(_ assets: [DigitalAsset], emptyText: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            if assets.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 60)
            } else {
                VStack(spacing: 16) {
                    ForEach(assets) { asset in
                        Button {
                            selectedAsset = asset
                        } label: {
                            CollectionCard(asset: asset)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Header (matches main app's ProfileView style)
    private func headerView(for user: User) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: user.avatarUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.purple, lineWidth: 2))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(user.name ?? user.username)
                        .font(.title3.bold())
                    if let verified = user.verifiedFlags?["blue"], verified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Text("@\(user.username)")
                    .foregroundStyle(.gray)

                if let bio = user.bio {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statView(value: vm.ownAssets.count, label: "Assets")
                    statView(value: vm.exploredAssets.count, label: "Explored")
                    statView(value: vm.totalViews, label: "Views")
                }
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private func statView(value: Int, label: String) -> some View {
        VStack {
            Text("\(value)").bold()
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
}
