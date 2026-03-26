//
//  AssetDetailSheet.swift
//  Locolo
//
//  ok so this whole file is basically my asset detail page.
//  I forced it to always be dark mode because honestly the UI
//  just looks better dark and I cannot deal with light mode mismatch with the scene kit view.
//
//

import SwiftUI
import CoreLocation


struct AssetDetailSheet: View {
    let asset: DigitalAsset
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userVM: UserViewModel
    
    // I just override the whole colour scheme.
    // I tried mixing light/dark earlier and it looked ugly + too bright.
    private let isDark = true
    
    @State private var showARView = false
    @State private var showOffers = false
    @State private var showCreateOffer = false
    @State private var distanceText: String = "--"
    @State private var distanceMeters: Double?
    @State private var isAboutExpanded: Bool = false
    @State private var resolvedLocationName: String = "Unknown"
    @State private var isWishlisted: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                
                // Background always full black. Less sensory chaos.
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // TOP ~60% → SceneKit preview
                    // earlier I tried 50% but felt too cramped,
                    // so I increased a bit.
                    AssetSceneView(asset: asset)
                        .frame(height: UIScreen.main.bounds.height * 0.60)
                        .background(Color.black)
                        .padding(.bottom, -20)  // I push it down so fog blends with card
                        .clipped()
                        .overlay(
                            // This little gradient helps avoid harsh line cut 
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.0),
                                    Color.black.opacity(0.35),
                                    Color.black.opacity(0.95)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 80),
                            alignment: .bottom
                        )
                    
                    // bottom card
                    bottomCard
                        .frame(height: UIScreen.main.bounds.height * 0.50)
                }
            }
            
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        // kept this simple, I was using a fancy custom back button before
                        // but honestly this one is faster and clean.
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.white)
                    }
                }
            }
            .onAppear {
                computeDistance()
                reverseGeocodeAssetLocation()
            }
        }
    }
}

extension AssetDetailSheet {
    
    // I check if the asset belongs to current user
    private var isCurrentUserOwner: Bool {
        userVM.currentUser?.id == asset.userId
    }
    
    // AR button only appears if you're close to the asset
    // I put 150m because earlier 100m felt too strict.
    private var shouldShowARButton: Bool {
        guard (asset.interactionType == "ar" || asset.panoramaUrl != nil),
              let meters = distanceMeters else { return false }
        return meters <= 150
    }
    
