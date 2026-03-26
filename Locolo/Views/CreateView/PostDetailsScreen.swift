//
//  PostDetailsScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 9/10/2025.
//

import SwiftUI
import PhotosUI
import Supabase

struct PostDetailsScreen: View {

    @EnvironmentObject var createPostVM: CreatePostViewModel
    @EnvironmentObject var locationVM: LocationViewModel
    @EnvironmentObject var placeVM: PlaceViewModel
    @EnvironmentObject var loopVM: LoopViewModel
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var locationManager: LocationManager

    @State private var expandedSection: ExpandableSection? = nil
    @State private var query = ""
    @State private var privacy = "Private"
    @State private var showCamera = false
    @State private var showFullPlaceForm = false
    @State private var currentImageIndex = 0

    @State private var quickTags = ["#vibes", "#fire", "#aesthetic", "#gen-z", "#cyberpunk"]
    
    // MARK: EVENT POSTING FLOW - State for event selection
    @State private var availableEvents: [Event] = []
    @State private var isLoadingEvents = false

    let onNext: () -> Void

    var body: some View {
        
        ScrollView {
            VStack(spacing: 28) {
                // MARK: Header Image Carousel
                // Displays all memory images in a swipeable TabView carousel
                PostImageCarouselView(
                       images: $createPostVM.memoryImages,
                       selectedPlace: $createPostVM.selectedPlace
                   )

                
                // MARK: - Caption + Tags
                VStack(alignment: .leading, spacing: 12) {
                    TextField("What's the vibe? Drop your thoughts... ✨",
                              text: $createPostVM.description,
                              axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .padding()
                    .background(LinearGradient(colors: [.purple.opacity(0.2), .blue.opacity(0.1)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(16)
                    .foregroundColor(.primary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(quickTags, id: \.self) { tag in
                                TagButton(text: tag,
                                          isSelected: createPostVM.tags.contains(tag)) {
                                    toggleTag(tag)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal)
                // MARK: Expandable Cards Section
                // Interactive cards for location tagging, memory, music, and privacy settings
                ExpandableCard(
                    icon: "mappin.circle.fill",
                    title: "Tag a location",
                    subtitle: createPostVM.selectedPlace?.name ?? "Help people discover this spot",
                    color: .blue,
                    isExpanded: expandedSection == .location
                ) {
                    locationSection
                }
                .onTapGesture { toggleSection(.location) }

                ExpandableCard(
                    icon: "camera.fill",
                    title: "Add Memory",
                    subtitle: "BeReal-style behind-the-scenes",
                    color: .orange,
                    isExpanded: expandedSection == .memory
                ) {
                    memorySection
                }
                .onTapGesture { toggleSection(.memory) }

                ExpandableCard(
                    icon: "music.note",
                    title: "Add Music",
                    subtitle: "Set the vibe with a soundtrack",
                    color: .purple,
                    isExpanded: expandedSection == .music
                ) {
                    VStack(spacing: 8) {
                        Text("Music linking coming soon 🎶")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .onTapGesture { toggleSection(.music) }

                ExpandableCard(
                    icon: "globe",
                    title: "Privacy & Settings",
                    subtitle: privacy,
                    color: .indigo,
                    isExpanded: expandedSection == .privacy
                ) {
                    Picker("Privacy", selection: $privacy) {
                        Text("Public").tag("Public")
                        Text("Loops Only").tag("Loops")
                        Text("Private").tag("Private")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .onTapGesture { toggleSection(.privacy) }
                
                // MARK: EVENT POSTING FLOW - Post Type Toggle Card
                ExpandableCard(
                    icon: "calendar.badge.plus",
                    title: "Post Type",
                    subtitle: createPostVM.postType == .normal ? "Normal post" : "Event post",
                    color: .green,
                    isExpanded: expandedSection == .postType
                ) {
                    postTypeSection
                }
                .onTapGesture { toggleSection(.postType) }
                
                // MARK: Continue Button
                // Navigation button to proceed to preview screen
                Button {
                    onNext()
                } label: {
                    Text("Preview Post 🚀")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.pink, .purple],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .padding(.top)
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                createPostVM.digitalMemoryImage = image
                showCamera = false
            }
        }
        .sheet(isPresented: $showFullPlaceForm) {
            AddNewPlaceSection(
                loopVM: loopVM,
                userVM: userVM,
                locationVM: LocationViewModel(),
                placeVM: placeVM,
                createPostVM: createPostVM
            ) { showFullPlaceForm = false }
        }
        .navigationTitle("Create Post")
        .navigationBarTitleDisplayMode(.inline)
        // MARK: EVENT POSTING FLOW - Load events when view appears or post type changes
        .onAppear {
            if createPostVM.postType == .event {
                loadEvents()
            }
        }
        .onChange(of: createPostVM.postType) { newType in
            if newType == .event && availableEvents.isEmpty {
                loadEvents()
            }
        }
    }
}

// MARK: Expandable Sections Content
extension PostDetailsScreen {
    // MARK: Location Section
    // Shows selected place info and search functionality for tagging locations
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: Selected Place Display
            // Shows the currently selected place name and source if one is chosen
            if let selectedPlace = createPostVM.selectedPlace {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPlace.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Locolo Place")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 6)
                .transition(.opacity)
            }
            // MARK: Place Search Section
            // Text field that searches both Locolo database and Apple Maps when user types
            TextField("Search places...", text: $query)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: query) { newValue in
                    Task {
                        if newValue.count > 2 {
                            await placeVM.searchPlaceFlow(
                                query: newValue,
                                userLat: locationManager.userLocation?.latitude,
                                userLon: locationManager.userLocation?.longitude,
                                radiusMeters: 5000,
                                loopID: UUID(uuidString: loopVM.activeLoop?.id ?? ""),
                                postedBy: userVM.currentUser?.id
                            )
                        } else {
                            placeVM.placesResult = []
                        }
                    }
                }

            if placeVM.isLoading {
                ProgressView("Searching…")
            } else if !placeVM.placesResult.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(placeVM.placesResult, id: \.id) { result in
                        Button {
                            handlePlaceSelection(result)
                        } label: {
                            HStack {
                                Text(result.place?.name ?? "Unknown")
                                    .bold()
                                    .foregroundColor(.blue)
                                Spacer()
                                Text(result.source == .database ? "Locolo" : "Apple")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            // MARK: Create New Place Button
            // Button that opens form to add a new place if search results are empty
            Button {
                showFullPlaceForm = true
            } label: {
                Label("Create new place", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
            }
            .padding(.top, 4)
        }
    }
    // MARK: Memory Section
    // Allows user to capture or select a BeReal style behind the scenes memory photo
    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = createPostVM.digitalMemoryImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            createPostVM.digitalMemoryImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white)
                                .padding(6)
                        }
                    }
            } else {
                Button {
                    showCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Click Now")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(12)
                }
            }
        }
    }
    // MARK: Section Toggle Logic
    // Expands or collapses an expandable section with spring animation
    private func toggleSection(_ section: ExpandableSection) {
        withAnimation(.spring()) {
            expandedSection = (expandedSection == section) ? nil : section
        }
    }
    // MARK: Tag Toggle Logic
    // Adds or removes a tag from the post tags array
    private func toggleTag(_ tag: String) {
        if createPostVM.tags.contains(tag) {
            createPostVM.tags.removeAll { $0 == tag }
        } else {
            createPostVM.tags.append(tag)
        }
    }
    // MARK: Place Selection Handler
    // Handles selection of place from search results, persists Apple Maps places to database
    private func handlePlaceSelection(_ result: PlaceResult) {
        switch result.source {
        case .database:
            placeVM.selectedPlace = result.place
            createPostVM.selectedPlace = result.place
            createPostVM.selectedPlaceSource = .database
            expandedSection = nil
            
        case .appleMap:
            guard let location = result.location else { return }
            Task {
                do {
                    let persistedLocation = try await locationVM.addLocation(location)
                    var applePlace = result.place
                    applePlace?.locationId = persistedLocation.id
                    
                    await MainActor.run {
                        placeVM.selectedPlace = applePlace
                        createPostVM.selectedPlace = applePlace
                        createPostVM.selectedPlaceSource = .appleMap
                        expandedSection = nil
                    }
                } catch {
                    await MainActor.run {
                        placeVM.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: ========================================
    // MARK: EVENT POSTING FLOW - ADDED RECENTLY
    // MARK: ========================================
    // The following code was added to support event posting functionality:
    // - Post Type section with toggle between Normal/Event post
    // - Event picker that loads events from the active loop
    // - Context selector (Announcement/Hype/Memory)
    // - Event loading logic
    
    // MARK: Post Type Section
    private var postTypeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toggle between Normal and Event post
            Picker("Post Type", selection: $createPostVM.postType) {
                Text("Normal Post").tag(PostType.normal)
                Text("Event Post").tag(PostType.event)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // If Event post is selected, show event selection/creation options
            if createPostVM.postType == .event {
                VStack(alignment: .leading, spacing: 16) {
                    // Toggle between selecting existing event or creating new one
                    Picker("Event Option", selection: $createPostVM.isCreatingNewEvent) {
                        Text("Select Existing").tag(false)
                        Text("Create New").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if createPostVM.isCreatingNewEvent {
                        // EVENT POSTING FLOW: Form for creating new event
                        newEventForm
                    } else {
                        // Select existing event
                        existingEventPicker
                    }
                    
                    // Show context selector if event is selected/created
                    if (createPostVM.isCreatingNewEvent && !createPostVM.newEventName.isEmpty) || createPostVM.selectedEvent != nil {
                        eventContextSelector
                    }
                }
            }
        }
    }
    
    // MARK: Existing Event Picker
    private var existingEventPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Event")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            if isLoadingEvents {
                ProgressView("Loading events...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if availableEvents.isEmpty {
                Text("No events available in this loop")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Picker("Event", selection: $createPostVM.selectedEvent) {
                    Text("Choose an event...").tag(Event?.none)
                    ForEach(availableEvents, id: \.id) { event in
                        Text(event.name).tag(Event?.some(event))
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
        }
    }
    
    // MARK: New Event Form
    private var newEventForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create New Event")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            TextField("Event Name *", text: $createPostVM.newEventName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("Description (optional)", text: $createPostVM.newEventDescription, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3, reservesSpace: true)
            
            DatePicker("Start Date & Time *", selection: $createPostVM.newEventStartDate, displayedComponents: [.date, .hourAndMinute])
            
            DatePicker("End Date & Time *", selection: $createPostVM.newEventEndDate, displayedComponents: [.date, .hourAndMinute])
            
            // MARK: Pricing Section - Constraint compliant
            VStack(alignment: .leading, spacing: 8) {
                Text("Pricing")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                
                Toggle("Free Event", isOn: $createPostVM.newEventIsFree)
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                
                if !createPostVM.newEventIsFree {
                    // Paid event: require price > 0 and currency
                    HStack {
                        TextField("Price *", text: $createPostVM.newEventPrice)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Picker("Currency", selection: $createPostVM.newEventCurrency) {
                            Text("AUD").tag("AUD")
                            Text("USD").tag("USD")
                            Text("EUR").tag("EUR")
                            Text("GBP").tag("GBP")
                            Text("INR").tag("INR")
                            Text("JPY").tag("JPY")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 100)
                    }
                    
                    if !createPostVM.newEventPrice.isEmpty {
                        if let priceValue = Double(createPostVM.newEventPrice.trimmingCharacters(in: .whitespaces)),
                           priceValue <= 0 {
                            Text("Price must be greater than 0")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            
            // Event image picker (optional)
            if let eventImage = createPostVM.newEventImage {
                Image(uiImage: eventImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            createPostVM.newEventImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white)
                                .padding(4)
                        }
                    }
            } else {
                Button {
                    // TODO: Add image picker
                    print(" [EVENT POSTING] Image picker not yet implemented")
                } label: {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text("Add Event Image (optional)")
                    }
                    .font(.subheadline)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: Event Context Selector
    private var eventContextSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Post Context")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            Picker("Context", selection: $createPostVM.eventContext) {
                Text("Select context...").tag(EventContext?.none)
                ForEach(EventContext.allCases, id: \.self) { context in
                    Text(context.displayName).tag(EventContext?.some(context))
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            // Encouragement message
            if createPostVM.eventContext != nil {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Share event-specific details in your caption!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: Load Events Function
    private func loadEvents() {
        isLoadingEvents = true
        Task {
            do {
                // EVENT POSTING FLOW: Use repository method instead of direct Supabase call
                let eventsRepo = EventsDiscoverRepository()
                let response = try await eventsRepo.fetchRawEvents()
                
                await MainActor.run {
                    availableEvents = response
                    isLoadingEvents = false
                    print(" [EVENT POSTING] Loaded \(response.count) events")
                }
            } catch {
                await MainActor.run {
                    isLoadingEvents = false
                    print(" [EVENT POSTING] Failed to load events: \(error)")
                }
            }
        }
    }
}



// MARK: - Expandable Card Component
struct ExpandableCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isExpanded: Bool
    let content: Content

    init(icon: String, title: String, subtitle: String, color: Color, isExpanded: Bool, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(LinearGradient(colors: [color.opacity(0.1), .purple.opacity(0.05)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing))
            .cornerRadius(14)

            if isExpanded {
                content
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Supporting Types
enum ExpandableSection {
    case location, memory, music, privacy, postType  // EVENT POSTING FLOW: Added postType case
}

struct TagButton: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.pink.opacity(0.8) : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(10)
        }
    }
}

struct CameraCaptureView: View {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Spacer()
            Text("📸 Simulated Camera")
                .font(.headline)
            Button("Capture Sample Image") {
                onCapture(UIImage(systemName: "camera.fill")!)
                dismiss()
            }
            .padding()
            Spacer()
        }
    }
}








struct PostImageCarouselView: View {
    @Binding var images: [UIImage]
    @Binding var selectedPlace: Place?
    
    @State private var currentIndex = 0

    var body: some View {
        VStack {
            if images.isEmpty {
                placeholderView
            } else {
                carouselView
            }
        }
    }
}

// MARK: - Subviews
extension PostImageCarouselView {
    
    private var carouselView: some View {
        VStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    carouselImage(image, at: index)
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            .frame(height: 260)
            .cornerRadius(20)
            .padding(.horizontal)
            .id(images.count) // refresh layout when count changes
            
            if let place = selectedPlace {
                placeTagView(place)
                    .padding(.horizontal)
                    .offset(y: -40)
            }
        }
    }
    
    private func carouselImage(_ image: UIImage, at index: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
                .cornerRadius(20)
                .overlay(alignment: .topTrailing) {
                    removeButton(at: index)
                }
        }
    }
    
    private func removeButton(at index: Int) -> some View {
        Button {
            withAnimation(.spring()) {
                if index < images.count {
                    images.remove(at: index)
                }
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
                .padding(8)
        }
    }
    
    private func placeTagView(_ place: Place) -> some View {
        HStack {
            Label(place.name, systemImage: "mappin.and.ellipse")
                .font(.subheadline.bold())
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            Spacer()
        }
    }
    
    private var placeholderView: some View {
        LinearGradient(
            colors: [.purple.opacity(0.5), .pink.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .cornerRadius(20)
        .overlay(
            VStack {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.9))
                Text("No image added yet")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.subheadline)
            }
        )
        .padding(.horizontal)
    }
}
