//
//  DiscoverView.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/9/2025.
//

import SwiftUI


struct DiscoverPlace: Identifiable , Hashable {
    let id : UUID
    let name: String
    let hypes: Int
    let type: String
    let image: String
    let trending: Bool
    let description: String
    let createdAt: Date
}

enum FilteredViewType {
    case mostHyped
    case weekly
    case today
    case all
}

struct DiscoverView: View {
    // MARK: View State
    // Tracks active section tab, search query, and selected items for navigation
    @State private var activeSection = "discover"
    @State private var searchQuery: String = ""
    @EnvironmentObject var discoverVM: DiscoverViewModel
    @State private var selectedPlace: DiscoverPlace?
    @State private var selectedEvent: EventItem?
    @State private var selectedActivity: ActivityItem?
    
    var body: some View {
        VStack(spacing: 16) {
            // MARK: Search Bar Section
            // Text field that triggers search across places, events, and activities
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search the vibe... 🔍✨", text: $searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchQuery) { newValue in
                        handleSearch(newValue)
                    }
            }
            .padding()
            .background(AppColors.cardBackground)
            .cornerRadius(20)
            .padding(.horizontal)
            // MARK: Navigation Section
            // Tab bar for switching between discover, events, and activities sections
            TopNavBar(activeSection: $activeSection)
            
            Divider()
                   .background(Color.black.opacity(0.1))
                   .padding(.horizontal)
            // MARK: Content Section
            // Shows search results when query is active, otherwise shows active section content
            ScrollView {
                if !searchQuery.isEmpty {
                    SearchResultsView(
                            activeSection: activeSection,
                            onSelectPlace: { selectedPlace = $0 },
                            onSelectEvent: { selectedEvent = $0 },
                            onSelectActivity: { selectedActivity = $0 },
                            searchQuery: $searchQuery
                        )
                } else {
                    switch activeSection {
                    case "discover":
                        DiscoverPage()
                    case "events":
                        EventsView()
                    case "activities":
                        ActivitiesView()
                    default:
                        DiscoverPage()
                    }
                }
            }
        }
        .padding(.top)
        .background(AppColors.screenBackground.ignoresSafeArea())
        .navigationDestination(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
        .navigationDestination(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
        .navigationDestination(item: $selectedActivity) { activity in
            ActivityDetailView(activity: activity)
        }
    }
    // MARK: Search Logic
    // Handles search query changes and triggers view model search function
    private func handleSearch(_ text: String) {
        guard !text.isEmpty else {
            discoverVM.searchResultsPlaces = []
            discoverVM.searchResultsEvents = []
            discoverVM.searchResultsActivities = []
            return
        }

        switch activeSection {
        case "discover":
            discoverVM.searchPlaces(text)
        case "events":
            discoverVM.searchEvents(text)
        case "activities":
            discoverVM.searchActivities(text)
        default:
            break
        }
    }
    

}


struct DiscoverPage: View {
    @EnvironmentObject var discoverVM: DiscoverViewModel
    @EnvironmentObject var loopVM: LoopViewModel
    @State private var selectedPlace: DiscoverPlace?

