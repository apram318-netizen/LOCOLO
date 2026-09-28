//
//  ARCelebration.swift
//  Locolo
//
//  Gen-Z delight: bursts + animated counters. Respects Reduce Motion.
//

import SwiftUI

struct CelebrationBurst: View {
    var symbol: String = "sparkles"
    var colors: [Color] = [.yellow, .orange, .pink, .purple]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Circle()
                    .fill(colors[i % colors.count].opacity(0.85))
                    .frame(width: reduceMotion ? 6 : 8, height: reduceMotion ? 6 : 8)
                    .offset(y: go ? -56 : 0)
                    .rotationEffect(.degrees(Double(i) / 12 * 360))
                    .opacity(go ? 0 : 1)
            }
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .scaleEffect(go ? 1.15 : 0.4)
                .opacity(go ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                go = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { go = true }
            }
        }
        .allowsHitTesting(false)
    }
}

struct AnimatedCounter: View {
    let value: Int
    var font: Font = .title2.bold().monospacedDigit()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed = 0

    var body: some View {
        Text("\(displayed)")
            .font(font)
            .contentTransition(.numericText())
            .onAppear { animate(to: value) }
            .onChange(of: value) { _, v in animate(to: v) }
    }

    private func animate(to target: Int) {
        if reduceMotion {
            displayed = target
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            displayed = target
        }
    }
}

/// Full-screen flash celebration overlay.
struct CelebrationOverlay: ViewModifier {
    @Binding var trigger: Bool
    var symbol: String = "sparkles"

    func body(content: Content) -> some View {
        content.overlay {
            if trigger {
                CelebrationBurst(symbol: symbol)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                            withAnimation { trigger = false }
                        }
                    }
            }
        }
    }
}

extension View {
    func celebration(trigger: Binding<Bool>, symbol: String = "sparkles") -> some View {
        modifier(CelebrationOverlay(trigger: trigger, symbol: symbol))
    }
}
