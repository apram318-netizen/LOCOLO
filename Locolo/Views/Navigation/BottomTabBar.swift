//
//  BottomTabBar.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import SwiftUI

struct BottomTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selected: Int

    private let iconSize: CGFloat = 26
    private let horizontalSpacing: CGFloat = 32
    private let verticalPadding: CGFloat = 6

    var body: some View {
        // MARK: Tab Buttons Section
        // Horizontal stack of five tab buttons for main app navigation
        HStack(spacing: horizontalSpacing) {
            tabButton(index: 0, systemName: "house.fill")
            tabButton(index: 1, systemName: "magnifyingglass")
            Button(action: { selected = 2 }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
            tabButton(index: 3, systemName: "arkit")
            tabButton(index: 4, systemName: "person.crop.circle")
        }
        .padding(.horizontal, horizontalSpacing / 2)
        .padding(.vertical, verticalPadding)
        .background(
            LinearGradient(
                colors: [
                    Color.adaptive(
                        light: Color.white.opacity(0.9),
                        dark: Color(hex: "#0A0A0A").opacity(0.95)
                    ),
                    Color.adaptive(
                        light: Color(hex: "#F9F9F9").opacity(0.7),
                        dark: Color(hex: "#1A1A1A").opacity(0.85)
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
        .ignoresSafeArea(edges: .bottom)
    }
    // MARK: Tab Button Helper
    // Creates individual tab button with selected state styling and gradient effects
    private func tabButton(index: Int, systemName: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                selected = index
            }
        }) {
            ZStack {
                if selected == index {
                    // switch gradient based on mode so dark mode doesn't flatten out
                    let activeGradient = colorScheme == .dark ? AppColors.blueCyanMutedGradient : AppColors.purplePinkMutedGradient

                    // main glow behind icon
                    activeGradient
                        .clipShape(Circle())
                        .frame(width: 48, height: 48)
                        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
                        .transition(.scale)

                    // glass overlay for that subtle depth
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.2), lineWidth: 1)
                        )
                        .shadow(color: colorScheme == .dark ? .white.opacity(0.03) : .white.opacity(0.05), radius: 3)
                        .blendMode(.plusLighter)
                        .scaleEffect(1.05)

                    // light reflection and curved highlight — keep it soft and subtle
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.35),
                                    Color.white.opacity(0.03),
                                    Color.clear
                                ]),
                                center: .topLeading,
                                startRadius: 2,
                                endRadius: 30
                            )
                        )
                        .overlay {
                            if colorScheme == .dark {
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.1),
                                        Color.white.opacity(0.03),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .blendMode(.overlay)
                            }
                        }
                        // a tiny bit more blur so the reflection melts in, not just sits on top
                        .blur(radius: colorScheme == .dark ? 0.6 : 0.3)
                        .blendMode(.softLight)
                        .scaleEffect(1.04)
                        // fade it back slightly so the bubble doesn't overpower the icon
                        .opacity(colorScheme == .dark ? 0.45 : 0.5)
                        .allowsHitTesting(false)
                        .rotation3DEffect(.degrees(3), axis: (x: 1, y: 0.5, z: 0))

                    // add a bit of inner shadow in dark mode so the droplet feels thicker and more 3D
                    if colorScheme == .dark {
                        Circle()
                            .stroke(Color.black.opacity(0.35), lineWidth: 1)
                            .blur(radius: 2)
                            .offset(y: 1.2)
                            .mask(Circle().fill(LinearGradient(colors: [.black, .clear],
                                                               startPoint: .bottom,
                                                               endPoint: .top)))
                    }
                }
                
                // icon setup
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    // gradient fill to keep icons visible and give them a bit of volume
                 // adaptive icon fill – black for selected in dark mode, gradient otherwise
                    .foregroundStyle({
                        if colorScheme == .dark {
                            if selected == index {
                                return AnyShapeStyle(Color.black)
                            } else {
                                return AnyShapeStyle(
                                    LinearGradient(
                                        colors: [.white.opacity(0.9), .gray.opacity(0.6)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                        } else {
                            return AnyShapeStyle(Color.black)
                        }
                    }())
                    .shadow(color: colorScheme == .dark ? .black.opacity(0.6) : .white.opacity(0.5), radius: 1, y: 1)
                    .scaleEffect(selected == index ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
                
            }
            .frame(width: 50, height: 40)
            .contentShape(Rectangle())
            .ignoresSafeArea()
        }
        .buttonStyle(.plain)
    }
}
