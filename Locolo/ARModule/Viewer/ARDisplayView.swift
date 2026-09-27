//
//  ARDisplayView.swift
//  Locolo
//
//  Created by Apramjot Singh on 14/11/2025.
//
//  This screen shows the AR camera feed and the digital assets
//  placed around the user. It also shows a status message overlay
//  and a small green indicator once AR geo-tracking is fully ready.

import SwiftUI
import RealityKit
import ARKit

struct ARDisplayView: View {
    @StateObject private var vm = ARDisplayViewModel()

    var body: some View {
        ZStack {

            // MARK: - AR Camera View
            // Hosts the ARView from RealityKit and fills the whole screen.
            ARViewContainer(vm: vm)
                .edgesIgnoringSafeArea(.all)


            // MARK: - Localization Indicator
            // Once the session is ready, a small badge shows a green dot plus
            // which placement mode is active (geo-anchored vs GPS mode).
            if vm.isLocalized {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text(vm.trackingModeLabel)
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 50)
                        .padding(.trailing, 20)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("AR ready, \(vm.trackingModeLabel)")
                    }
                    Spacer()
                }
                .transition(.scale)
            }


            // MARK: - Speech Trigger Banner
            // Tells the viewer why the mic is on and what to say.
            if let hint = vm.listeningHint {
                VStack {
                    Label("Listening for: \"\(hint)\"", systemImage: "mic.fill")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 50)
                    Spacer()
                }
            }


            // MARK: - AR Radar
            // A compass ring showing where nearby assets are around you —
            // blips rotate as you turn, drift inward as you approach.
            if vm.isLocalized && !vm.radarBlips.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        ARRadarView(blips: vm.radarBlips, heading: vm.headingDegrees)
                            .padding(.leading, 20)
                            .padding(.bottom, 96)
                        Spacer()
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }

            // MARK: - Status Message
            // Shows helpful AR messages at the bottom (accuracy, loading, errors, etc).
            if let msg = vm.statusMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                        .padding(.bottom, vm.permissionDenied || vm.showRetry ? 108 : 40)
                }
                .animation(.easeInOut, value: msg)
            }

            // MARK: - Recovery actions (WS3)
            // Denied permission or a stuck start gets an actionable button
            // instead of a dead end.
            if vm.permissionDenied || vm.showRetry {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        if vm.permissionDenied {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Open Settings", systemImage: "gearshape.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 18).padding(.vertical, 12)
                                    .background(LinearGradient(colors: [.purple, .pink],
                                                               startPoint: .leading, endPoint: .trailing),
                                                in: Capsule())
                                    .foregroundColor(.white)
                            }
                        }
                        Button {
                            vm.retry()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }

        // MARK: - Startup
        // Resets AR state and begins location updates when the view appears.
        .onAppear {
            vm.resetARState()
            vm.startLocationUpdates()
        }
        // Release the mic and motion sensors when leaving the AR session
        .onDisappear {
            vm.triggerEngine.teardown()
        }
    }
}


// MARK: - ARView Container
// Wraps the shared ARView so SwiftUI can display RealityKit content.

struct ARViewContainer: UIViewRepresentable {
    let vm: ARDisplayViewModel

    func makeUIView(context: Context) -> ARView {
        let view = SharedARViewHolder.shared
        vm.arView = view

        // The ARView is a shared singleton, so remove the recognizer from any
        // previous visit before installing a fresh one.
        if let old = SharedARViewHolder.triggerTapRecognizer {
            view.removeGestureRecognizer(old)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        SharedARViewHolder.triggerTapRecognizer = tap

        // Coaching overlay guides world-tracking initialization and auto-hides
        // once tracking is normal. Reuse one instance across visits. (WS3)
        let coaching = SharedARViewHolder.coachingOverlay ?? {
            let c = ARCoachingOverlayView()
            c.goal = .tracking
            c.activatesAutomatically = true
            c.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            SharedARViewHolder.coachingOverlay = c
            return c
        }()
        coaching.session = view.session
        coaching.frame = view.bounds
        if coaching.superview !== view {
            coaching.removeFromSuperview()
            view.addSubview(coaching)
        }

        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(vm: vm)
    }

    // MARK: Tap → trigger
    // Hit-tests the tapped point and forwards the entity to the trigger engine.
    // Gesture callbacks always arrive on the main thread, so MainActor is safe.
    @MainActor
    final class Coordinator {
        let vm: ARDisplayViewModel

        init(vm: ARDisplayViewModel) {
            self.vm = vm
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = vm.arView else { return }
            let point = gesture.location(in: arView)
            if let entity = arView.entity(at: point) {
                vm.triggerEngine.handleTap(on: entity)
            }
        }
    }
}


// MARK: - AR Radar
// Glass compass ring: N marker tracks true north, purple blips are nearby
// assets (angle = bearing relative to facing, radius = distance).
struct ARRadarView: View {
    let blips: [ARDisplayViewModel.RadarBlip]
    let heading: Double?

    private let size: CGFloat = 108

    var body: some View {
        ZStack {
            // Ring + sweep background
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            Circle()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                .frame(width: size * 0.55, height: size * 0.55)

            // Facing wedge (what's roughly in front of the camera)
            RadarWedge()
                .fill(LinearGradient(colors: [Color.purple.opacity(0.35), .clear],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: size, height: size)

            // North marker, rotating opposite the device heading
            if let heading {
                Text("N")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .offset(y: -size / 2 + 9)
                    .rotationEffect(.degrees(-heading))
            }

            // Asset blips
            ForEach(blips) { blip in
                Circle()
                    .fill(LinearGradient(colors: [.purple, .pink],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 7, height: 7)
                    .shadow(color: .purple.opacity(0.8), radius: 3)
                    .offset(blipOffset(blip))
            }

            // You
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .shadow(color: .white.opacity(0.9), radius: 2)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(blips.count) AR asset\(blips.count == 1 ? "" : "s") nearby")
    }

    private func blipOffset(_ blip: ARDisplayViewModel.RadarBlip) -> CGSize {
        // Up = the direction the device is facing. Keep a small inner margin.
        let r = (size / 2 - 10) * CGFloat(max(blip.normalizedDistance, 0.12))
        return CGSize(width: r * CGFloat(sin(blip.relativeAngle)),
                      height: -r * CGFloat(cos(blip.relativeAngle)))
    }
}

/// Narrow triangle from the center to the top edge — the facing indicator.
private struct RadarWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addLine(to: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Shared ARView
// Keeps one shared ARView instance so the AR session does not reset unnecessarily.
final class SharedARViewHolder {
    static let shared = ARView(frame: .zero)
    static var triggerTapRecognizer: UITapGestureRecognizer?
    static var coachingOverlay: ARCoachingOverlayView?
}
