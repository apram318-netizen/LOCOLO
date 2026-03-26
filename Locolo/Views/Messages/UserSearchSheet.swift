//
//  UserSearchSheet.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/10/2025.
//


import SwiftUI

struct UserSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentUserId: String
    let currentUserName: String
    let onUserSelected: (SupabaseUser) -> Void

    // MARK: Search State
    @State private var query = ""
    @State private var results: [SupabaseUser] = []
    @State private var loading = false

    private let searchService = UserSearchService()

    var body: some View {
        NavigationStack {
            // MARK: Search Section
            VStack {
                TextField("Search users...", text: $query)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                    .onChange(of: query) { text in
                        Task { await search(text) }
                    }

                // MARK: Results Section
                if loading {
                    ProgressView().padding()
                } else if results.isEmpty {
                    Text("No results").foregroundColor(.gray)
                } else {
                    List(results) { user in
                        Button {
                            onUserSelected(user)
                            dismiss()
                        } label: {
                            HStack {
                                if let url = user.avatar_url, let imageURL = URL(string: url) {
                                    AsyncImage(url: imageURL) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.2)
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                }
                                VStack(alignment: .leading) {
                                    Text(user.name ?? "" )
                                    if let username = user.username {
                                        Text("@\(username)").font(.caption).foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Chat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Search Logic
    private func search(_ text: String) async {
        guard !text.isEmpty else {
            results = []
            return
        }
        loading = true
        results = await searchService.searchUsers(keyword: text, excludeUserId: currentUserId.lowercased())
        loading = false
    }
}
