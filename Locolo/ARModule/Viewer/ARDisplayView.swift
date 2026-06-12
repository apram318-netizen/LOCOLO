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
            // A green dot appears when the AR session is fully geo-localized.
            if vm.isLocalized {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .padding(.top, 50)
                            .padding(.trailing, 20)
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


            // MARK: - Status Message
            // Shows helpful AR messages at the bottom (accuracy, loading, errors, etc).
            if let msg = vm.statusMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.callout)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.bottom, 40)
                }
                .animation(.easeInOut, value: msg)
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


// MARK: - Shared ARView
// Keeps one shared ARView instance so the AR session does not reset unnecessarily.
final class SharedARViewHolder {
    static let shared = ARView(frame: .zero)
    static var triggerTapRecognizer: UITapGestureRecognizer?
}
