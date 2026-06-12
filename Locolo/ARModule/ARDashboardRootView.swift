//
//  ARDashboardRootView.swift
//  Locolo
//
//  Entry point of the isolated AR module. Presented full screen from the
//  landing screen (FeedView) and owns its own NavigationStack, so all AR
//  sections (gallery, collection, wishlist, map, viewer, creation) live
//  apart from the rest of the app.
//

import SwiftUI

struct ARDashboardRootView: View {
    @StateObject private var dashboardState = ARDashboardState()
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var wishlistVM: WishlistViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $dashboardState.path) {
            ARScreen()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.bold())
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("AR Dashboard")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dashboardState.path.append(.profile)
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.subheadline.bold())
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dashboardState.path.append(.create)
                        } label: {
                            Image(systemName: "plus")
                                .font(.subheadline.bold())
                        }
                    }
                }
                .navigationDestination(for: ARRoute.self) { route in
                    switch route {
                    case .viewer:
                        ARDisplayView()
                    case .create:
                        ARCreateAssetFlowView(userId: userVM.currentUser?.id ?? UUID())
                    case .profile:
                        ARProfileView()
                    }
                }
        }
        .environmentObject(dashboardState)
        .task {
            if let user = userVM.currentUser {
                await wishlistVM.loadWishlist(for: user.id)
            }
        }
    }
}
