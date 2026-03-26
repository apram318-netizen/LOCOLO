//
//  PostsTab.swift
//  Locolo
//
//  Created by Apramjot Singh on 1/10/2025.
//

import SwiftUI

// MARK: - Post Navigation Wrapper
// Wrapper struct to make Post Hashable for navigation
struct PostNavigationItem: Identifiable, Hashable {
    let id: UUID
    let post: Post
    
    init(post: Post) {
        self.post = post
        self.id = post.id ?? UUID()
    }
    
    static func == (lhs: PostNavigationItem, rhs: PostNavigationItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PostsTab: View {
    let posts: [Post]
    @Binding var gridMode: Bool
    
    // MARK: Navigation State
    // State for presenting post detail view
    @State private var selectedPost: PostNavigationItem?

    var body: some View {
        VStack(spacing: 10) {
            // MARK: Layout Toggle Section
            // MARK: Layout toggle buttons
            HStack {
                Spacer()
                Button(action: { gridMode = true }) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.title3)
                        .foregroundColor(gridMode ? .blue : .gray)
                }
                Button(action: { gridMode = false }) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundColor(!gridMode ? .blue : .gray)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)

            // MARK: Grid View Section
            // MARK: Grid / List switch
            if gridMode {
                GeometryReader { geo in
                    let columns = 3
                    let spacing: CGFloat = 4    //  tiny gaps
                    let totalSpacing = spacing * CGFloat(columns - 1)
                    let cell = (geo.size.width - totalSpacing - 4) / CGFloat(columns)
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.fixed(cell), spacing: spacing),
                                count: columns
                            ),
                            spacing: spacing
                        ) {
                            ForEach(posts) { post in
                                Button {
                                    selectedPost = PostNavigationItem(post: post)
                                } label: {
                                    AsyncImage(url: post.media) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.15)
                                    }
                                    .frame(width: cell, height: cell)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) //  rounded like reference
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 2)  //  minimal side margins
                        .padding(.top, 4)
                        .padding(.bottom, 80)     // leave space above tab bar
                    }
                }
                //  Fills remaining screen height, keeping header fixed
                .frame(maxWidth: .infinity)
                .frame(height: UIScreen.main.bounds.height - 340)
            } else {
                // MARK: List View Section
                // MARK: List layout (unchanged)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(posts) { post in
                            Button {
                                selectedPost = PostNavigationItem(post: post)
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: post.media) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.15)
                                    }
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(post.caption ?? "Untitled")
                                            .font(.headline)
                                            .multilineTextAlignment(.leading)
                                        Text(post.author?.username ?? "")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 10)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.bottom, 80)
                }
                .frame(height: UIScreen.main.bounds.height - 340)
            }
        }
        // MARK: Post Detail Navigation
        // Presents post detail view when a post is tapped
        .navigationDestination(item: $selectedPost) { item in
            PostDetailView(post: item.post)
                
        }
    }
}