    // MARK: - Bottom Card
    private var bottomCard: some View {
        ZStack {
            
            // Always dark gradient.
            // I lowered opacity because earlier it was too shiny
            // and hurting my eyes at night.
            RoundedRectangle(cornerRadius: 26)
                .fill(AppColors.cardGradientDark)
                .opacity(0.92)
                .background(.ultraThinMaterial.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .shadow(color: Color.black.opacity(0.8), radius: 20, x: 0, y: -4)
            
            // scroll content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    topRow
                    titleSection
                    hypeOnlySection
                    aboutSection
                    priceSection
                    buttonSection
                }
                .padding(22)
            }
        }
        .padding(.horizontal, 20)
    }
    
    
    // MARK: - TOP ROW
    private var topRow: some View {
        HStack(alignment: .top) {
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // Location + distance
                    Label(resolvedLocationName, systemImage: "mappin.and.ellipse")
                        .foregroundColor(.white.opacity(0.85))
                        .font(.subheadline.weight(.semibold))
                    
                    if distanceText != "--" {
                        Text(distanceText)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.pink.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                
                // type badge
                Text(asset.fileType.uppercased())
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                
                // creation date
                Text(asset.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                
                // wishlist button
                Button { isWishlisted.toggle() } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.09))
                            .frame(width: 30, height: 30)
                        Image(systemName: isWishlisted ? "heart.fill" : "heart")
                            .foregroundColor(isWishlisted ? .pink : .white)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    
    // MARK: - TITLE
    private var titleSection: some View {
        // title looks cleaner when it's bold white
        Text(asset.name ?? "Untitled Artwork")
            .font(.title2.bold())
            .foregroundColor(.white)
    }
    
    
    // MARK: - HYPE
    private var hypeOnlySection: some View {
        HStack {
            // I made hype yellow because with purple it didn’t pop.
            Label("\(asset.hypeCount)", systemImage: "bolt.fill")
                .foregroundColor(.yellow)
            Spacer()
        }
    }
    
    
    // MARK: - ABOUT
    private var aboutSection: some View {
        Group {
            if let desc = asset.description, !desc.isEmpty {
                // I kept this disclosureGroup because long descriptions
                // were ruining the layout visually.
                DisclosureGroup(isExpanded: $isAboutExpanded) {
                    Text(desc)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 4)
                } label: {
                    Text("About this artwork")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    
    // MARK: - PRICE
    private var priceSection: some View {
        Group {
            if let price = asset.currentValue {
                // I tried making this bigger But looked kinda weird.
                Text("$\(price, specifier: "%.0f")")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .padding(.top, 4)
            }
        }
    }
    
    
    // MARK: - BUTTONS
    private var buttonSection: some View {
        VStack(spacing: 12) {

            // BUY NOW
            if asset.isForSale == true && !isCurrentUserOwner {
                Button {
                    // still TODO — I will add purchase flow later
                } label: {
                    HStack {
                        Image(systemName: "bag.fill")
                        Text("Buy Now")
                    }
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.purplePinkGradient)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
            }
            
            // OFFERS
            if asset.acceptsOffers == true {
                if isCurrentUserOwner {
                    
                    // Owner can see offers they got
                    Button { showOffers = true } label: {
                        MatteOfferButton(title: "View Offers")
                    }
                    .sheet(isPresented: $showOffers) {
                        OfferListView(assetId: asset.id)
                    }
                    
                } else {
                    
                    // Non-owner can make offer
                    Button { showCreateOffer = true } label: {
                        MatteOfferButton(title: "Make Offer")
                    }
                    .sheet(isPresented: $showCreateOffer) {
                        CreateOfferView(assetId: asset.id)
                    }
                }
            }

            // AR VIEW button
            if shouldShowARButton {
                Button { showARView = true } label: {
                    Label("AR View", systemImage: "arkit")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppColors.blueCyanMutedGradient)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .sheet(isPresented: $showARView) {
                    // temporary placeholder
                    Text("AR Coming Soon")
                }
            }
        }
    }
}


// MARK: - DISTANCE CALCULATION
extension AssetDetailSheet {
    private func computeDistance() {
        guard let lat = asset.latitude,
              let lon = asset.longitude else { return }
        
        let manager = LocationManager.shared
        guard let coord = manager.userLocation ?? manager.latestStoredLocation else {
            distanceText = "--"
            return
        }
        
        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let assetLoc = CLLocation(latitude: lat, longitude: lon)
        
        let meters = userLoc.distance(from: assetLoc)
        distanceMeters = meters
        
        // I kept distance formatting simple
        if meters < 100 {
            distanceText = "\(Int(meters)) m"
        } else if meters < 1000 {
            distanceText = "\(Int(meters)) m"
        } else {
            distanceText = String(format: "%.1f km", meters/1000)
        }
    }
    
    private func reverseGeocodeAssetLocation() {
        guard let lat = asset.latitude,
              let lon = asset.longitude else { return }

        let location = CLLocation(latitude: lat, longitude: lon)
        let geocoder = CLGeocoder()

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let place = placemarks?.first {
                // prioritise: Suburb, City, Country (you can tune this)
                let name =
                    place.locality ??
                    place.subLocality ??
                    place.administrativeArea ??
                    place.country ??
                    "Unknown"

                DispatchQueue.main.async {
                    resolvedLocationName = name
                }
            }
        }
    }
}


// MARK: - Matte Offer Button (looks clean + shiny)
struct MatteOfferButton: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    // faint blur base
                    Color.white.opacity(0.06).blur(radius: 2)
                    
                    // subtle vertical gloss
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blur(radius: 8)

                    // clean border
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.purple.opacity(0.6),
                                    Color.pink.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.1
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
