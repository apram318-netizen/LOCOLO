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

    var body: some View {
        // ARDashboardRootView already owns its own NavigationStack, tab bar,
        // and reads userVM / wishlistVM from the environment.
        ARDashboardRootView(isRootExperience: true)
    }
}
