//
//  CreatorProfileView.swift
//  Locolo
//
//  Public creator profile (WS4): identity header, follower/following counts,
//  Follow / Message actions, and a grid of the creator's placed AR assets.
//

import SwiftUI

struct CreatorProfileView: View {
    let userId: UUID

    @StateObject private var vm: CreatorProfileViewModel
    @EnvironmentObject private var dashboardState: ARDashboardState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAsset: DigitalAsset?
    @State private var showMessagesComingSoon = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(userId: UUID) {
        self.userId = userId
        _vm = StateObject(wrappedValue: CreatorProfileViewModel(userId: userId))
    }

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    if vm.canFollow || vm.isSelf { actionRow }
                    assetGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable { await vm.load() }

            if vm.isLoading && vm.user == nil {
                ProgressView().tint(.purple).scaleEffect(1.3)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ARGlassHeader(title: vm.creator?.displayName ?? "Profile",
                          subtitle: vm.user.map { "@\($0.username)" }) {
                EmptyView()
            }
            .overlay(alignment: .leading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .padding(9)
                        .background(Circle().fill(ARDesign.headerButtonCircle))
                }
                .padding(.leading, 16)
                .accessibilityLabel("Back")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .sheet(item: $selectedAsset) { AssetDetailSheet(asset: $0) }
        .alert("Messaging is coming soon", isPresented: $showMessagesComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Encrypted chat with creators arrives in a future update.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            AsyncImage(url: vm.user?.avatarUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Circle().fill(AppColors.purplePinkGradient.opacity(0.25))
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundColor(.purple)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(ARDesign.hairline, lineWidth: 1))

            HStack(spacing: 6) {
                Text(vm.creator?.displayName ?? "AR Creator")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                if vm.creator?.isVerified == true {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Verified creator")
                }
            }

            if let bio = vm.user?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            statsRow
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statPill(count: vm.assets.count, label: "Assets") {}
            divider
            statPill(count: vm.followers, label: "Followers") {
                dashboardState.path.append(.followList(userId: userId, followers: true))
            }
            divider
            statPill(count: vm.following, label: "Following") {
                dashboardState.path.append(.followList(userId: userId, followers: false))
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .arGlassCard(cornerRadius: 18)
    }

    private var divider: some View {
        Rectangle().fill(ARDesign.hairline).frame(width: 1, height: 32)
    }

    private func statPill(count: Int, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(count)").font(.title3.bold()).foregroundColor(.primary)
                Text(label).font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(label)")
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            if vm.canFollow {
                Button { Task { await vm.toggleFollow() } } label: {
                    Text(vm.isFollowing ? "Following" : "Follow")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if vm.isFollowing {
                                Capsule().fill(.ultraThinMaterial)
                            } else {
                                Capsule().fill(AppColors.purplePinkGradient)
                            }
                        }
                        .overlay(
                            Capsule().strokeBorder(vm.isFollowing ? ARDesign.hairline : .clear, lineWidth: 1)
                        )
                        .foregroundColor(vm.isFollowing ? .primary : .white)
                }
                .disabled(vm.isMutatingFollow)

                Button { showMessagesComingSoon = true } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(ARDesign.headerButtonCircle))
                }
                .accessibilityLabel("Message")
            } else if vm.isSelf {
                Text("This is you")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
        }
    }

    // MARK: - Assets

    private var assetGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ARSectionHeader(title: "Placed Assets",
                            subtitle: vm.assets.isEmpty ? nil : "\(vm.assets.count) in the world",
                            icon: "cube.transparent")

            if vm.assets.isEmpty {
                emptyAssets
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(vm.assets) { asset in
                        Button { selectedAsset = asset } label: {
                            AssetThumbnailView(asset: asset, cornerRadius: 16)
                                .aspectRatio(1, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(alignment: .bottomLeading) {
                                    Text(asset.name ?? "Untitled")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                                           startPoint: .top, endPoint: .bottom)
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyAssets: some View {
        ARInlineEmptyState(
            icon: "cube.transparent",
            title: vm.isSelf ? "You haven't placed any assets yet" : "No assets placed yet",
            subtitle: vm.isSelf ? "Your AR creations will show up here." : nil,
            actionTitle: vm.isSelf ? "Create your first" : nil,
            action: vm.isSelf ? { dashboardState.path.append(.create) } : nil
        )
    }
}
