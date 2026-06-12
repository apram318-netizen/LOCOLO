//
//  AttendanceCTAView.swift
//  Locolo
//
//  Reusable attendance toggle — used on EventPostView (overlay style, dark bg)
//  and EventDetailView (card style, light bg). Same logic, different skin.
//

import SwiftUI

// MARK: - Style

enum AttendanceCTAStyle {
    case overlay   // frosted glass on dark image background
    case card      // solid on light/dark card background
}

// MARK: - AttendanceCTAView

struct AttendanceCTAView: View {
    @ObservedObject var vm: EventAttendanceViewModel
    var style: AttendanceCTAStyle = .card
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Going / Interested buttons
            HStack(spacing: 10) {
                AttendButton(
                    label: "Going",
                    icon: vm.myStatus == .going ? "checkmark.circle.fill" : "checkmark.circle",
                    isActive: vm.myStatus == .going,
                    activeColors: [.green, .teal],
                    style: style
                ) {
                    vm.toggle(.going)
                }

                AttendButton(
                    label: "Interested",
                    icon: vm.myStatus == .interested ? "heart.fill" : "heart",
                    isActive: vm.myStatus == .interested,
                    activeColors: [.purple, .pink],
                    style: style
                ) {
                    vm.toggle(.interested)
                }
            }

            // Avatar stack + count (only visible when someone's going)
            if vm.goingCount > 0 || vm.interestedCount > 0 {
                HStack(spacing: 8) {
                    attendeeAvatarStack

                    countText

                    Spacer()

                    if let onSeeAll {
                        Button(action: onSeeAll) {
                            Text("See all")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(style == .overlay ? .white.opacity(0.85) : .purple)
                        }
                    }
                }
            }
        }
    }

    // MARK: Avatar stack

    private var attendeeAvatarStack: some View {
        HStack(spacing: -8) {
            ForEach(vm.previews.prefix(3)) { person in
                AsyncImage(url: person.avatarUrl.flatMap(URL.init)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Text(String(person.username.prefix(1)).uppercased())
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(
                        style == .overlay ? Color.black.opacity(0.3) : Color(.systemBackground),
                        lineWidth: 1.5
                    )
                )
            }
        }
    }

    // MARK: Count label

    private var countText: some View {
        Group {
            if vm.goingCount > 0 && vm.interestedCount > 0 {
                Text("\(vm.goingCount) going · \(vm.interestedCount) interested")
            } else if vm.goingCount > 0 {
                Text(vm.goingCount == 1 ? "1 person going" : "\(vm.goingCount) going")
            } else {
                Text(vm.interestedCount == 1 ? "1 interested" : "\(vm.interestedCount) interested")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(style == .overlay ? .white.opacity(0.85) : AppColors.secondaryText)
    }
}

// MARK: - AttendButton

struct AttendButton: View {
    let label: String
    let icon: String
    let isActive: Bool
    let activeColors: [Color]
    let style: AttendanceCTAStyle
    let action: () -> Void

    @State private var bouncing = false

    var body: some View {
        Button {
            bouncing = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { bouncing = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(
                isActive ? .white : (style == .overlay ? .white : AppColors.primaryText)
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background { buttonBackground }
            .clipShape(Capsule())
            .overlay {
                if !isActive {
                    Capsule()
                        .stroke(
                            style == .overlay ? .white.opacity(0.3) : Color(.separator),
                            lineWidth: 1
                        )
                }
            }
        }
        .scaleEffect(bouncing ? 0.93 : (isActive ? 1.04 : 1.0))
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isActive)
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: bouncing)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if isActive {
            LinearGradient(
                colors: activeColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if style == .overlay {
            Color.white.opacity(0.15)
        } else {
            Color(.secondarySystemBackground)
        }
    }
}
