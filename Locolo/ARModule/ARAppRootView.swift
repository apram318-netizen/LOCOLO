//
//  ARAppRootView.swift
//  Locolo
//
//  Root of the standalone AR-only app (WS0). Once the user is authenticated,
//  the AR module IS the whole app — there is no legacy tab shell behind it.
//  The non-AR screens remain in the repo but are no longer on the boot path.
//

import SwiftUI

struct ARAppRootView: View {
    @EnvironmentObject var userVM: UserViewModel
    @ObservedObject private var deepLinks = DeepLinkRouter.shared

    @State private var deepLinkAsset: DigitalAsset?
    private let assetRepo = DigitalAssetRepository()

    /// Read by the notification quick-reply path, which runs outside any view.
    static let displayNameDefaultsKey = "ar_current_user_display_name"

    var body: some View {
        // ARDashboardRootView already owns its own NavigationStack, tab bar,
        // and reads userVM / wishlistVM from the environment.
        ARDashboardRootView(isRootExperience: true)
            // Deep links (locolo://asset/<uuid>) are caught by ContentView and
            // parked in DeepLinkRouter so cold launches aren't lost.
            .onChange(of: deepLinks.pendingAssetId) { openPendingDeepLink() }
            .task {
                openPendingDeepLink()
                await onSignedIn()
            }
            // This view only exists while signed in, so leaving it is sign-out.
            .onDisappear { SocialSession.end() }
            .sheet(item: $deepLinkAsset) { asset in
                AssetDetailSheet(asset: asset)
            }
    }

    private func openPendingDeepLink() {
        guard let assetId = deepLinks.consume() else { return }
        Task {
            if let asset = await assetRepo.fetchAsset(id: assetId),
               !SafetyService.shared.isHidden(asset) {
                deepLinkAsset = asset
            }
        }
    }

    /// Runs every time the signed-in experience mounts — after session
    /// restore, sign-in, and sign-up alike (ContentView only covered restore).
    private func onSignedIn() async {
        guard let user = userVM.currentUser else { return }
        UserDefaults.standard.set(user.name ?? user.username, forKey: Self.displayNameDefaultsKey)
        async let social: Void = SocialSession.start(me: user.id)
        await KeyDirectory.shared.publishMyKey(userId: user.id)
        await SafetyService.shared.syncBlocks(for: user.id)
        await social
    }
}
