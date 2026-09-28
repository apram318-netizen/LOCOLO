//
//  TriggerConfigView.swift
//  Locolo
//
//  Form section where the poster picks how the asset's animation fires.
//

import SwiftUI

struct TriggerConfigView: View {
    @ObservedObject var vm: ARCreateViewModel

    var body: some View {
        Picker("Trigger", selection: $vm.triggerType) {
            ForEach(TriggerType.allCases) { type in
                Text(type.label).tag(type)
            }
        }

        switch vm.triggerType {
        case .tap:
            Text("The asset reacts when the viewer taps it in AR.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .proximity:
            VStack(alignment: .leading, spacing: 6) {
                Slider(value: $vm.triggerDistance, in: 1...50, step: 1)
                Text("Reacts when the viewer comes within \(Int(vm.triggerDistance)) m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Tip: GPS accuracy makes distances under ~3 m unreliable.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .speech:
            VStack(alignment: .leading, spacing: 6) {
                TextField("Exact phrase, e.g. \"open sesame\"", text: $vm.triggerPhrase)
                    .textInputAutocapitalization(.never)
                Text("Reacts when the viewer says this phrase out loud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .shake:
            VStack(alignment: .leading, spacing: 6) {
                Picker("Pattern", selection: $vm.shakePattern) {
                    ForEach(ShakePattern.allCases) { pattern in
                        Text(pattern.label).tag(pattern)
                    }
                }
                .pickerStyle(.segmented)
                Text("Reacts when the viewer moves their phone this way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .gaze:
            VStack(alignment: .leading, spacing: 6) {
                Slider(value: $vm.gazeSeconds, in: 0.5...5, step: 0.5)
                Text("Reacts after looking at it for \(vm.gazeSeconds, specifier: "%.1f") s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .timeOfDay:
            VStack(alignment: .leading, spacing: 8) {
                Stepper("From \(vm.todStartHour):00", value: $vm.todStartHour, in: 0...23)
                Stepper("Until \(vm.todEndHour):00", value: $vm.todEndHour, in: 0...23)
                Text("Fires once while the viewer is near and the local clock is in this window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .longPress:
            Text("The asset reacts when the viewer presses and holds it — like petting.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .multiTap:
            VStack(alignment: .leading, spacing: 6) {
                Stepper("\(vm.multiTapCount) taps", value: $vm.multiTapCount, in: 2...6)
                Text("Reacts after this many quick taps on the asset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .walkAround:
            VStack(alignment: .leading, spacing: 6) {
                Slider(value: $vm.orbitDegrees, in: 90...360, step: 15)
                Text("Reacts after walking ~\(Int(vm.orbitDegrees))° around it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
