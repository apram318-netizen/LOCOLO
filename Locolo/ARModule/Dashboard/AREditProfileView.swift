//
//  AREditProfileView.swift
//  Locolo
//
//  The AR app's own profile editor: cover + avatar photos, display name,
//  username (validated, with a live availability check) and bio. Saves via
//  UserViewModel.updateProfile, which only writes the user-editable columns.
//

import SwiftUI
import PhotosUI
import Supabase

struct AREditProfileView: View {
    @EnvironmentObject private var userVM: UserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var avatarUrl: URL?
    @State private var coverUrl: URL?
    @State private var avatarPreview: UIImage?
    @State private var coverPreview: UIImage?
    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?

    @State private var uploading: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var usernameStatus: UsernameStatus = .unchanged
    @State private var loaded = false

    private enum UsernameStatus: Equatable {
        case unchanged, checking, available, taken, invalid(String)
    }

    private static let bioLimit = 150
    private static let nameLimit = 40

    private var user: User? { userVM.currentUser }

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var hasChanges: Bool {
        guard let user else { return false }
        return displayName.trimmingCharacters(in: .whitespacesAndNewlines) != (user.name ?? "")
            || normalizedUsername != user.username.lowercased()
            || bio.trimmingCharacters(in: .whitespacesAndNewlines) != (user.bio ?? "")
            || avatarUrl != user.avatarUrl
            || coverUrl != user.coverUrl
    }

