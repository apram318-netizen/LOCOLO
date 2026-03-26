//
//  StandardLocationPost.swift
//  Locolo
//
//  Created by Apramjot Singh on 4/10/2025.
//

// this is the location post view for a post that is just a standard sharing of a certain place with a split 50 - 50 view of media and place card/ details

//possible inclusions I need

// I want to display the user profile pic, username, then the tag if available, time since posted at the top
// then the thoughts/reviews if the user wants it to be a review post  has any reviews added for the place
// Then the media with a side box view of the place card with the place details in it
// then I need the hype and echo location and share buttons in a Hstack
// The place view hovering like a cloud over the place media,
// The full place view needs to be swapable with the media in the post



import SwiftUI
import MapKit

struct StandardLocationPost: View {
    
    @EnvironmentObject var loopVM: LoopViewModel
    
    let post: Post
    let place: Place
    
    // MARK: View State
    @State private var showPlaceInsteadOfMedia = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // MARK: - Header
            HStack(spacing: 10) {
                AsyncImage(url: post.author?.avatarUrl) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    default:
                        Circle().fill(Color.gray.opacity(0.3)).frame(width: 44, height: 44)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(post.author?.username ?? "Unknown")
                            .font(.headline)
                        
                        if let tag = loopVM.activeUserTag {
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                    
                    Text(relativeTime(for: post.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            
            // MARK: - Thoughts / Review
//            if post.isReviewPost {
//                if let reviewText = post.caption {
//                    Text(reviewText)
//                        .font(.body)
//                        .padding(.horizontal)
//                }
//            }
            
            // MARK: - Media or Place View (swappable)
            ZStack(alignment: .bottomTrailing) {
                if showPlaceInsteadOfMedia {
                    PlaceCardView(place: place)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                } else {
                    PostMediaView(post: post)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                }
                
                Button(action: {
                    withAnimation(.spring()) {
                        showPlaceInsteadOfMedia.toggle()
                    }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                }
                .padding(12)
            }
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 4)
            .padding(.horizontal)
            .padding(.top, 4)
            
            // MARK: - Floating Place Cloud over Media
            if !showPlaceInsteadOfMedia {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(.headline)
                        if let city = place.location?.city {
                            Text(city)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.pink)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(radius: 4)
                .padding(.horizontal, 24)
                .offset(y: -40)
            }
            
            // MARK: - Interaction Buttons
            HStack(spacing: 30) {
                Button(action: {}) {
                    Label("Hype", systemImage: "sparkles")
                }
                Button(action: {}) {
                    Label("Echo", systemImage: "message")
                }
                Button(action: {}) {
                    Label("Locate", systemImage: "mappin.and.ellipse")
                }
                Button(action: {}) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.top, -20)
            
            Divider()
        }
        .padding(.bottom)
    }
    
    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}


// MARK: - Subviews


struct PostMediaView: View {
    let post: Post
    
    @EnvironmentObject var createPostVM : CreatePostViewModel
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                
                PostImageCarouselView(
                    images: $createPostVM.memoryImages,
                    selectedPlace: $createPostVM.selectedPlace
                )
                
                if let url = post.media {
                    
//                    AsyncImage(url: url) { phase in
//                        switch phase {
//                        case .success(let img):
//                            img
//                                .resizable()
//                                .scaledToFill()
//                                .frame(width: geo.size.width, height: geo.size.height)
//                                .clipped()
//                        default:
//                            ZStack {
//                                Color.gray.opacity(0.2)
//                                Image(systemName: "photo")
//                                    .font(.largeTitle)
//                                    .foregroundColor(.gray)
//                            }
//                            
//                        }
//                    }
                
                } else {
//                    
//                    ZStack {
//                        Color.gray.opacity(0.2)
//                        Image(systemName: "photo")
//                            .font(.largeTitle)
//                            .foregroundColor(.gray)
//                    }
                    
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}
    



struct PlaceCardView: View {
    let place: Place
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name)
                .font(.title3)
                .bold()
            if let desc = place.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            if let city = place.location?.city {
                Label(city, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .cornerRadius(16)
        .shadow(radius: 4)
    }
}


struct LocationPostView: View {
    let post: Post
    let place: Place
    @State private var showFullPlaceView = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PostHeaderView(post: post)
            PostMediaSplitView(post: post, place: place, showFullPlaceView: $showFullPlaceView)
            PostInteractionBar()
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
    }
}


struct PostHeaderView: View {
    let post: Post
    
    var body: some View {
        HStack {
            AsyncImage(url: post.author?.avatarUrl) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Circle().fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(post.author?.username ?? "Unknown User")
                    .font(.headline)
                Text(timeAgo(from: post.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 60 { return "Just now" }
        else if interval < 3600 { return "\(Int(interval / 60))m ago" }
        else if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        else { return "\(Int(interval / 86400))d ago" }
    }
}


struct PostMediaSplitView: View {
    let post: Post
    let place: Place
    @Binding var showFullPlaceView: Bool
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    PostMediaView(post: post)
                        .frame(width: geo.size.width / 2, height: 240)
                    
                    PostPlaceCard(place: place)
                        .frame(width: geo.size.width / 2)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                showFullPlaceView.toggle()
                            }
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                
                if !showFullPlaceView {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            PlaceHoverCard(place: place)
                                .offset(x: -12, y: 12)
                        }
                    }
                }
            }
        }
        .frame(height: 240)
        .padding(.horizontal)
    }
}




struct PostPlaceCard: View {
    let place: Place
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.4), .blue.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: place.placeImageUrl ?? "" )){ phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Text(place.name)
                    .font(.headline)
                
//                if let categoryId = place.categoryId {
//                    Text(String(categoryId))
//                        .font(.caption)
//                        .padding(.horizontal, 8)
//                        .padding(.vertical, 4)
//                        .background(Capsule().fill(Color.blue.opacity(0.2)))
//                }
                
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
//                    Text(String(format: "%.1f", place.rating))
                }
                .font(.caption)
                
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
//                    Text(String(format: "%.1f km away", place.distance))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}


struct PostInteractionBar: View {
    var body: some View {
        HStack(spacing: 24) {
            Button(action: {}) { Label("Hype", systemImage: "flame.fill") }
            Button(action: {}) { Label("Echo", systemImage: "bubble.left.and.bubble.right.fill") }
            Button(action: {}) { Label("Share", systemImage: "square.and.arrow.up") }
            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal)
        .foregroundColor(.secondary)
    }
}

struct PlaceHoverCard: View {
    let place: Place
    
    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: place.placeImageUrl ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.caption)
                    .fontWeight(.semibold)
//                if let category = place.category {
//                    Text(category)
//                        .font(.caption2)
//                        .foregroundColor(.secondary)
//                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
    }
}


