//
//  EventPostView.swift
//  Locolo
//
//  Created for event announcement posts in the feed
//

import SwiftUI

// MARK: - EventPostView
/// Render rule: use this card when post.eventId != nil && post.eventContext == "event_announcement"
struct EventPostView: View {
    let post: Post
    let event: Event
    @Binding var selectedPost: Post?
    let currentUserId: UUID
    
    @StateObject private var hypeVM: HypeViewModel
    @StateObject private var echoVM: EchoViewModel
    @State private var style: PosterStyle = .hero
    @State private var showCalendarSheet = false
    @State private var showEchoSheet = false
    
    init(post: Post, event: Event, selectedPost: Binding<Post?>, currentUserId: UUID) {
        self.post = post
        self.event = event
        _selectedPost = selectedPost
        self.currentUserId = currentUserId
        _hypeVM = StateObject(wrappedValue: HypeViewModel(post: post, currentUserId: currentUserId))
        _echoVM = StateObject(wrappedValue: EchoViewModel(post: post))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Full-width background image
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = width * 1.25 // 4:5 aspect ratio
                
                ZStack(alignment: .bottom) {
                    // Background image
                    posterBackground
                        .frame(width: width, height: height)
                        .clipped()
                    
                    // Gradient overlays for text readability
                    posterOverlays
                        .frame(width: width, height: height)
                    
                    // Content overlay
                    contentOverlay
                        .frame(width: width, height: height)
                }
                .frame(width: width, height: height)
            }
            .aspectRatio(4/5, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            
            // Bottom interaction bar (like Instagram)
            interactionBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .background(Color(.systemBackground))
        .onAppear {
            hypeVM.loadHypes()
        }
        .sheet(isPresented: $showCalendarSheet) {
            AddToCalendarView(event: event, post: post)
        }
        .sheet(isPresented: $showEchoSheet) {
            EchoSheet(post: post, vm: echoVM)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .onAppear {
                    echoVM.loadEchoes(for: post)
                }
        }
    }
    
