//
//  MainView.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import SwiftUI

struct MainView: View {
    
    @State private var selected = 0
    
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var placeVM: PlaceViewModel
    @EnvironmentObject var postsVM: ExplorePostsViewModel
    @EnvironmentObject var createPostVM: CreatePostViewModel
    @EnvironmentObject var discoverVM: DiscoverViewModel
    @EnvironmentObject var wishlistVM: WishlistViewModel
    @EnvironmentObject var keyboardObserver: KeyboardObserver
    
    var body: some View {
        
        VStack(spacing: 0) {
            ZStack {
                switch selected {
                case 0: FeedView()
                case 1: NavigationStack {
                    DiscoverView()
                        .environmentObject(discoverVM)
                        .environmentObject(loopVM)
                }
                case 2: CreatePostFlow(selectedTab: $selected)
                        .environmentObject(createPostVM)
                        .environmentObject(placeVM)
                        .environmentObject(loopVM)
                        .environmentObject(postsVM)
                case 3: NavigationStack {
                    ARScreen()
                        .task {
                            if let user = userVM.currentUser {
                                await wishlistVM.loadWishlist(for: user.id)
                            }
                        }
                }
                case 4: NavigationStack { ProfileView() }
                default: FeedView()
                }
            }
            if !keyboardObserver.isKeyboardVisible {
                BottomTabBar(selected: $selected)
            }
        }
    }
    
}

#Preview {
   MainView()
}
