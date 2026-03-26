//
//  EchoSheet.swift
//  Locolo
//
//  Created by Apramjot Singh on 3/10/2025.
//


import SwiftUI
import Foundation

struct EchoSheet: View {
    let post: Post
    @ObservedObject var vm: EchoViewModel
    @EnvironmentObject var userVM: UserViewModel
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Handle drag bar
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            
            // Title
            Text("Echoes")
                .font(.headline)
                .padding(.vertical, 8)
            
            Divider()
            
            // Echo List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.echoes) { echo in
                        HStack(alignment: .top, spacing: 12) {
                            AsyncImage(url: echo.author?.avatarUrl) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .scaledToFill()
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                default:
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 32, height: 32)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(echo.author?.username ?? "")
                                    .font(.subheadline).bold()
                                Text(echo.content)
                                    .font(.body)
                                Text(relativeTime(for: echo.createdAt))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            
            Divider()
            
            // Input Bar
            HStack(spacing: 8) {
                AsyncImage(url: userVM.currentUser?.avatarUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    default:
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 32, height: 32)
                    }
                }
                
                TextField("Add an echo...", text: $vm.newEchoText, axis: .vertical)
                    .focused($isInputFocused)
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
                
                Button(action: {
                    vm.addEcho(to: post, currentUserId: userVM.currentUser?.id  ?? UUID())
                    isInputFocused = false
                }) {
                    Text("Send")
                        .bold()
                        .foregroundColor(vm.newEchoText.isEmpty ? .gray : .blue)
                }
                .disabled(vm.newEchoText.isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .onAppear {
            vm.loadEchoes(for: post)
        }
    }
    
    
    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    
}