    var body: some View {
        Group {
            if discoverVM.isLoading {
                ProgressView("Loading places...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = discoverVM.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await discoverVM.loadPlaces() }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        SectionHeaderDiscover(title: "Most Hyped 🔥", icon: "bolt.fill", colors: [.orange, .red])

                        GridSection(places: discoverVM.mostHyped) { place in
                            selectedPlace = place
                        }

                        SectionHeaderDiscover(title: "Weekly Winners 📈", icon: "calendar", colors: [.blue, .purple])

                        VStack(spacing: 12) {
                            ForEach(discoverVM.weekly) { place in
                        HStack {
                            AsyncImage(url: URL(string: place.image)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                AppColors.secondaryText.opacity(0.3)
                            }
                            .frame(width: 64, height: 64)
                            .cornerRadius(12)

                            VStack(alignment: .leading) {
                                Text(place.name)
                                    .font(.headline)
                                    .foregroundColor(AppColors.primaryText)
                                HStack {
                                    Text(place.type)
                                        .font(.caption)
                                        .padding(4)
                                        .background(AppColors.categoryBadge)
                                        .cornerRadius(8)
                                    Spacer()
                                    Label("\(place.hypes)", systemImage: "bolt.fill")
                                        .font(.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                        }
                        .padding()
                        .background(AppColors.cardBackground)
                        .cornerRadius(16)
                        .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 1)
                        .onTapGesture {
                            selectedPlace = place
                        }
                    }
                }
                .padding(.horizontal)

                        SectionHeaderDiscover(title: "Today's Picks ⭐", icon: "star.fill", colors: [Color.green, Color.teal])

                        GridSection(places: discoverVM.today) { place in
                            selectedPlace = place
                        }
                    }
                }
                .background(AppColors.screenBackground)
                .navigationDestination(item: $selectedPlace) { place in
                    PlaceDetailView(place: place)
                }
            }
        }
        .task {
            await discoverVM.loadPlaces()
        }
        .onChange(of: loopVM.activeLoop?.id) { _ in
            // Reload places when active loop changes
            Task {
                await discoverVM.loadPlaces()
            }
        }
    }
}




struct GridSection: View {
    let places: [DiscoverPlace]
    var onSelect: (DiscoverPlace) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(places) { place in
                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: URL(string: place.image)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            AppColors.secondaryText.opacity(0.3)
                        }
                        .frame(height: 80)
                        .cornerRadius(12)

                        if place.trending {
                            Circle()
                                .fill(AppColors.trendingBadge)
                                .frame(width: 16, height: 16)
                                .overlay(Image(systemName: "flame.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white))
                                .padding(4)
                        }
                    }

                    Text(place.name)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(AppColors.primaryText)

                    HStack {
                        Text(place.type)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.categoryBadge)
                            .cornerRadius(8)
                        Spacer()
                        Label("\(place.hypes)", systemImage: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                .padding(6)
                .background(AppColors.cardBackground)
                .cornerRadius(12)
                .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 1)
                .onTapGesture {
                    onSelect(place)   
                }
            }
        }
        .padding(.horizontal)
    }
}


struct SectionHeaderDiscover: View {
    let title: String
    let icon: String
    let colors: [Color]
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: 24, height: 24)
                .overlay(Image(systemName: icon).foregroundColor(.white).font(.system(size: 12)))
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal)
    }
}





struct EventItem: Identifiable, Hashable {
    let id : UUID
    let name: String
    let date: String
    let time: String
    let location: String
    let price: String
    let attendees: Int
    let hypes: Int
    let image: String
    let ticketUrl: String
    let category: String
    let featured: Bool
    let description: String
}



struct TopNavBar: View {
    @Binding var activeSection: String
    
    var body: some View {
        HStack(spacing: 8) {
            NavButton(
                title: "Discover",
                icon: "chart.line.uptrend.xyaxis",
                isActive: activeSection == "discover",
                colors: [.purple, .pink]
            ) { activeSection = "discover" }
            
            NavButton(
                title: "Events",
                icon: "calendar",
                isActive: activeSection == "events",
                colors: [.blue, .cyan]
            ) { activeSection = "events" }
            
            NavButton(
                title: "Activities",
                icon: "music.note",
                isActive: activeSection == "activities",
                colors: [.green, .teal]
            ) { activeSection = "activities" }
        }
        .padding(6)
        .background(AppColors.cardBackground)
        .cornerRadius(20)
        .shadow(color: AppColors.cardShadow, radius: 3, x: 0, y: 1)
        .padding(.horizontal)
    }
}



struct NavButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let colors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isActive {
                        LinearGradient(colors: colors,
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    } else {
                        AppColors.cardBackground
                    }
                }
            )
            .foregroundColor(isActive ? .white : AppColors.secondaryText)
            .cornerRadius(16)
            .shadow(color: isActive ? AppColors.cardShadow : .clear, radius: 2, x: 0, y: 1)
        }
    }
}




