//
//  ARCreatorDashboardView.swift
//  Locolo
//
//  The Profile tab of the AR dashboard: a creator-focused home with
//  overview stats, analytics charts, marketplace insights, and the
//  user's AR library (own assets, explored, collection, wishlist).
//  Replaces the old ARProfileView.
//

import SwiftUI
import Charts

struct ARCreatorDashboardView: View {
    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject private var dashboardState: ARDashboardState
    @StateObject private var vm = ARProfileViewModel()

    @State private var selectedAsset: DigitalAsset?
    @State private var offersForAsset: DigitalAsset?

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()

            if let user = userVM.currentUser {
                content(for: user)
            } else {
                Text("User not logged in")
                    .foregroundColor(.secondary)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ARGlassHeader(title: "Creator Studio", subtitle: "Your AR presence", onExit: onDismiss) {
                ARHeaderIconButton(icon: "plus", label: "Create AR asset", prominent: true) {
                    dashboardState.path.append(.create)
                }
            }
        }
        .sheet(item: $selectedAsset) { AssetDetailSheet(asset: $0) }
        .sheet(item: $offersForAsset) { asset in
            OfferListView(assetId: asset.id, ownerId: userVM.currentUser?.id)
        }
    }

    private func content(for user: User) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                headerView(for: user)

                if vm.isLoading {
                    ProgressView("Loading your studio…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let error = vm.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                } else {
                    overviewSection
                    if !vm.ownAssets.isEmpty {
                        analyticsSection
                        marketplaceSection
                    }
                    librarySection
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await vm.load(userId: user.id) }
        .task { await vm.load(userId: user.id) }
    }

    // MARK: - Header

    private func headerView(for user: User) -> some View {
        HStack(alignment: .center, spacing: 16) {
            AsyncImage(url: user.avatarUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [.purple, .pink],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 2
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(user.name ?? user.username)
                        .font(.title3.bold())
                        .lineLimit(1)
                    if let verified = user.verifiedFlags?["blue"], verified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Verified")
                    }
                }

                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ARSectionHeader(title: "Overview", icon: "chart.bar.doc.horizontal")
                .padding(.horizontal, 16)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ARStatTile(value: "\(vm.ownAssets.count)", label: "Published Assets",
                           icon: "cube.fill")
                ARStatTile(value: "\(vm.totalViews)", label: "Total Views",
                           icon: "eye.fill", tint: Color(hex: "0891B2"))
                ARStatTile(value: "\(vm.totalHype)", label: "Hype Received",
                           icon: "bolt.fill", tint: Color(hex: "D97706"))
                ARStatTile(value: "\(vm.exploredAssets.count)", label: "Assets Explored",
                           icon: "safari.fill", tint: Color(hex: "16A34A"))
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Analytics

    private var analyticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ARSectionHeader(
                title: "Analytics",
                subtitle: "How your assets are performing",
                icon: "chart.xyaxis.line"
            )
            .padding(.horizontal, 16)

            VStack(spacing: 12) {
                if !vm.topAssetsByViews.isEmpty {
                    viewsChart
                }
                if vm.uploadsByMonth.count > 1 {
                    uploadsChart
                }
                if !vm.categoryBreakdown.isEmpty {
                    categoryChart
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Top assets by views — horizontal bars, single brand hue.
    private var viewsChart: some View {
        chartCard(title: "Most viewed assets") {
            Chart(vm.topAssetsByViews, id: \.name) { entry in
                BarMark(
                    x: .value("Views", entry.views),
                    y: .value("Asset", entry.name)
                )
                .foregroundStyle(ARDesign.accent)
                .cornerRadius(4)
                .annotation(position: .trailing, spacing: 6) {
                    Text("\(entry.views)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: CGFloat(vm.topAssetsByViews.count) * 34 + 8)
        }
    }

    /// Uploads over time — single-series area + line.
    private var uploadsChart: some View {
        chartCard(title: "Uploads over time") {
            Chart(vm.uploadsByMonth, id: \.month) { entry in
                AreaMark(
                    x: .value("Month", entry.month, unit: .month),
                    y: .value("Uploads", entry.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [ARDesign.accent.opacity(0.32), ARDesign.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Month", entry.month, unit: .month),
                    y: .value("Uploads", entry.count)
                )
                .foregroundStyle(ARDesign.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(ARDesign.hairline)
                    AxisValueLabel().font(.caption2)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), collisionResolution: .greedy)
                        .font(.caption2)
                }
            }
            .frame(height: 160)
        }
    }

    /// Category breakdown — donut with fixed per-category colors,
    /// sector gaps + legend as the secondary (non-color) encoding.
    private var categoryChart: some View {
        chartCard(title: "Assets by category") {
            Chart(vm.categoryBreakdown, id: \.category) { entry in
                SectorMark(
                    angle: .value("Assets", entry.count),
                    innerRadius: .ratio(0.62),
                    angularInset: 2
                )
                .foregroundStyle(by: .value("Category", entry.category.capitalized))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale(
                domain: ARProfileViewModel.categoryOrder.map(\.capitalized),
                range: ARDesign.chartCategorical
            )
            .chartLegend(position: .trailing, alignment: .center, spacing: 16)
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let anchor = proxy.plotFrame {
                        let frame = geo[anchor]
                        VStack(spacing: 2) {
                            Text("\(vm.ownAssets.count)")
                                .font(.title3.bold())
                            Text("assets")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 170)
        }
    }

    private func chartCard(title: String, @ViewBuilder chart: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            chart()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .arGlassCard(cornerRadius: 20)
    }

    // MARK: - Marketplace

    private var marketplaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ARSectionHeader(
                title: "Marketplace",
                subtitle: "Offers, earnings and portfolio value",
                icon: "bag.fill"
            )
            .padding(.horizontal, 16)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ARStatTile(value: currency(vm.portfolioValue), label: "Portfolio Value",
                           icon: "chart.pie.fill")
                ARStatTile(value: currency(vm.revenue), label: "Earnings (accepted)",
                           icon: "dollarsign.circle.fill", tint: Color(hex: "16A34A"))
                ARStatTile(value: "\(vm.pendingOffers.count)", label: "Pending Offers",
                           icon: "envelope.badge.fill", tint: Color(hex: "D97706"))
                ARStatTile(value: vm.highestOpenOffer.map(currency) ?? "—", label: "Highest Open Offer",
                           icon: "arrow.up.right.circle.fill", tint: Color(hex: "0891B2"))
            }
            .padding(.horizontal, 16)

            if let top = vm.topAsset {
                topPerformerCard(top)
                    .padding(.horizontal, 16)
            }

            if vm.isLoadingOffers {
                HStack(spacing: 8) {
                    ProgressView().tint(.purple)
                    Text("Checking your offers…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
            } else if !vm.assetsWithPendingOffers.isEmpty {
                VStack(spacing: 10) {
                    ForEach(vm.assetsWithPendingOffers, id: \.asset.id) { entry in
                        pendingOfferRow(entry.asset, best: entry.best, count: entry.count)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func topPerformerCard(_ asset: DigitalAsset) -> some View {
        Button { selectedAsset = asset } label: {
            HStack(spacing: 12) {
                AssetThumbnailView(asset: asset)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "trophy.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text("Top performer")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                    Text(asset.name ?? "Untitled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(asset.viewCount) views · \(asset.hypeCount) hypes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .arGlassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    private func pendingOfferRow(_ asset: DigitalAsset, best: Double, count: Int) -> some View {
        Button { offersForAsset = asset } label: {
            HStack(spacing: 12) {
                AssetThumbnailView(asset: asset)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name ?? "Untitled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(count) pending offer\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(currency(best))
                    .font(.subheadline.bold())
                    .foregroundColor(Color(hex: "16A34A"))

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .arGlassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Review offers for this asset")
    }

    private func currency(_ value: Double) -> String {
        value == 0 ? "$0" : String(format: "$%.0f", value)
    }

    // MARK: - Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ARSectionHeader(title: "Library", subtitle: "Your AR content", icon: "books.vertical.fill")
                .padding(.horizontal, 16)

            assetShelf(
                title: "My Assets",
                emptyText: "You haven't posted any assets yet — tap + to place your first one.",
                assets: vm.ownAssets
            )

            assetShelf(
                title: "Explored",
                emptyText: "Nothing explored yet — open the AR viewer and discover assets around you.",
                assets: vm.exploredAssets
            )

            VStack(spacing: 10) {
                libraryLink(title: "My Collection", icon: "bag.fill", route: .collection)
                libraryLink(title: "Wishlist", icon: "heart.fill", route: .wishlist)
            }
            .padding(.horizontal, 16)
        }
    }

    private func assetShelf(title: String, emptyText: String, assets: [DigitalAsset]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(assets.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            if assets.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(assets) { asset in
                            Button { selectedAsset = asset } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    AssetThumbnailView(asset: asset, cornerRadius: 14)
                                        .frame(width: 104, height: 104)
                                    Text(asset.name ?? "Untitled")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .frame(width: 104, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func libraryLink(title: String, icon: String, route: ARRoute) -> some View {
        Button {
            dashboardState.path.append(route)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.purple)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.purple.opacity(0.14)))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .arGlassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}
