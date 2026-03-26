//
//  LocoloApp.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/9/2025.
//

import SwiftUI
import FirebaseCore

@main
struct LocoloApp: App {
    @StateObject private var userVM = UserViewModel()
    @StateObject private var loopVM = LoopViewModel()
    @StateObject private var placeVM = PlaceViewModel()
    @StateObject private var locationVM = LocationViewModel()
    @StateObject private var postsVM: ExplorePostsViewModel
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var createPostVM :CreatePostViewModel
    @StateObject private var discoverVM = DiscoverViewModel()
    @StateObject private var wishlistVM = WishlistViewModel()
    @StateObject private var keyboardObserver = KeyboardObserver()
    
    private let placesRepo = PlacesRepository()
    
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        
        let user = UserViewModel()
        let loop = LoopViewModel()
        
        
        _userVM = StateObject(wrappedValue: user)
        _loopVM = StateObject(wrappedValue: loop)
        _placeVM = StateObject(wrappedValue: PlaceViewModel())
        _postsVM = StateObject(wrappedValue: ExplorePostsViewModel(
            loopViewModel: loop,
            userViewModel: user
        ))
        
        NotificationManager.shared.requestAuthorization()
        
        FirebaseApp.configure()// This needs to run after every view model and stuff has initialised
        
        _createPostVM = StateObject(wrappedValue: CreatePostViewModel(
          loopVM: loop,
          userVM: user,
        ))
        
        
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userVM)
                .environmentObject(loopVM)
                .environmentObject(placeVM)
                .environmentObject(postsVM)
                .environmentObject(locationVM)
                .environmentObject(locationManager)
                .environmentObject(createPostVM)
                .environmentObject(discoverVM)
                .environmentObject(wishlistVM)
                .environmentObject(keyboardObserver)
        }
    }
    

}


/// Overall project general resources
///https://supabase.com/docs/guides/database/overview
///https://developer.apple.com/documentation/swift/asyncstream
///https://firebase.google.com/docs/firestore/query-data/get-data#custom_objects
///https://youtu.be/fjZd1CwjlxQ?si=QX0O9FLNWKWcVWJp
///https://youtu.be/LExN1t6QhVQ?si=2tB6GdOEuxOND4Bg
///https://youtu.be/gNywPlVzgiI?si=6hXAaMuw9TejJVOA
///https://gitea.osgeo.org/postgis/postgis
///https://youtu.be/Ek_r-7aRp3A?si=C0fJujV0rBiRrvwq
///https://medium.com/@canakyildz/advanced-swiftui-state-management-3816d804477e // This was helpful in helping me relate to my kotlin experience.
///
///NOTE: More resources are generally added at the bottom of the appropriate files.
///Ps: Finally got to clear my google history.
