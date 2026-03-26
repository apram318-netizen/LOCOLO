//
//  NotificationCenterScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 14/11/2025.
//


import SwiftUI

struct NotificationCenterScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject var vm: NotificationViewModel

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header Section
            header
            // MARK: Tabs Section
            tabs
            // MARK: Content Section
            listContent
        }
        .background(
            colorScheme == .dark
            ? Color.black.ignoresSafeArea()
            : Color.white.ignoresSafeArea()
        )
    }

    // MARK: HEADER
    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.title2.bold())
                .foregroundColor(AppColors.primaryText)

            Spacer()

            let unread = vm.notifications.filter { !($0.read ?? false) }.count
            if unread > 0 {
                Text("\(unread) new")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color.adaptive(light: .red.opacity(0.8),
                                       dark: .red.opacity(0.7))
                    )
                    .cornerRadius(10)
            }
        }
        .padding()
    }

    // MARK: TABS
    private var tabs: some View {
        HStack {
            tabButton("General")
            tabButton("Digital Art")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func tabButton(_ label: String) -> some View {
        Button {
            vm.selectedTab = label
        } label: {
            Text(label)
                .foregroundColor(
                    vm.selectedTab == label
                    ? AppColors.primaryText
                    : AppColors.secondaryText
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    vm.selectedTab == label ?
                    AppColors.primaryText.opacity(0.15) : Color.clear
                )
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: LIST CONTENT
    private var listContent: some View {
        ScrollView {
            VStack(spacing: 16) {

                ForEach(vm.selectedTab == "General" ? vm.generalNotifs : vm.artNotifs) { notif in
                    notificationCard(notif)
                        .onTapGesture { vm.markRead(notif) }
                }

            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: CARD UI
    private func notificationCard(_ n: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {

            // Avatar placeholder
            Circle()
                .fill(colorScheme == .dark ?
                      Color.white.opacity(0.15) :
                      Color.black.opacity(0.05))
                .frame(width: 40, height: 40)
                .overlay(
                    Text("MC")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(n.title)
                        .foregroundColor(AppColors.primaryText)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if !(n.read ?? false) {
                        Circle()
                            .fill(
                                Color.adaptive(
                                    light: .black.opacity(0.8),
                                    dark: .white.opacity(0.85)
                                )
                            )
                            .frame(width: 8, height: 8)
                    }
                }

                Text(n.body)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)

                Text(n.timestamp.timeAgo())
                    .foregroundColor(AppColors.secondaryText)
                    .font(.caption)
            }
        }
        .padding()
        .background(
            colorScheme == .dark
            ? AppColors.cardGradientDark
            : AppColors.cardGradientLight
        )
        .cornerRadius(16)
        .shadow(
            color: AppColors.cardShadow.opacity(0.25),
            radius: 8, x: 0, y: 4
        )
    }
}