    // MARK: - Background
    private var posterBackground: some View {
        Group {
            if let imageUrlString = event.eventImageUrl, let url = URL(string: imageUrlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackGradient
                    }
                }
            } else if let mediaUrl = post.media {
                AsyncImage(url: mediaUrl) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackGradient
                    }
                }
            } else {
                fallbackGradient
            }
        }
    }
    
    private var fallbackGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.2, green: 0.3, blue: 0.5),
                Color(red: 0.4, green: 0.2, blue: 0.4),
                Color(red: 0.3, green: 0.3, blue: 0.5)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Overlays
    private var posterOverlays: some View {
        ZStack {
            // Top gradient for header readability
            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.6), .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                Spacer()
            }
            
            // Bottom gradient for info readability
            VStack {
                Spacer()
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Content Overlay
    private var contentOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerRow
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Bottom content section
            VStack(alignment: .leading, spacing: 12) {
                // Title
                titleBlock
                
                // Tags
                tagsRow
                
                // Info chips
                infoRow
                
                // CTA button
                ctaButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Header
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // Avatar
            AsyncImage(url: post.author?.avatarUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Circle()
                        .fill(.white.opacity(0.2))
                        .overlay(
                            Text(authorInitials)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(post.author?.username ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    // Status tag (loco, exploro, voyo, etc.)
                    if let tag = post.author?.loopTimeCounters?.first?.status {
                        Text(tag.capitalized)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                Text(isOfficial ? "Official event" : "Event announcement")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            
            // Event badge
            HStack(spacing: 4) {
                if isOfficial {
                    pill("OFFICIAL", size: 10)
                }
                pill("EVENT", size: 10)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var isOfficial: Bool {
        event.postedBy == post.authorId || event.visibility == "public"
    }
    
    private var authorInitials: String {
        let username = post.author?.username ?? "U"
        let components = username.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1)) + String(components[1].prefix(1))
        }
        return String(username.prefix(2)).uppercased()
    }
    
    private func pill(_ text: String, size: CGFloat = 10) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.2))
            .clipShape(Capsule())
    }
    
    // MARK: - Title
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.name)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            
            if let tagline = eventTagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var eventTagline: String? {
        post.caption ?? event.description
    }
    
    // MARK: - Tags Row
    @ViewBuilder
    private var tagsRow: some View {
        if let tags = post.tags, !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Info Row
    private var infoRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let startAt = event.startAt {
                    infoChip(icon: "calendar", text: dateText(from: startAt))
                    infoChip(icon: "clock", text: timeText(from: startAt, endAt: event.endAt))
                }
                
                if let location = locationText, !location.isEmpty {
                    infoChip(
                        icon: event.locationMode == "online" ? "video.fill" : "mappin.circle.fill",
                        text: location
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var locationText: String? {
        if event.locationMode == "online" {
            return "Online"
        } else if event.placeID != nil {
            return "In-Person"
        }
        return nil
    }
    
    private func dateText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
    
    private func timeText(from start: Date, endAt: Date?) -> String {
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "h:mm a"
        
        var text = startFormatter.string(from: start)
        
        if let end = endAt {
            let endFormatter = DateFormatter()
            endFormatter.dateFormat = "h:mm a"
            text += "–" + endFormatter.string(from: end)
        }
        
        return text
    }
    
    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.15))
        .clipShape(Capsule())
        .fixedSize()
    }
    
    // MARK: - CTA Button
    private var ctaButton: some View {
        Button {
            handleCTAAction()
        } label: {
            HStack(spacing: 8) {
                Text(primaryCtaLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var primaryCtaLabel: String {
        if let label = event.officialUrlLabel, !label.isEmpty {
            return label
        }
        if event.locationMode == "online", event.onlineUrl != nil {
            return "Join Event"
        }
        if event.officialUrl != nil {
            return "View Details"
        }
        return "Save Event"
    }
    
    private func handleCTAAction() {
        if let urlString = event.onlineUrl, let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        } else if let urlString = event.officialUrl, let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Interaction Bar
    private var interactionBar: some View {
        HStack(spacing: 20) {
            Button(action: { hypeVM.toggleHype() }) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                    Text("\(hypeVM.hypes.count)")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(hypeVM.isHypedByUser ? .yellow : .primary)
            }
            
            Button(action: {
                selectedPost = post
                showEchoSheet = true
            }) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
            }
            
            Button(action: {
                showCalendarSheet = true
            }) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Poster Style Variants
enum PosterStyle: Equatable {
    case hero
    case countdown
    case strip
    
    var minHeight: CGFloat {
        switch self {
        case .hero: return 400
        case .countdown: return 360
        case .strip: return 240
        }
    }
    
    var maxHeight: CGFloat? {
        switch self {
        case .hero: return 500
        case .countdown: return 440
        case .strip: return 300
        }
    }
    
    var titleSize: CGFloat {
        switch self {
        case .hero: return 32
        case .countdown: return 28
        case .strip: return 24
        }
    }
    
    var titleLineLimit: Int {
        switch self {
        case .hero: return 2
        case .countdown: return 2
        case .strip: return 1
        }
    }
    
    var showsTagline: Bool { self != .strip }
    
    func countdownTitle(from startAt: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: startAt).day ?? 0
        if days <= 0 { return "TODAY" }
        if days == 1 { return "1 DAY" }
        return "\(days) DAYS"
    }
}

// MARK: - EventPostWrapper
/// Wrapper to fetch event data and render EventPostView
struct EventPostWrapper: View {
    let post: Post
    @Binding var selectedPost: Post?
    let currentUserId: UUID
    
    @State private var event: Event?
    @State private var isLoading = true
    
    init(post: Post, selectedPost: Binding<Post?>, currentUserId: UUID? = nil) {
        self.post = post
        _selectedPost = selectedPost
        
        // Get currentUserId from parameter, UserDefaults, or generate a fallback UUID
        if let providedId = currentUserId {
            self.currentUserId = providedId
        } else if let userIdString = SupabaseManager.shared.currentUserId,
                  let userId = UUID(uuidString: userIdString) {
            self.currentUserId = userId
        } else {
            // Fallback: generate a UUID (this shouldn't happen in normal flow)
            self.currentUserId = UUID()
        }
    }
    
    var body: some View {
        Group {
            if let event = event {
                EventPostView(
                    post: post,
                    event: event,
                    selectedPost: $selectedPost,
                    currentUserId: currentUserId
                )
                .frame(maxWidth: .infinity)
                .clipped()
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
            } else {
                // Fallback to regular FeedCell if event fetch fails
                FeedCell(post: post, selectedPost: $selectedPost, currentUserId: currentUserId)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .task {
            await fetchEvent()
        }
    }
    
    private func fetchEvent() async {
        guard let eventId = post.eventId else {
            print("⚠️ [EventPostWrapper] Post has no eventId")
            isLoading = false
            return
        }
        
        print("🔍 [EventPostWrapper] Fetching event with ID: \(eventId.uuidString)")
        let repo = EventsDiscoverRepository()
        do {
            event = try await repo.fetchEventById(eventId)
            if event == nil {
                print("⚠️ [EventPostWrapper] Event not found for ID: \(eventId.uuidString)")
            } else {
                print("✅ [EventPostWrapper] Event found: \(event?.name ?? "Unknown")")
            }
        } catch {
            print("❌ [EventPostWrapper] Failed to fetch event: \(error)")
        }
        isLoading = false
    }
}
