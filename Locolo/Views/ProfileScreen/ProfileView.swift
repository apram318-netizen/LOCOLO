//
//  ProfileView.swift
//  Locolo
//
//  Created by Apramjot Singh on 1/10/2025.
//
import SwiftUI
import MapKit

struct ProfileView: View {
    @EnvironmentObject var userVM: UserViewModel
    @StateObject private var vm = ProfileViewModel()

    @State private var selectedTab: Int = 0
    @State private var postGridMode: Bool = true
    @State private var placesListMode: Bool = true

    var body: some View {
        if let user = userVM.currentUser {
            VStack(spacing: 20) {
                // MARK: - Profile Header (Fixed)
                headerView(for: user)
                    .padding(.top, 25) // consistent space below notch

                // MARK: - Tabs
                Picker("", selection: $selectedTab) {
                    Text("Posts").tag(0)
                    Text("Places").tag(1)
                    Text("Art").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                // MARK: - Content (Scrollable only for lower section)
                ZStack {
                    if selectedTab == 0 {
                        if vm.isLoading {
                            ProgressView("Loading posts…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                PostsTab(posts: vm.posts, gridMode: $postGridMode)
                                    .padding(.bottom, 100) // space for tab bar
                            }
                        }
                    } else if selectedTab == 1 {
                        if vm.isLoading && vm.places.isEmpty {
                            ProgressView("Loading places…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                PlacesTab(places: vm.places, listMode: $placesListMode)
                                    .padding(.bottom, 100)
                            }
                        }
                    } else if selectedTab == 2 {
                        if vm.isLoading && vm.assets.isEmpty {
                            ProgressView("Loading artworks…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                ArtTab(assets: vm.assets)
                                    .padding(.bottom, 100)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground))
            .ignoresSafeArea(edges: .bottom)
            .task {
                await vm.loadPosts(for: user.id)
                await vm.loadPlaces(for: user.id)
                await vm.loadUserCollection(userId: user.id)
            }
        }
    }

    // MARK: - Header Component
    private func headerView(for user: User) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: user.avatarUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.purple, lineWidth: 2))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(user.name ?? user.username)
                        .font(.title3.bold())
                    if let verified = user.verifiedFlags?["blue"], verified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Text("@\(user.username)")
                    .foregroundStyle(.gray)

                if let bio = user.bio {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statView(value: vm.posts.count, label: "Posts")
                    statView(value: user.stats?["followers"] ?? 0, label: "Followers")
                    statView(value: user.stats?["following"] ?? 0, label: "Following")
                }
            }

            Spacer()

            VStack {
                
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
            }
        }
        .padding(.horizontal)
    }

    private func statView(value: Int, label: String) -> some View {
        VStack {
            Text("\(value)").bold()
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
}
