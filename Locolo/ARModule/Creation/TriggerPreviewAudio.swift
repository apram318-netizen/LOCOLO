//
//  TriggerPreviewAudio.swift
//  Locolo
//
//  One-shot AVAudioPlayer for Create-flow trigger preview (non-AR).
//

import Foundation
import AVFoundation

@MainActor
final class TriggerPreviewAudio {
    static let shared = TriggerPreviewAudio()
    private var player: AVAudioPlayer?

    private init() {}

    func play(url: URL) {
        player?.stop()
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            LocoloLog.ar.error("Preview audio failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
