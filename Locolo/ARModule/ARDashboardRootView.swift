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
    /// When true the AR module IS the whole app (launched as root), so there is
    /// nothing to dismiss back to and the header exit affordance is hidden.
    /// When false it behaves as a modal presented over the legacy app.
    var isRootExperience: Bool = false

    @StateObject private var dashboardState = ARDashboardState()
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var wishlistVM: WishlistViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var deepLinks = DeepLinkRouter.shared

    /// Tabs are created lazily on first visit, then kept alive so each
    /// screen preserves its scroll position, map camera, and search state.
    @State private var visitedTabs: Set<ARTab> = [.explore]

    /// One-time welcome flow (discover → create → connect).
    @AppStorage("ar_onboarding_seen") private var onboardingSeen = false
    @State private var showOnboarding = false

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
        // Profile links (locolo://user/<id>) push onto the dashboard stack.
        .onChange(of: deepLinks.pendingUserId) { openPendingProfileLink() }
        // Notification taps (chat, activity, AR viewer) push their screen.
        .onChange(of: deepLinks.pendingRoute) { openPendingRoute() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await ActivityStore.shared.refresh(force: false) }
                Task { await InboxStore.shared.syncReadState() }
                BadgeSync.shared.update()
            }
        }
        .task {
            openPendingProfileLink()
            openPendingRoute()
            if let user = userVM.currentUser {
                await wishlistVM.loadWishlist(for: user.id)
            }
            if isRootExperience && !onboardingSeen {
                showOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            AROnboardingView {
                onboardingSeen = true
                showOnboarding = false
            }
        }
    }

    private func openPendingProfileLink() {
        guard let userId = deepLinks.consumeUser() else { return }
        if userId == userVM.currentUser?.id {
            dashboardState.path = []
            dashboardState.select(.profile)
        } else if !SafetyService.shared.isBlocked(userId) {
            dashboardState.path.append(.profile(userId: userId))
        }
    }

    private func openPendingRoute() {
        guard let route = deepLinks.consumeRoute() else { return }
        if dashboardState.path.last == route { return }
        if case .chat(let id) = route, InboxStore.shared.openConversationId == id { return }
        dashboardState.path.append(route)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func tabContent(_ tab: ARTab) -> some View {
        // As the root experience there is nowhere to exit to, so we pass no
        // dismiss handler and the header hides its exit button.
        let exit: (() -> Void)? = isRootExperience ? nil : { dismiss() }
        switch tab {
        case .explore:
            ARExploreView(onDismiss: exit)
        case .nearby:
            ARNearbyView(onDismiss: exit)
        case .search:
            ARSearchView(onDismiss: exit)
        case .profile:
            ARCreatorDashboardView(onDismiss: exit)
        }
    }

    // MARK: - Pushed routes

    @ViewBuilder
    private func destination(for route: ARRoute) -> some View {
        switch route {
        case .viewer:
            ARDisplayView()
        case .create:
            if let userId = userVM.currentUser?.id {
                ARCreateAssetFlowView(userId: userId)
            } else {
                ARInlineEmptyState(
                    icon: "person.crop.circle.badge.exclamationmark",
                    title: "Sign in to create",
                    subtitle: "Assets are published under your profile, so you need to be signed in."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ARDesign.screenBackground.ignoresSafeArea())
            }
        case .collection:
            CollectionView()
                .background(AppColors.screenBackground.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
        case .wishlist:
            WishlistView()
                .navigationBarTitleDisplayMode(.inline)
        case .profile(let userId):
            CreatorProfileView(userId: userId)
        case .followList(let userId, let followers):
            FollowListView(userId: userId, showingFollowers: followers)
        case .conversations:
            ARMessagesView()
        case .settings:
            ARSettingsView()
        case .chat(let conversationId):
            if let me = userVM.currentUser {
                ARChatScreen(conversationId: conversationId,
                             currentUserId: me.id.uuidString,
                             currentUserName: me.name ?? me.username)
            }
        case .activity:
            ARActivityView()
        case .editProfile:
            AREditProfileView()
        }
    }
}
