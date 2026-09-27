//
//  ARComponents.swift
//  Locolo
//
//  Shared, on-brand building blocks used across the AR module so loading and
//  empty states feel like one system (glass, purple→pink gradient, rounded).
//

import SwiftUI

// MARK: - Avatar

/// Circular avatar with a gradient initials fallback.
struct ARAvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Branded wordmark

/// The LOCOLO wordmark rendered in the brand gradient. Reused on the launch
/// screen and anywhere the brand needs to appear.
struct LocoloWordmark: View {
    var size: CGFloat = 40

    var body: some View {
        Text("LOCOLO")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(size * 0.06)
            .foregroundStyle(
                LinearGradient(colors: [.purple, .pink, .blue],
                               startPoint: .leading, endPoint: .trailing)
            )
            .accessibilityLabel("Locolo")
    }
}

// MARK: - Loading

/// Consistent full-bleed loading state: a breathing gradient orb + label.
struct ARLoadingView: View {
    var message: String = "Loading…"
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppColors.purplePinkGradient)
                    .frame(width: 54, height: 54)
                    .blur(radius: 6)
                    .opacity(pulse ? 0.9 : 0.5)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                ProgressView()
                    .tint(.white)
            }
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Empty state

/// Consistent inline empty state: soft icon, title, optional subtitle, and an
/// optional call-to-action.
struct ARInlineEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(AppColors.purplePinkGradient)
            }

            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(AppColors.purplePinkGradient))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
