//
//  ARDashboardRootView.swift
//  Locolo
//
//  Entry point of the isolated AR module. Presented full screen from the
//  landing screen (FeedView) and behaves like a standalone app: four tabs
//  (Explore, Nearby, Search, Profile) behind a floating glass tab bar,
//  with the viewer and creation flow pushed on top of everything.
//

import SwiftUI

struct ARDashboardRootView: View {
    @StateObject private var dashboardState = ARDashboardState()
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var wishlistVM: WishlistViewModel
    @Environment(\.dismiss) private var dismiss

    /// Tabs are created lazily on first visit, then kept alive so each
    /// screen preserves its scroll position, map camera, and search state.
    @State private var visitedTabs: Set<ARTab> = [.explore]

    var body: some View {
        NavigationStack(path: $dashboardState.path) {
            ZStack {
                ARDesign.screenBackground.ignoresSafeArea()

                ForEach(ARTab.allCases) { tab in
                    if visitedTabs.contains(tab) {
                        tabContent(tab)
                            .opacity(dashboardState.selectedTab == tab ? 1 : 0)
                            .allowsHitTesting(dashboardState.selectedTab == tab)
                            .accessibilityHidden(dashboardState.selectedTab != tab)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ARTabBar(dashboardState: dashboardState)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ARRoute.self) { route in
                destination(for: route)
            }
        }
        .environmentObject(dashboardState)
        .onChange(of: dashboardState.selectedTab) { _, newTab in
            visitedTabs.insert(newTab)
        }
        .task {
            if let user = userVM.currentUser {
                await wishlistVM.loadWishlist(for: user.id)
            }
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private func tabContent(_ tab: ARTab) -> some View {
        switch tab {
        case .explore:
            ARExploreView(onDismiss: { dismiss() })
        case .nearby:
            ARNearbyView(onDismiss: { dismiss() })
        case .search:
            ARSearchView(onDismiss: { dismiss() })
        case .profile:
            ARCreatorDashboardView(onDismiss: { dismiss() })
        }
    }

    // MARK: - Pushed routes

    @ViewBuilder
    private func destination(for route: ARRoute) -> some View {
        switch route {
        case .viewer:
            ARDisplayView()
        case .create:
            ARCreateAssetFlowView(userId: userVM.currentUser?.id ?? UUID())
        case .collection:
            CollectionView()
                .background(AppColors.screenBackground.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
        case .wishlist:
            WishlistView()
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
