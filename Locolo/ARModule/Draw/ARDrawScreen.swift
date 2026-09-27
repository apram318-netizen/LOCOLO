//
//  ARDrawScreen.swift
//  Locolo
//
//  Full-screen air-drawing experience (WS7): pinch (or drag) to draw strokes in
//  AR, pick a colour/width, undo, then Finish to export a USDZ that flows into
//  the normal create pipeline.
//

import SwiftUI

struct ARDrawScreen: View {
    /// Called with the exported .usdz URL when the user finishes.
    var onFinish: (URL) -> Void
    var onCancel: () -> Void = {}

    @StateObject private var vm = ARDrawViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var exportError: String?

    private let palette: [(String, UIColor)] = [
        ("Violet", UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1)),
        ("Pink", UIColor(red: 0.93, green: 0.28, blue: 0.60, alpha: 1)),
        ("Cyan", UIColor(red: 0.03, green: 0.57, blue: 0.70, alpha: 1)),
        ("Amber", UIColor(red: 0.85, green: 0.47, blue: 0.02, alpha: 1)),
        ("White", .white)
    ]

    var body: some View {
        ZStack {
            #if targetEnvironment(simulator)
            simulatorNotice
            #else
            ARDrawView(vm: vm).ignoresSafeArea()
            #endif

            VStack {
                topBar
                Spacer()
                Text(vm.statusHint)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 6)
                controls
            }
            .padding(16)
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { _ in exportError = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportError ?? "") }
    }

    private var topBar: some View {
        HStack {
            Button { onCancel(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.bold()).foregroundColor(.white)
                    .padding(10).background(Circle().fill(.black.opacity(0.4)))
            }
            Spacer()
            Picker("Input", selection: $vm.useHandTracking) {
                Text("Hand").tag(true)
                Text("Touch").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            // Colour palette
            HStack(spacing: 12) {
                ForEach(palette, id: \.0) { name, color in
                    Circle()
                        .fill(Color(color))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9),
                                                       lineWidth: vm.strokeColor == color ? 3 : 1))
                        .onTapGesture { vm.strokeColor = color }
                }
            }

            HStack(spacing: 14) {
                Button { vm.undo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!vm.canUndo)

                Button(role: .destructive) { vm.clearAll() } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(vm.strokeCount == 0)

                Spacer()

                Button { finish() } label: {
                    Text("Finish")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Capsule().fill(AppColors.purplePinkGradient))
                }
                .disabled(!vm.hasContent)
            }
            .font(.subheadline)
            .tint(.white)
            .padding(.horizontal, 4)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var simulatorNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.draw").font(.largeTitle).foregroundColor(.purple)
            Text("Air-drawing needs a real device")
                .font(.headline)
            Text("Camera + hand tracking aren't available in the simulator.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding()
    }

    private func finish() {
        do {
            let url = try vm.exportUSDZ()
            onFinish(url)
            dismiss()
        } catch {
            exportError = "Couldn't export your drawing. Try adding a few more strokes."
        }
    }
}
