//
//  MessagesScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 15/10/2025.
//


import SwiftUI

struct MessagesScreen: View {
    // MARK: View State
    @State private var searchText = ""
    @State private var selectedTab = "Chats"
    @State private var selectedChat: ChatPreview? = nil
    @Namespace private var animation
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: Top Bar Section
                //  Top Bar
                HStack {
                    Text("Messages 💬")
                        .font(.title2.bold())
                    Spacer()
                    Button(action: {}) {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                    }
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .font(.title3)
                    }
                    Button(action: {}) {
                        Image(systemName: "xmark")
                            .font(.title3)
                    }
                }
                .padding()
                .background(LinearGradient(colors: [.purple.opacity(0.4), .blue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                // MARK: Search Section
                // 🔹 Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search conversations...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // MARK: Tabs Section
                // 🔹 Tabs (Chats / Groups)
                HStack(spacing: 0) {
                    ForEach(["Chats", "Groups"], id: \.self) { tab in
                        Button {
                            withAnimation(.spring()) { selectedTab = tab }
                        } label: {
                            Text(tab)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    ZStack {
                                        if selectedTab == tab {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.blue.opacity(0.3))
                                                .matchedGeometryEffect(id: "TAB", in: animation)
                                        }
                                    }
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // MARK: Conversations List Section
                // 🔹 Chats list (temporary placeholder layout)
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            Button {
                                selectedChat = ChatPreview(name: "Sarah Kim")
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 50, height: 50)
                                        .overlay(Text("S").font(.title3).bold().foregroundColor(.white))
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Sarah Kim")
                                            .font(.headline)
                                        Text("Love your latest digital piece!")
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("1h ago")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(LinearGradient(colors: [.black, .purple.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationDestination(item: $selectedChat) { chat in
                ChatDetailView(chat: chat)
            }
        }
    }
}

struct ChatPreview: Identifiable, Hashable {
    var id = UUID()
    var name: String
}

struct ChatDetailView: View {
    let chat: ChatPreview
    @State private var newMessage = ""
    @State private var messages: [String] = []
    
    var body: some View {
        VStack {
            //  Chat header
            HStack {
                Button(action: { /* back handled automatically */ }) {
                    Image(systemName: "chevron.left")
                }
                Circle()
                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                    .overlay(Text(String(chat.name.prefix(1))).foregroundColor(.white))
                
                VStack(alignment: .leading) {
                    Text(chat.name)
                        .font(.headline)
                    Text("Online")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
                Button(action: {}) {
                    Image(systemName: "square.and.pencil")
                }
            }
            .padding()
            .background(Color.black.opacity(0.2))
            
            //  Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages.indices, id: \.self) { index in
                            HStack {
                                if index % 2 == 0 {
                                    Spacer()
                                    Text(messages[index])
                                        .padding(10)
                                        .background(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .cornerRadius(16)
                                        .foregroundColor(.white)
                                        .id(index)
                                } else {
                                    Text(messages[index])
                                        .padding(10)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(16)
                                        .foregroundColor(.white)
                                        .id(index)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(messages.count - 1, anchor: .bottom)
                    }
                }
            }
            
            // 🔹 Input bar
            HStack {
                TextField("Type something cool... ✨", text: $newMessage)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(20)
                
                Button {
                    guard !newMessage.isEmpty else { return }
                    messages.append(newMessage)
                    newMessage = ""
                } label: {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "paperplane.fill").foregroundColor(.white))
                }
            }
            .padding()
            .background(Color.black.opacity(0.2))
        }
        .background(LinearGradient(colors: [.black, .purple.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}