struct EventCard: View {
    let event: EventItem
    
    var body: some View {
        
        NavigationLink(destination: EventDetailView(event: event)) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: URL(string: event.image)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        AppColors.secondaryText.opacity(0.3)
                    }
                    .frame(height: 180)
                    .clipped()
                    
                    // Featured badge
                    if event.featured {
                        Text("Featured")
                            .font(.caption2).bold()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(AppColors.trendingBadge)
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .padding(8)
                    }
                    
                    // Price tag
                    HStack {
                        Spacer()
                        Text(event.price)
                            .font(.caption).bold()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .padding(8)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.category)
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppColors.categoryBadge)
                        .cornerRadius(10)
                    
                    Text(event.name)
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    Label("\(event.date) • \(event.time)", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 16) {
                        Label("\(event.attendees)", systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Label("\(event.hypes)", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    
                    HStack {
                        Button(action: {
                            if let url = URL(string: event.ticketUrl) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Label("Get Tickets", systemImage: "ticket.fill")
                                .font(.subheadline).bold()
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(20)
                                .foregroundColor(.white)
                        }
                        
                    }
                    .padding(.top, 8)
                }
                .padding()
                .background(AppColors.cardBackground)
                .cornerRadius(20)
                .shadow(color: AppColors.cardShadow, radius: 5, x: 0, y: 2)
            }
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}


struct EventsView: View {
    @StateObject private var vm = EventsDiscoverViewModel()
    @EnvironmentObject var loopVM: LoopViewModel
    
    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading events...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = vm.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await vm.loadEvents() }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Upcoming Events")
                                .font(.headline)
                                .foregroundColor(AppColors.primaryText)
                        }
                        .padding(.horizontal)
                        
                        VStack(spacing: 20) {
                            ForEach(vm.events) { event in
                                EventCard(event: event)
                            }
                        }
                    }
                    .padding(.top)
                }
            }
        }
        .background(AppColors.screenBackground)
        .task {
            await vm.loadEvents()
        }
        .onChange(of: loopVM.activeLoop?.id) { _ in
            // Reload events when active loop changes
            Task {
                await vm.loadEvents()
            }
        }
    }
}

struct SearchResultsView: View {
    @EnvironmentObject var vm: DiscoverViewModel
    let activeSection: String
    let onSelectPlace: (DiscoverPlace) -> Void
    let onSelectEvent: (EventItem) -> Void
    let onSelectActivity: (ActivityItem) -> Void
    @Binding var searchQuery: String
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                
                // --- PLACES ---
                if activeSection == "discover" {
                    if vm.searchResultsPlaces.isEmpty {
                        Text("No places found ")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(vm.searchResultsPlaces, id: \.self) { place in
                            Button {
                                onSelectPlace(place)
                            } label: {
                                HStack {
                                    AsyncImage(url: URL(string: place.image)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                    }
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(10)

                                    VStack(alignment: .leading) {
                                        Text(place.name).bold()
                                        Text(place.type).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(AppColors.cardBackground)
                                .cornerRadius(12)
                            }
                        }

                    }
                }
                
                // --- EVENTS ---
                if activeSection == "events" {
                    if vm.searchResultsEvents.isEmpty {
                        Text("No events found 😔")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(vm.searchResultsEvents) { event in
                            Button {
                                onSelectEvent(event)
                            } label: {
                                EventCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }

                    }
                }

                // --- ACTIVITIES ---
                if activeSection == "activities" {
                    if vm.searchResultsActivities.isEmpty {
                        Text("No activities found 😔")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(vm.searchResultsActivities, id: \.name) { activity in
                            Button {
                                onSelectActivity(activity)
                            } label: {
                                HStack {
                                    AsyncImage(url: URL(string: activity.image)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                    }
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(10)

                                    VStack(alignment: .leading) {
                                        Text(activity.name).bold()
                                        Text(activity.type).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(AppColors.cardBackground)
                                .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}
