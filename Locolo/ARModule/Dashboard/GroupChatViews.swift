//
//  GroupChatViews.swift
//  Locolo
//
//  Group chats: create (pick people + name), group info (members, add,
//  rename, leave). Messages are end-to-end encrypted by fan-out — see
//  ChatViewModel.sendGroupMessage — so groups need no new server schema.
//

import SwiftUI

struct NewGroupView: View {
    @EnvironmentObject private var userVM: UserViewModel
    @EnvironmentObject private var dashboardState: ARDashboardState
    @ObservedObject private var follows = FollowStore.shared
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var creators = CreatorCache.shared

    @State private var name = ""
    @State private var query = ""
    @State private var results: [ARCreator] = []
    @State private var selected: [ARCreator] = []
    @State private var isCreating = false
    @State private var errorText: String?

    private var suggestions: [ARCreator] {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return results }
        let blocked = SafetyService.shared.blockedUserIds
        let ids = inbox.conversations.compactMap { inbox.peerId(of: $0) } + Array(follows.following)
        var seen = Set<UUID>()
        return ids.filter { !blocked.contains($0) && seen.insert($0).inserted }.compactMap { creators.creator($0) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(AppColors.purplePinkGradient)
                        Image(systemName: "person.3.fill").foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)
                    TextField("Group name", text: $name)
                        .font(.headline)
                        .onChange(of: name) { _, n in if n.count > 40 { name = String(n.prefix(40)) } }
                }
            }

            if !selected.isEmpty {
                Section("\(selected.count) selected") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selected) { person in
                                Button { toggle(person) } label: {
                                    VStack(spacing: 4) {
                                        ARAvatarView(url: person.avatarUrl, name: person.displayName, size: 46)
                                            .overlay(alignment: .topTrailing) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .gray)
                                            }
                                        Text(person.displayName).font(.caption2).lineLimit(1).frame(width: 56)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Section(query.isEmpty ? "Suggested" : "Results") {
                ForEach(suggestions) { person in
                    Button { toggle(person) } label: {
                        HStack(spacing: 12) {
                            ARAvatarView(url: person.avatarUrl, name: person.displayName, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                ARCreatorName(creator: person)
                                Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selected.contains(person) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected.contains(person) ? AnyShapeStyle(ARDesign.accent) : AnyShapeStyle(.secondary))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(.red).font(.footnote) }
            }
        }
        .searchable(text: $query, prompt: "Search people")
        .navigationTitle("New group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: create) {
                    if isCreating { ProgressView() } else { Text("Create").bold() }
                }
                .disabled(selected.count < 2 || isCreating)
            }
        }
        .task { await CreatorCache.shared.load(Array(follows.following)) }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { results = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            results = await PeopleSearch.search(q).filter { $0.id != userVM.currentUser?.id }
        }
    }

    private func toggle(_ person: ARCreator) {
        ARHaptics.tick()
        if let i = selected.firstIndex(of: person) { selected.remove(at: i) }
        else if selected.count < 31 { selected.append(person) }
    }

    private func create() {
        guard let me = userVM.currentUser else { return }
        isCreating = true
        errorText = nil
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? selected.prefix(3).map(\.displayName).joined(separator: ", ")
            : name.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let id = try await ChatRepository().createGroup(
                    name: title, creator: me.id.uuidString,
                    members: selected.map { $0.id.uuidString })
                ARHaptics.success()
                dashboardState.path.removeLast()
                dashboardState.path.append(.chat(conversationId: id))
            } catch {
                errorText = "Couldn't create the group. Check your connection and try again."
            }
            isCreating = false
        }
    }
}

/// Members, add people, rename, leave.
struct GroupInfoSheet: View {
    let conversationId: String
    @ObservedObject var vm: ChatViewModel

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var userVM: UserViewModel
    @ObservedObject private var creators = CreatorCache.shared
    @State private var newName = ""
    @State private var adding = false
    @State private var confirmLeave = false

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField(vm.groupName ?? "Group", text: $newName)
                        .onSubmit {
                            let n = newName.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty else { return }
                            Task { try? await ChatRepository().renameGroup(conversationId, to: n) }
                        }
                }
                Section("\(vm.groupMembers.count) members") {
                    ForEach(vm.groupMembers, id: \.self) { id in
                        let c = creators.creator(id)
                        HStack(spacing: 12) {
                            ARAvatarView(url: c?.avatarUrl, name: c?.displayName ?? "?", size: 36)
                            ARCreatorName(creator: c, fallback: "Explorer")
                            Spacer()
                            if vm.unreachableMembers.contains(id) {
                                Image(systemName: "lock.slash").foregroundStyle(.orange)
                                    .accessibilityLabel("Hasn't set up encrypted chat")
                            }
                        }
                    }
                    Button { adding = true } label: { Label("Add people", systemImage: "person.badge.plus") }
                }
                Section {
                    Button("Leave group", role: .destructive) { confirmLeave = true }
                } footer: {
                    Text("Messages are end-to-end encrypted separately for each member. New members can't read anything sent before they joined.")
                }
            }
            .navigationTitle("Group info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $adding) {
                ARNewMessageSheet { person in
                    Task { try? await ChatRepository().addMembers([person.id.uuidString], to: conversationId) }
                }
            }
            .confirmationDialog("Leave this group?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    guard let me = userVM.currentUser else { return }
                    Task {
                        try? await ChatRepository().leaveGroup(conversationId, userId: me.id.uuidString)
                        dismiss()
                    }
                }
            }
        }
    }
}
