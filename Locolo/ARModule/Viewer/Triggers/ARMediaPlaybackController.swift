//
//  ARMediaPlaybackController.swift
//  Locolo
//
//  Plays an AR asset's optional sidecar media when its trigger fires:
//   • Audio  → RealityKit SPATIAL audio anchored to the asset (sound comes from
//              the object and attenuates with distance), with a flat AVPlayer
//              fallback if the spatial resource can't load.
//   • Video  → rendered as a VIDEO TEXTURE on a plane above the asset (a
//              floating screen in the world), not just its audio track.
//

import AVFoundation
import Foundation
import RealityKit

@MainActor
final class ARMediaPlaybackController {
    private var players: [UUID: AVPlayer] = [:]           // flat-audio + video players
    private var audioControllers: [UUID: AudioPlaybackController] = [:]
    private var videoScreens: [UUID: Entity] = [:]

    var onPlaybackMessage: ((String) -> Void)?

    /// Play `asset`'s media, spatialized on `entity` when possible.
    func playMedia(for asset: DigitalAsset, on entity: Entity?) {
        guard let mediaUrl = asset.mediaUrl, let remoteURL = URL(string: mediaUrl) else { return }
        configureAudioSession()
        let localURL = MediaCache.shared.localURL(forRemoteURL: remoteURL) ?? remoteURL

        if asset.mediaType == "video" {
            playVideo(asset: asset, url: localURL, on: entity)
        } else {
            playAudio(asset: asset, url: localURL, on: entity)
        }
    }

    // MARK: Spatial audio

    private func playAudio(asset: DigitalAsset, url: URL, on entity: Entity?) {
        onPlaybackMessage?("Playing audio: \(asset.name ?? "AR asset")")

        // Prefer RealityKit spatial audio anchored to the entity (same Combine
        // LoadRequest pattern the viewer uses for models), flat fallback on fail.
        guard let entity else { playFlatAudio(asset: asset, url: url); return }
        let assetId = asset.id
        do {
            let resource = try AudioFileResource.load(
                contentsOf: url,
                withName: assetId.uuidString,
                inputMode: .spatial,
                loadingStrategy: .preload,
                shouldLoop: false
            )
            let controller = entity.prepareAudio(resource)
            controller.play()
            audioControllers[assetId] = controller
        } catch {
            playFlatAudio(asset: asset, url: url)
        }
    }

    private func playFlatAudio(asset: DigitalAsset, url: URL) {
        let player = AVPlayer(url: url)
        players[asset.id] = player
        player.seek(to: .zero)
        player.play()
    }

    // MARK: Video-as-texture

    private func playVideo(asset: DigitalAsset, url: URL, on entity: Entity?) {
        onPlaybackMessage?("Playing video: \(asset.name ?? "AR asset")")

        let player = AVPlayer(url: url)
        players[asset.id] = player

        guard let entity else { player.play(); return }

        // A plane textured with the live video, floated just above the asset.
        let material = VideoMaterial(avPlayer: player)
        let bounds = entity.visualBounds(relativeTo: entity)
        let width = max(0.4, min(bounds.extents.x, 1.2))
        let height = width * 9.0 / 16.0
        let screen = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [material])
        screen.position = [0, bounds.extents.y + height / 2 + 0.05, 0]
        // Face the viewer; RealityKit billboard component keeps it readable.
        screen.components.set(BillboardComponent())
        entity.addChild(screen)
        videoScreens[asset.id] = screen

        player.seek(to: .zero)
        player.play()
    }

    // MARK: Teardown

    func stopAll() {
        for player in players.values { player.pause() }
        players.removeAll()
        for controller in audioControllers.values { controller.stop() }
        audioControllers.removeAll()
        for screen in videoScreens.values { screen.removeFromParent() }
        videoScreens.removeAll()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            LocoloLog.ar.error("media audio session failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
