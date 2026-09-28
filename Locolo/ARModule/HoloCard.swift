//
//  HoloCard.swift
//  Locolo
//
//  Gyroscope-driven holographic card wrapper for Featured / rare surfaces.
//  Respects Reduce Motion (static iridescent sheen only).
//

import SwiftUI
import CoreMotion

struct HoloCard<Content: View>: View {
    var intensity: Double = 1
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = HoloMotionSampler()
    @State private var phase: CGFloat = 0

    var body: some View {
        content()
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : motion.roll * 8 * intensity),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.65
            )
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : motion.pitch * -6 * intensity),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.65
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.cyan.opacity(0.18),
                                Color.pink.opacity(0.22),
                                Color.yellow.opacity(0.15),
                                Color.clear
                            ],
                            startPoint: UnitPoint(x: 0.1 + motion.roll * 0.4 + phase,
                                                  y: 0.0 + motion.pitch * 0.3),
                            endPoint: UnitPoint(x: 0.9 + motion.roll * 0.2,
                                                y: 1.0)
                        )
                    )
                    .blendMode(.softLight)
                    .allowsHitTesting(false)
            }
            .onAppear {
                motion.start()
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: true)) {
                    phase = 0.25
                }
            }
            .onDisappear { motion.stop() }
    }
}

@MainActor
private final class HoloMotionSampler: ObservableObject {
    @Published var pitch: Double = 0
    @Published var roll: Double = 0

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let attitude = data?.attitude else { return }
            // Soft clamp so the card doesn't flip wildly.
            self?.pitch = max(-1, min(1, attitude.pitch))
            self?.roll = max(-1, min(1, attitude.roll))
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
