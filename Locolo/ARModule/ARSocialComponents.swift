//
//  ARSocialComponents.swift
//  Locolo
//
//  Social-network building blocks shared across the AR module: count badges,
//  follow buttons wired to FollowStore, verified marks, shimmer skeletons,
//  and compact count / relative-time formatting.
//

import SwiftUI

// MARK: - Formatting

extension Int {
    /// 950 → "950", 1_240 → "1.2K", 3_400_000 → "3.4M".
    var compactFormatted: String {
        let n = Double(self)
        switch abs(n) {
        case 1_000_000...: return Self.trim(n / 1_000_000) + "M"
        case 10_000...:    return "\(Int(n / 1_000))K"
        case 1_000...:     return Self.trim(n / 1_000) + "K"
        default:           return "\(self)"
        }
    }

    private static func trim(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

extension Date {
    /// Instagram-style short relative time: "now", "4m", "3h", "2d", "5w", "12 Mar".
    var shortRelative: String {
        let seconds = max(0, Date().timeIntervalSince(self))
        switch seconds {
        case ..<60:        return "now"
        case ..<3600:      return "\(Int(seconds / 60))m"
        case ..<86_400:    return "\(Int(seconds / 3600))h"
        case ..<604_800:   return "\(Int(seconds / 86_400))d"
        case ..<2_419_200: return "\(Int(seconds / 604_800))w"
        default:
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate(
                Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year) ? "d MMM" : "d MMM yyyy")
            return f.string(from: self)
        }
    }
}

// MARK: - Badges

/// Red count badge (caps at 99+).
struct ARCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, count > 9 ? 5 : 0)
                .frame(minWidth: 17, minHeight: 17)
                .background(Capsule().fill(Color(hex: "FF3B5C")))
                .overlay(Capsule().strokeBorder(ARDesign.screenBackground, lineWidth: 2))
                .transition(.scale.combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }
}

/// Header icon button with an unread badge.
struct ARBadgedIconButton: View {
    let icon: String
    let label: String
    let badge: Int
    let action: () -> Void

    var body: some View {
        ARHeaderIconButton(icon: icon, label: badge > 0 ? "\(label), \(badge) new" : label, action: action)
            .overlay(alignment: .topTrailing) {
                ARCountBadge(count: badge)
                    .offset(x: 5, y: -4)
            }
            .animation(ARDesign.spring, value: badge)
    }
}

struct ARVerifiedBadge: View {
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size))
            .foregroundStyle(.white, Color(hex: "3B82F6"))
            .accessibilityLabel("Verified")
    }
}

/// Name + optional verified seal, the canonical way to print a creator.
struct ARCreatorName: View {
    let creator: ARCreator?
    var fallback: String = "Creator"
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        HStack(spacing: 4) {
            Text(creator?.displayName ?? fallback)
                .font(font)
                .foregroundColor(.primary)
                .lineLimit(1)
            if creator?.isVerified == true {
                ARVerifiedBadge(size: 12)
            }
        }
    }
}

// MARK: - Follow button

/// Follow / Following toggle bound to FollowStore; hidden for yourself.
struct ARFollowButton: View {
    enum Style { case regular, compact, prominent }

    let userId: UUID
    var style: Style = .regular
    /// Label for the not-yet-following state, e.g. "Follow back".
    var followTitle: String = "Follow"

    @ObservedObject private var follows = FollowStore.shared

    private var isFollowing: Bool { follows.isFollowing(userId) }
    private var isPending: Bool { follows.pending.contains(userId) }

    var body: some View {
        if follows.me != nil && follows.me != userId {
            Button {
                if isFollowing { ARHaptics.tick() } else { ARHaptics.success() }
                Task { await follows.toggle(userId) }
            } label: {
                Text(isFollowing ? "Following" : followTitle)
                    .font(style == .compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                    .foregroundColor(isFollowing ? .primary : .white)
                    .padding(.horizontal, style == .compact ? 12 : 18)
                    .padding(.vertical, style == .compact ? 6 : 9)
                    .frame(maxWidth: style == .prominent ? .infinity : nil)
                    .background(
                        Capsule().fill(isFollowing
                                       ? AnyShapeStyle(ARDesign.headerButtonCircle)
                                       : AnyShapeStyle(AppColors.purplePinkGradient))
                    )
                    .overlay(Capsule().strokeBorder(isFollowing ? ARDesign.hairline : .clear, lineWidth: 1))
                    .opacity(isPending ? 0.6 : 1)
                    .contentTransition(.identity)
            }
            .buttonStyle(.plain)
            .disabled(isPending)
            .animation(ARDesign.spring, value: isFollowing)
            .accessibilityLabel(isFollowing ? "Following. Double tap to unfollow" : followTitle)
        }
    }
}

// MARK: - Skeletons

private struct ARShimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.35), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                    .blendMode(.plusLighter)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func arShimmer() -> some View { modifier(ARShimmer()) }
}

struct ARSkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ARDesign.headerButtonCircle)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Placeholder shaped like ARSocialAssetCard.
struct ARFeedCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(ARDesign.headerButtonCircle).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    ARSkeletonBlock(width: 120, height: 11)
                    ARSkeletonBlock(width: 70, height: 9)
                }
                Spacer()
            }
            ARSkeletonBlock(height: 190, cornerRadius: 16)
            ARSkeletonBlock(width: 180, height: 14)
            ARSkeletonBlock(width: 240, height: 10)
            HStack(spacing: 16) {
                ARSkeletonBlock(width: 54, height: 18, cornerRadius: 9)
                ARSkeletonBlock(width: 54, height: 18, cornerRadius: 9)
                Spacer()
                ARSkeletonBlock(width: 28, height: 18, cornerRadius: 9)
            }
        }
        .padding(14)
        .arGlassCard(cornerRadius: 22)
        .arShimmer()
        .accessibilityHidden(true)
    }
}

/// Placeholder row for lists (inbox, activity, comments).
struct ARRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(ARDesign.headerButtonCircle).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 7) {
                ARSkeletonBlock(width: 140, height: 12)
                ARSkeletonBlock(width: 200, height: 10)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .arShimmer()
        .accessibilityHidden(true)
    }
}
