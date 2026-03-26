//
//  ActivityDetailView.swift
//  Locolo
//
//  Created by Apramjot Singh on 4/10/2025.
//



import SwiftUI
import Foundation



struct ActivityDetailView: View {
    
    let activity: ActivityItem
    
    //@StateObject private var vm = PlaceDetailViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                
                AsyncImage(url: URL(string: activity.image)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(height: 200)
                .clipped()
                .cornerRadius(12)
                
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(activity.name)
                        .font(.title).bold()
                    
                    Text(activity.type)
                        .font(.headline).foregroundColor(.secondary)
                    
                    Label("\(activity.hypes) hypes", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    
                    Divider()
                    
                    Text(activity.description)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal)
                
                // Posts section
//                if vm.isLoading {
//                    ProgressView("Loading posts…").padding()
//                } else if let error = vm.errorMessage {
//                    Text(error).foregroundColor(.red).padding()
//                } else if vm.posts.isEmpty {
//                    Text("No posts yet for this place.")
//                        .foregroundColor(.gray)
//                        .padding()
//                } else {
//                    Divider()
//                    Text("Posts from this spot ")
//                        .font(.headline)
//                        .padding(.horizontal)
//                    
//                    VStack(spacing: 16) {
//                        ForEach(vm.posts) { post in
//                            PostCard(post: post)
//                        }
//                    }
//                    .padding(.horizontal)
//                }
            }
            .padding(.top)
        }
        .navigationTitle(activity.name)
        .navigationBarTitleDisplayMode(.inline)
//        .task {
//            await vm.loadPosts(for: place.id)
//        }
    }
}


