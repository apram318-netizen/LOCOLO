//
//  ARDesign.swift
//  Locolo
//
//  Small design system for the standalone AR experience: glass surfaces,
//  chart palette, shared header, stat tiles, haptics, and a couple of
//  DigitalAsset helpers that several AR screens need.
//

import SwiftUI
import CoreLocation

// MARK: - Design tokens

enum ARDesign {
    /// Standard spring used across the AR module for tab/selection animation.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.82)

    /// Brand accent used for single-series charts and active states.
    static let accent = Color(hex: "8B5CF6")

    /// Categorical chart palette. Validated for lightness, chroma, CVD
    /// separation and contrast against both light and dark surfaces —
    /// keep the order fixed and pair with direct labels or a legend.
    static let chartCategorical: [Color] = [
        Color(hex: "8B5CF6"), // violet
        Color(hex: "0891B2"), // cyan
        Color(hex: "EC4899"), // pink
        Color(hex: "D97706"), // amber
        Color(hex: "16A34A")  // green
    ]

    static let screenBackground = Color.adaptive(
        light: Color(.systemGroupedBackground),
        dark: Color(red: 0.04, green: 0.02, blue: 0.10)
    )

    static let headerButtonCircle = Color.adaptive(
        light: Color.black.opacity(0.07),
        dark: Color.white.opacity(0.12)
    )

    static let hairline = Color.adaptive(
        light: Color.black.opacity(0.08),
        dark: Color.white.opacity(0.08)
    )
}

// MARK: - Haptics

enum ARHaptics {
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func pulse(intensity: CGFloat) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: max(0.1, min(1, intensity)))
    }

    /// An AR asset materialized into view — a soft double tick.
    static func discovery() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.impactOccurred(intensity: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            g.impactOccurred(intensity: 0.9)
        }
    }

    /// A trigger fired (animation/media played) — a crisp medium tap.
    static func triggerFired() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.85)
    }

    /// "You found it!" — a celebratory success ripple.
    static func found() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.8)
        }
    }
}

// MARK: - Glass card

struct ARGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ARDesign.hairline, lineWidth: 1)
            )
            .shadow(color: AppColors.cardShadow, radius: 14, x: 0, y: 6)
    }
}

extension View {
    func arGlassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(ARGlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Shared header

/// Consistent floating header for the four AR tabs: exit button on the
/// left, title in the middle, screen-specific actions on the right.
struct ARGlassHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var onExit: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let onExit {
                Button(action: onExit) {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .padding(9)
                        .background(Circle().fill(ARDesign.headerButtonCircle))
                }
                .accessibilityLabel("Exit Loco AR")
            }

            Spacer()

            VStack(spacing: 2) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer()

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    ARDesign.screenBackground,
                    ARDesign.screenBackground.opacity(0.92),
                    ARDesign.screenBackground.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

/// Small circular icon button used in headers.
struct ARHeaderIconButton: View {
    let icon: String
    let label: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundColor(prominent ? .white : .primary)
                .padding(9)
                .background(
                    Circle().fill(
                        prominent
                            ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink],
                                                           startPoint: .topLeading,
                                                           endPoint: .bottomTrailing))
                            : AnyShapeStyle(ARDesign.headerButtonCircle)
                    )
                )
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Section header

struct ARSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 22)

                Text(title)
                    .font(.title3.bold())
                    .foregroundColor(.primary)

                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundColor(.purple.opacity(0.8))
                }
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Stat tile

struct ARStatTile: View {
    let value: String
    let label: String
    let icon: String
    var tint: Color = ARDesign.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tint)
                .padding(8)
                .background(Circle().fill(tint.opacity(0.14)))

            Text(value)
                .font(.title3.bold())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .arGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Filter chip

struct ARFilterChip: View {
    let title: String
    var icon: String? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isActive
                        ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink],
                                                       startPoint: .leading,
                                                       endPoint: .trailing))
                        : AnyShapeStyle(.ultraThinMaterial)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isActive ? Color.clear : ARDesign.hairline,
                    lineWidth: 1
                )
            )
            .foregroundColor(isActive ? .white : .primary)
        }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - DigitalAsset helpers

extension DigitalAsset {
    /// Views + hype: the module-wide popularity score.
    var engagementScore: Int { viewCount + hypeCount }

    /// Distance from the user's live (or last stored) location, in meters.
    var distanceMeters: Double? {
        guard let lat = latitude, let lon = longitude else { return nil }
        let manager = LocationManager.shared
        guard let coord = manager.userLocation ?? manager.latestStoredLocation else { return nil }
        return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lon))
    }

    var distanceLabel: String? {
        guard let meters = distanceMeters else { return nil }
        return meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)
    }

    /// Best human-readable location string available on the asset.
    var displayLocation: String? {
        if let address, !address.isEmpty { return address }
        if let locationName, !locationName.isEmpty { return locationName }
        return nil
    }

    /// Lowercased category on the canonical taxonomy (art/photo/3d/audio/other).
    /// Assets created before the taxonomy fix were saved as "ar_model"; they are
    /// 3D models and must filter/chart as such.
    var normalizedCategory: String? {
        guard let raw = category?.lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "ar_model", "model", "usdz": return "3d"
        default: return raw
        }
    }

    var categoryLabel: String? {
        normalizedCategory?.capitalized
    }

    /// Creation writes public / private / friends; legacy rows say "normal"
    /// (an old rarity value), which behaves as public.
    var normalizedVisibility: String {
        let raw = visibility.lowercased()
        return raw == "normal" || raw.isEmpty ? "public" : raw
    }
}
