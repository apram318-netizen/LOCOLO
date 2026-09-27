//
//  ARSearchView.swift
//  Locolo
//
//  The Search tab: full-catalogue discovery with recent searches,
//  trending suggestions, category browsing, sorting, and marketplace
//  filters. Results reuse ArtworkCard; data comes from ARGalleryViewModel.
//

import SwiftUI

struct ARSearchView: View {
    var onDismiss: (() -> Void)? = nil

    @StateObject private var vm = ARGalleryViewModel()
    @EnvironmentObject private var dashboardState: ARDashboardState

    @State private var selectedAsset: DigitalAsset?
    @State private var showFilters = false
    @FocusState private var searchFocused: Bool

    /// Recent searches persist across sessions as a JSON-encoded array.
    @AppStorage("ar_recent_searches") private var recentSearchesData: Data = Data()

    private var recentSearches: [String] {
        (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }

    private var isSearching: Bool {
        !vm.searchQuery.isEmpty || vm.hasActiveFilters
    }

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if vm.isLoading {
                        ProgressView("Loading catalogue…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if isSearching {
                        resultsSection
                    } else {
                        discoverSections
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 10) {
                ARGlassHeader(title: "Search", subtitle: "Discover AR assets", onExit: onDismiss) {
                    ARHeaderIconButton(
                        icon: "slider.horizontal.3",
                        label: "Filters and sorting",
                        prominent: vm.hasActiveFilters
                    ) {
                        showFilters = true
                    }
                }
                searchBar
            }
        }
        .task { await vm.loadArtworks() }
        .sheet(item: $selectedAsset) { asset in
            AssetDetailSheet(asset: asset, onOpenCreator: {
                dashboardState.path.append(.profile(userId: asset.userId))
            })
        }
        .sheet(isPresented: $showFilters) {
            filterSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search assets, categories, places…", text: $vm.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { commitSearch(vm.searchQuery) }
                    .accessibilityLabel("Search AR assets")

                if !vm.searchQuery.isEmpty {
                    Button {
                        vm.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(ARDesign.hairline, lineWidth: 1))

            if searchFocused {
                Button("Cancel") {
                    vm.searchQuery = ""
                    searchFocused = false
                }
                .font(.subheadline)
                .foregroundColor(.purple)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(ARDesign.spring, value: searchFocused)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Discover (empty query)

    @ViewBuilder
    private var discoverSections: some View {
        if !recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ARSectionHeader(title: "Recent", icon: "clock")
                    Spacer()
                    Button("Clear") { clearRecentSearches() }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.purple)
                }
                .padding(.horizontal, 16)

                chipRow(recentSearches, icon: "arrow.counterclockwise")
            }
        }

        if !vm.trendingNames.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ARSectionHeader(title: "Trending", icon: "flame.fill")
                    .padding(.horizontal, 16)
                chipRow(vm.trendingNames, icon: "flame")
            }
        }

        if !vm.categoryCounts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ARSectionHeader(title: "Browse Categories", icon: "square.grid.2x2")
                    .padding(.horizontal, 16)
                categoryGrid
            }
        }
    }

    private func chipRow(_ items: [String], icon: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { term in
                    ARFilterChip(title: term, icon: icon, isActive: false) {
                        commitSearch(term)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(vm.categoryCounts, id: \.category) { entry in
                Button {
                    ARHaptics.tick()
                    vm.selectedCategory = entry.category
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: categoryIcon(entry.category))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.purple)
                            .padding(9)
                            .background(Circle().fill(Color.purple.opacity(0.14)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.category.capitalized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("\(entry.count) asset\(entry.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .arGlassCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "art": return "paintpalette.fill"
        case "photo": return "photo.fill"
        case "3d": return "cube.fill"
        case "audio": return "waveform"
        default: return "sparkles"
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Semantic matches surface above the keyword results when the
            // pgvector pipeline returns anything for this query. (WS5.3)
            if vm.isDeepSearching || !vm.semanticResults.isEmpty {
                semanticSection
            }

            HStack {
                Text("\(vm.filteredArtworks.count) result\(vm.filteredArtworks.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Menu {
                    ForEach(ARGalleryViewModel.SortOption.allCases) { option in
                        Button {
                            vm.sortOption = option
                        } label: {
                            Label(option.rawValue,
                                  systemImage: option == vm.sortOption ? "checkmark" : option.icon)
                        }
                    }
                } label: {
                    Label(vm.sortOption.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.purple)
                }
                .accessibilityLabel("Sort results")

                if vm.hasActiveFilters {
                    Button {
                        withAnimation(ARDesign.spring) { vm.resetFilters() }
                    } label: {
                        Label("Reset", systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Reset filters")
                }
            }
            .padding(.horizontal, 16)

            if vm.filteredArtworks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.purple.opacity(0.5))
                    Text("Nothing matches your search.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(vm.filteredArtworks) { art in
                        Button {
                            commitSearch(vm.searchQuery)
                            selectedAsset = art
                        } label: {
                            ArtworkCard(asset: art)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Filter sheet

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $vm.selectedCategory) {
                        Text("All").tag("all")
                        ForEach(vm.categoryCounts, id: \.category) { entry in
                            Text(entry.category.capitalized).tag(entry.category)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Sort by") {
                    Picker("Sort by", selection: $vm.sortOption) {
                        ForEach(ARGalleryViewModel.SortOption.allCases) { option in
                            Label(option.rawValue, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Marketplace") {
                    Toggle("For sale only", isOn: $vm.onlyForSale)
                    Toggle("Accepting offers", isOn: $vm.onlyAcceptsOffers)
                }

                Section {
                    Button("Reset all filters", role: .destructive) {
                        vm.resetFilters()
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilters = false }
                }
            }
        }
    }

    // MARK: - Recent searches

    // MARK: - Semantic matches (WS5.3)

    private var semanticSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ARSectionHeader(title: "Best matches", icon: "wand.and.stars")
                if vm.isDeepSearching {
                    ProgressView().controlSize(.small).tint(.purple)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            if !vm.semanticResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.semanticResults) { asset in
                            Button { selectedAsset = asset } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    AssetThumbnailView(asset: asset, cornerRadius: 14)
                                        .frame(width: 132, height: 100)
                                        .clipped()
                                    Text(asset.name ?? "Untitled")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    if let loc = asset.displayLocation {
                                        Text(loc)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 132)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func commitSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        vm.searchQuery = trimmed
        searchFocused = false

        var recents = recentSearches.filter { $0.localizedCaseInsensitiveCompare(trimmed) != .orderedSame }
        recents.insert(trimmed, at: 0)
        recentSearchesData = (try? JSONEncoder().encode(Array(recents.prefix(8)))) ?? Data()

        // Kick off semantic (pgvector) search alongside keyword filtering.
        // Silently no-ops until the embed-query function is deployed. (WS5.3)
        Task { await vm.deepSearch() }
    }

    private func clearRecentSearches() {
        recentSearchesData = (try? JSONEncoder().encode([String]())) ?? Data()
    }
}
