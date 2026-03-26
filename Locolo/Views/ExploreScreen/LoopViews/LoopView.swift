//
//  LoopView.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import SwiftUI

// MARK: - Compact View
struct LoopsCompactView: View {
    @EnvironmentObject var loopVM: LoopViewModel

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 12) {
                if let activeLoop = loopVM.activeLoop {
                    HStack(spacing: 8) {
                        Button(action: { loopVM.setActiveLoop(activeLoop) }) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.blueCyanGradient)
                                    .frame(width: 40, height: 40)
                                Text(String(activeLoop.name.prefix(1)))
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        Text(activeLoop.name)
                            .font(.headline)
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    Image(systemName: "map.circle")
                        .font(.title2)
                        .foregroundColor(.gray)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        loopVM.toggleExpanded()
                    }
                } label: {
                    Image(systemName: loopVM.expanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .padding(6)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}


// MARK: - Expanded View
// MARK: - Expanded View
struct LoopsExpandedView: View {
    @EnvironmentObject var loopVM: LoopViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    // Top Row: Search Bar + Close Button
                    HStack(spacing: 10) {
                        LoopsSearchBarSection()
                            .environmentObject(loopVM)

                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                loopVM.toggleExpanded()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .padding(6)
                                .accessibilityLabel("Close loops dropdown")
                        }
                    }
                    .padding(.horizontal)

                    // Recent loops or search results
                    if loopVM.searchQuery.isEmpty && !loopVM.recentLoops.isEmpty {
                        RecentLoopsSection()
                            .environmentObject(loopVM)
                    }

                    if !loopVM.searchQuery.isEmpty {
                        LoopsSearchResultsSection()
                            .environmentObject(loopVM)
                    }
                }
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(radius: 8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        .zIndex(1) // keeps overlay above everything
    }
}



// MARK: - Search Bar + Add Button Section
struct LoopsSearchBarSection: View {
    @EnvironmentObject var loopVM: LoopViewModel

    var body: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search loops...", text: $loopVM.searchQuery)
                    .onChange(of: loopVM.searchQuery) { newValue in
                        loopVM.searchLoops(newValue)
                    }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            Button {
                loopVM.creatingNewLoop = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .sheet(isPresented: $loopVM.creatingNewLoop) {
                LoopCreationView()
                    .environmentObject(loopVM)
            }
        }
        .padding(.horizontal)
    }
}



// MARK: - Recent Loops (Story Style)
struct RecentLoopsSection: View {
    @EnvironmentObject var loopVM: LoopViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently Visited")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(loopVM.recentLoops.prefix(5)) { loop in
                        VStack(spacing: 6) {
                            Button(action: { loopVM.setActiveLoop(loop) }) {
                                ZStack {
                                    // Gradient ring
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [.purple, .pink, .orange],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 3
                                        )
                                        .frame(width: 64, height: 64)

                                    // Cover image
                                    AsyncImage(url: URL(string: loop.coverImageUrl ?? "")) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable()
                                                .scaledToFill()
                                                .frame(width: 58, height: 58)
                                                .clipShape(Circle())
                                        default:
                                            Circle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(width: 58, height: 58)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Text(loop.name)
                                .font(.caption2)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}



// MARK: - Search Results Section
struct LoopsSearchResultsSection: View {
    @EnvironmentObject var loopVM: LoopViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                if loopVM.allLoops.isEmpty {
                    Text("No loops found")
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                } else {
                    ForEach(loopVM.allLoops) { loop in
                        LoopRowView(loop: loop)
                            .environmentObject(loopVM)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: min(CGFloat(loopVM.allLoops.count) * 70, 400)) // adaptive height
    }
}




// MARK: - Row View (Unchanged)
struct LoopRowView: View {
    let loop: Loop
    @EnvironmentObject var loopVM: LoopViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: loop.coverImageUrl ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 60, height: 60)
            .cornerRadius(10)
            .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(loop.name)
                    .font(.headline)
                Text("\(loop.memberCount) members")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if loop.isMember {
                Button(loop.isActive ? "Active" : "Set Active") {
                    loopVM.setActiveLoop(loop)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    loop.isActive
                    ? AnyShapeStyle(AppColors.blueCyanMutedGradient)
                    : AnyShapeStyle(AppColors.blueCyanMutedGradient.opacity(0.25))
                )
                .foregroundColor(loop.isActive ? .white : AppColors.primaryText)
                .cornerRadius(8)

            } else {
                Button("Join") {
                    loopVM.joinLoop(loop)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.categoryBadge)
                .cornerRadius(8)
                .foregroundColor(AppColors.primaryText)
            }
        }
        .padding(.vertical, 6)
    }
}
