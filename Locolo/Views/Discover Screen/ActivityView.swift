//
//  ActivityView.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/9/2025.
//

import SwiftUI

struct ActivityItem: Identifiable, Hashable {
    let id : UUID
    let name: String
    let type: String
    let duration: String
    let price: String
    let description: String
    let rating: Double
    let participants: Int
    let image: String
    let hypes: Int?
}

struct ActivityCard: View {
    let activity: ActivityItem
    
    var body: some View {
        NavigationLink(destination: ActivityDetailView(activity: activity)) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: activity.image)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    AppColors.secondaryText.opacity(0.3)
                }
                .frame(width: 80, height: 80)
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(activity.name)
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("\(activity.type) • \(activity.duration)")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack {
                        Label(String(format: "%.1f", activity.rating), systemImage: "star.fill")
                            .foregroundColor(AppColors.ratingStar)
                            .font(.caption)
                        
                        Text(activity.price)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.priceBadge)
                            .cornerRadius(8)
                        
                        Spacer()
                        
                        Text("\(activity.participants) joined")
                            .font(.caption2)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .padding()
            .background(AppColors.cardBackground)
            .cornerRadius(16)
            .shadow(color: AppColors.cardShadow, radius: 5, x: 0, y: 2)
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActivitiesView: View {
    @StateObject private var vm = ActivitiesDiscoverViewModel()
    @EnvironmentObject var loopVM: LoopViewModel
    
    // MARK: Navigation State
    // State for presenting activity detail view
    @State private var selectedActivity: ActivityItem?
    
    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading activities...")
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
                        Task { await vm.loadActivities() }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        //  Section
                        Text("Must-Do's ")
                            .font(.headline)
                            .foregroundColor(AppColors.primaryText)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            ForEach(vm.nycActivities) { activity in
                                ActivityCard(activity: activity)
                            }
                        }
                        
                        Text("Trending Activities ")
                            .font(.headline)
                            .foregroundColor(AppColors.primaryText)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(vm.popularActivities) { activity in
                                Button {
                                    selectedActivity = activity
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        AsyncImage(url: URL(string: activity.image)) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            AppColors.secondaryText.opacity(0.3)
                                        }
                                        .frame(height: 120)
                                        .cornerRadius(12)
                                        
                                        Text(activity.name)
                                            .font(.subheadline).bold()
                                            .foregroundColor(AppColors.primaryText)
                                            .lineLimit(1)
                                        
                                        Text(activity.type)
                                            .font(.caption2)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                    .padding(8)
                                    .background(AppColors.cardBackground)
                                    .cornerRadius(12)
                                    .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top)
                }
            }
        }
        .background(AppColors.screenBackground)
        .task {
            await vm.loadActivities()
        }
        .onChange(of: loopVM.activeLoop?.id) { _ in
            // Reload activities when active loop changes
            Task {
                await vm.loadActivities()
            }
        }
        // MARK: Activity Detail Navigation
        // Presents activity detail view when a trending activity is tapped
        .navigationDestination(item: $selectedActivity) { activity in
            ActivityDetailView(activity: activity)
        }
    }
}