    private var canSave: Bool {
        guard hasChanges, !isSaving, uploading.isEmpty else { return false }
        switch usernameStatus {
        case .unchanged, .available: return true
        default: return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 56)

                VStack(spacing: 16) {
                    field(title: "Name", footer: "\(displayName.count)/\(Self.nameLimit)") {
                        TextField("Your name", text: $displayName)
                            .textContentType(.name)
                            .onChange(of: displayName) { _, v in
                                if v.count > Self.nameLimit { displayName = String(v.prefix(Self.nameLimit)) }
                            }
                    }

                    field(title: "Username", footerView: AnyView(usernameFooter)) {
                        HStack(spacing: 2) {
                            Text("@").foregroundColor(.secondary)
                            TextField("username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                        }
                    }

                    field(title: "Bio", footer: "\(bio.count)/\(Self.bioLimit)") {
                        TextField("Tell explorers what you create", text: $bio, axis: .vertical)
                            .lineLimit(3...6)
                            .onChange(of: bio) { _, v in
                                if v.count > Self.bioLimit { bio = String(v.prefix(Self.bioLimit)) }
                            }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
        .background(ARDesign.screenBackground.ignoresSafeArea())
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save").bold() }
                }
                .disabled(!canSave)
            }
        }
        .onAppear(perform: loadCurrent)
        .onChange(of: avatarItem) { _, item in
            Task { await upload(item, kind: "avatar") }
        }
        .onChange(of: coverItem) { _, item in
            Task { await upload(item, kind: "cover") }
        }
        .task(id: normalizedUsername) { await checkUsername() }
    }

    // MARK: Header (cover + avatar)

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            PhotosPicker(selection: $coverItem, matching: .images) {
                ZStack {
                    if let coverPreview {
                        Image(uiImage: coverPreview).resizable().scaledToFill()
                    } else if let coverUrl {
                        AsyncImage(url: coverUrl) { $0.resizable().scaledToFill() } placeholder: {
                            AppColors.purplePinkGradient
                        }
                    } else {
                        AppColors.purplePinkGradient
                    }
                    Color.black.opacity(0.25)
                    photoBadge(uploading.contains("cover") ? nil : "Change cover")
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change cover photo")

            PhotosPicker(selection: $avatarItem, matching: .images) {
                ZStack {
                    Group {
                        if let avatarPreview {
                            Image(uiImage: avatarPreview).resizable().scaledToFill()
                        } else {
                            ARAvatarView(url: avatarUrl, name: displayName.isEmpty ? username : displayName, size: 96)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())

                    Circle().fill(Color.black.opacity(0.3)).frame(width: 96, height: 96)
                    if uploading.contains("avatar") {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "camera.fill").foregroundColor(.white)
                    }
                }
                .padding(4)
                .background(Circle().fill(ARDesign.screenBackground))
                .overlay(Circle().strokeBorder(AppColors.purplePinkGradient, lineWidth: 2.5))
            }
            .buttonStyle(.plain)
            .offset(x: 16, y: 48)
            .accessibilityLabel("Change profile photo")
        }
    }

    @ViewBuilder
    private func photoBadge(_ title: String?) -> some View {
        if let title {
            Label(title, systemImage: "photo")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.45)))
        } else {
            ProgressView().tint(.white)
        }
    }

    // MARK: Fields

    private func field<Content: View>(title: String, footer: String? = nil, footerView: AnyView? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            content()
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .arGlassCard(cornerRadius: 14)
            if let footerView {
                footerView
            } else if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var usernameFooter: some View {
        Group {
            switch usernameStatus {
            case .unchanged:
                Text("Explorers find and mention you with this.")
                    .foregroundColor(.secondary)
            case .checking:
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Checking…") }
                    .foregroundColor(.secondary)
            case .available:
                Label("Available", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            case .taken:
                Label("That username is taken", systemImage: "xmark.circle.fill").foregroundColor(.red)
            case .invalid(let reason):
                Label(reason, systemImage: "exclamationmark.circle.fill").foregroundColor(.orange)
            }
        }
        .font(.caption2)
    }

    // MARK: Logic

    private func loadCurrent() {
        guard !loaded, let user else { return }
        loaded = true
        displayName = user.name ?? ""
        username = user.username
        bio = user.bio ?? ""
        avatarUrl = user.avatarUrl
        coverUrl = user.coverUrl
    }

    private static func validate(_ name: String) -> String? {
        if name.count < 3 { return "At least 3 characters" }
        if name.count > 30 { return "30 characters max" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._")
        if name.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Letters, numbers, . and _ only"
        }
        if name.hasPrefix(".") || name.hasSuffix(".") { return "Can't start or end with a period" }
        return nil
    }

    private struct UsernameRow: Decodable { let user_id: UUID }

    private func checkUsername() async {
        guard let user else { return }
        let candidate = normalizedUsername
        if candidate == user.username.lowercased() { usernameStatus = .unchanged; return }
        if let reason = Self.validate(candidate) { usernameStatus = .invalid(reason); return }
        usernameStatus = .checking
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        do {
            let rows: [UsernameRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("user_id")
                .ilike("username", pattern: candidate.replacingOccurrences(of: "_", with: "\\_"))
                .neq("user_id", value: user.id)
                .limit(1)
                .execute()
                .value
            guard !Task.isCancelled else { return }
            usernameStatus = rows.isEmpty ? .available : .taken
        } catch {
            // Can't verify offline; let the save attempt surface a conflict.
            usernameStatus = .available
        }
    }

    private func upload(_ item: PhotosPickerItem?, kind: String) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Couldn't load that photo."
            return
        }
        let isAvatar = kind == "avatar"
        if isAvatar { avatarPreview = image } else { coverPreview = image }
        uploading.insert(kind)
        errorMessage = nil
        defer { uploading.remove(kind) }

        guard let jpeg = Self.compress(image, maxDimension: isAvatar ? 800 : 1600,
                                       maxBytes: isAvatar ? 300_000 : 700_000) else {
            errorMessage = "Couldn't process that photo."
            return
        }
        do {
            let path = "\(isAvatar ? "avatars" : "covers")/\(UUID().uuidString).jpg"
            let urlString = try await ObjStorageManager.shared.uploadFile(
                path: path, fileData: jpeg, contentType: "image/jpeg")
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            if isAvatar { avatarUrl = url } else { coverUrl = url }
        } catch {
            if isAvatar { avatarPreview = nil } else { coverPreview = nil }
            errorMessage = "Upload failed. Check your connection and try again."
        }
    }

    private static func compress(_ image: UIImage, maxDimension: CGFloat, maxBytes: Int) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        var quality: CGFloat = 0.85
        var data = resized.jpegData(compressionQuality: quality)
        while let d = data, d.count > maxBytes, quality > 0.2 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)
        }
        return data
    }

    private func save() async {
        guard let user, canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = User(
            id: user.id,
            username: normalizedUsername,
            email: user.email,
            name: name.isEmpty ? nil : name,
            bio: trimmedBio.isEmpty ? nil : trimmedBio,
            avatarUrl: avatarUrl,
            coverUrl: coverUrl,
            joinedAt: user.joinedAt,
            verifiedFlags: user.verifiedFlags,
            stats: user.stats
        )

        userVM.errorMessage = nil
        await userVM.updateProfile(updated)
        if let message = userVM.errorMessage {
            let lower = message.lowercased()
            errorMessage = lower.contains("duplicate") || lower.contains("unique")
                ? "That username is taken."
                : "Couldn't save your profile. Try again."
            userVM.errorMessage = nil
            ARHaptics.warning()
            return
        }

        UserDefaults.standard.set(updated.name ?? updated.username, forKey: ARAppRootView.displayNameDefaultsKey)
        await CreatorCache.shared.refresh(user.id)
        ARHaptics.success()
        dismiss()
    }
}
