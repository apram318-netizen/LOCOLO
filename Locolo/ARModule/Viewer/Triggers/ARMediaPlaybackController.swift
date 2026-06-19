//
//  ARMediaPlaybackController.swift
//  Locolo
//
//  Plays optional audio/video sidecar media when an AR asset trigger fires.
//  MP4/MOV files play their audio track for now; visual video surfaces can be
//  layered in later without changing the trigger API.
//

import AVFoundation
import Foundation

@MainActor
final class ARMediaPlaybackController {
    private var players: [UUID: AVPlayer] = [:]

    var onPlaybackMessage: ((String) -> Void)?

    func playMedia(for asset: DigitalAsset) {
        guard let mediaUrl = asset.mediaUrl,
              let remoteURL = URL(string: mediaUrl)
        else {
            return
        }

        configureAudioSession()

        let playbackURL = MediaCache.shared.localURL(forRemoteURL: remoteURL) ?? remoteURL
        let player = AVPlayer(url: playbackURL)
        players[asset.id] = player

        player.seek(to: .zero)
        player.play()

        let label = asset.mediaType == "video" ? "Playing video sound" : "Playing audio"
        onPlaybackMessage?("\(label): \(asset.name ?? "AR asset")")
    }

    func stopAll() {
        for player in players.values {
            player.pause()
        }
        players.removeAll()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            print("AR media audio session failed:", error.localizedDescription)
        }
    }
}
