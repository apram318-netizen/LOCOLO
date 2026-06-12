//
//  TriggerConfigView.swift
//  Locolo
//
//  Form section where the poster picks how the asset's animation fires:
//  tap, walking within a chosen distance, saying an exact phrase, or a
//  preset shake pattern.
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
            Text("Animation plays when the viewer taps the asset in AR.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .proximity:
            VStack(alignment: .leading, spacing: 6) {
                Slider(value: $vm.triggerDistance, in: 1...50, step: 1)
                Text("Plays when the viewer comes within \(Int(vm.triggerDistance)) m")
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
                Text("Plays when the viewer says this phrase out loud.")
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
                Text("Plays when the viewer moves their phone this way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
