//
//  ChatView.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/10/2025.
//

import SwiftUI
import Foundation

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel
    let currentUserId: String
    let currentUserName: String
    @State private var text = ""
    
    init(vm: ChatViewModel, currentUserId: String, currentUserName: String) {
        self._vm = ObservedObject(initialValue: vm)
        self.currentUserId = currentUserId
        self.currentUserName = currentUserName
        print(" ChatView initialized for convo:")
    }
    
    var body: some View {
        VStack() {
            // MARK: Messages List Section
            // Scrollable list of messages with auto scroll to bottom on new messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack() {
                        ForEach(vm.messages) { msg in
                            HStack {
                                if msg.senderId == currentUserId { Spacer() }
                                VStack(alignment: msg.senderId == currentUserId ? .trailing : .leading, spacing: 0) {
                                    Text(msg.senderName)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text(msg.text)
                                        .padding(10)
                                        .background(msg.senderId == currentUserId ? Color.blue.opacity(0.8) : Color.gray.opacity(0.2))
                                        .cornerRadius(16)
                                        .foregroundColor(msg.senderId == currentUserId ? .white : .primary)
                                }
                                if msg.senderId != currentUserId { Spacer() }
                            }
                            .padding(.horizontal)
                            .id(msg.id)
                        }
                    }
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: vm.messages.count) { _ in
                    // Auto-scroll to bottom when new messages arrive
                    if let last = vm.messages.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            // MARK: Input Section
            // Text field and send button for composing and sending messages
            HStack(spacing: 12) {
                TextField("Message...", text: $text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Send") {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    vm.sendMessage(
                        text,
                        senderId: currentUserId.lowercased(),
                        senderName: currentUserName
                    )
                    text = ""
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
}
