//
//  AppColors.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/9/2025.
//


import SwiftUI

struct AppColors {
    
    // MARK: - Base
    static let background = Color.adaptive(light: .white, dark: Color(.systemBackground))
    static let cardBackground = Color.adaptive(light: .white, dark: Color(.secondarySystemBackground))
    static let cardShadow = Color.adaptive(light: Color.black.opacity(0.05),
                                           dark: Color.black.opacity(0.8))
    
    // MARK: - Backgrounds
    static let screenBackground = Color.adaptive(
        light: Color(.systemGroupedBackground),
        dark: Color(.black)
    )
    
    
    static let cardGradientLight = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.92, blue: 0.98),
            Color(red: 0.90, green: 0.88, blue: 0.96)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradientDark = LinearGradient(
        colors: [
            Color(red: 0.17, green: 0.10, blue: 0.23),   // deep muted purple
            Color(red: 0.10, green: 0.06, blue: 0.16)    // very dark plum
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // MARK: - Text
    static let primaryText = Color.adaptive(
        light: .black,
        dark: .white
    )
    static let secondaryText = Color.adaptive(
        light: .gray,
        dark: .gray.opacity(0.6)
    )
    
    // MARK: - Badges
    static let priceBadge = Color.adaptive(
        light: Color.green.opacity(0.15),
        dark: Color.green.opacity(0.25)
    )
    static let categoryBadge = Color.adaptive(
        light: Color.blue.opacity(0.15),
        dark: Color.blue.opacity(0.25)
    )
    
    static let trendingBadge = LinearGradient(
        colors: [
            Color.adaptive(light: .orange, dark: .yellow),
            Color.adaptive(light: .red, dark: .orange)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // MARK: - Accent
    static let ratingStar = Color.adaptive(
        light: .yellow,
        dark: .yellow.opacity(0.9)
    )
    
    // MARK: - Gradients
    static let purplePinkGradient = LinearGradient(
        colors: [
            Color.adaptive(light: .purple, dark: .pink.opacity(0.8)),
            Color.adaptive(light: .pink, dark: .purple)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let blueCyanGradient = LinearGradient(
        colors: [
            Color.adaptive(light: .blue, dark: .cyan),
            Color.adaptive(light: .cyan, dark: .teal)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let blueCyanMutedGradient = LinearGradient(
        colors: [
            Color.adaptive(
                light: Color(red: 0.08, green: 0.22, blue: 0.45),   // deep blue
                dark:  Color(red: 0.0,  green: 0.33, blue: 0.38)    // dark teal-cyan
            ),
            Color.adaptive(
                light: Color(red: 0.0,  green: 0.47, blue: 0.55),   // muted cyan
                dark:  Color(red: 0.0,  green: 0.26, blue: 0.29)    // duller teal
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let purplePinkMutedGradient = LinearGradient(
        colors: [
            Color.adaptive(
                light: Color(red: 0.32, green: 0.13, blue: 0.44),   // muted royal purple
                dark:  Color(red: 0.36, green: 0.12, blue: 0.40)    // low-light magenta tone
            ),
            Color.adaptive(
                light: Color(red: 0.58, green: 0.27, blue: 0.46),   // dusty mauve-pink
                dark:  Color(red: 0.43, green: 0.19, blue: 0.39)    // deep plum
            )
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    
    static let greenEmeraldGradient = LinearGradient(
        colors: [
            Color.adaptive(light: .green, dark: .teal),
            Color.adaptive(light: .teal, dark: .green)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // MARK: - Rarity gradients
    static func rarityGradient(_ rarity: String) -> LinearGradient {
        switch rarity.lowercased() {
        case "legendary":
            return LinearGradient(colors: [
                Color.adaptive(light: .yellow, dark: .orange),
                Color.adaptive(light: .orange, dark: .red),
                Color.adaptive(light: .red, dark: .pink)
            ], startPoint: .leading, endPoint: .trailing)
        case "rare":
            return LinearGradient(colors: [
                Color.adaptive(light: .purple, dark: .pink),
                Color.adaptive(light: .pink, dark: .purple)
            ], startPoint: .leading, endPoint: .trailing)
        case "uncommon":
            return LinearGradient(colors: [
                Color.adaptive(light: .blue, dark: .cyan),
                Color.adaptive(light: .cyan, dark: .teal)
            ], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [
                Color.adaptive(light: .gray, dark: .gray.opacity(0.6)),
                Color.adaptive(light: .gray.opacity(0.8), dark: .gray.opacity(0.4))
            ], startPoint: .leading, endPoint: .trailing)
        }
    }
}




// Adding in the adaptive colour for the user's interface style
extension Color {
    
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}


