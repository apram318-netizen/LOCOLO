//
//  ARClipRecorder.swift
//  Locolo
//
//  Short AR screen clips via ReplayKit → MP4 Data for Story/share.
//  Simulator: unavailable (returns nil).
//

import Foundation
import ReplayKit
import AVFoundation
import UIKit

@MainActor
final class ARClipRecorder: NSObject {
    static let shared = ARClipRecorder()

    private(set) var isRecording = false
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var startedAt: Date?
    private var outputURL: URL?
    private var finishContinuation: CheckedContinuation<Data?, Never>?

    private override init() { super.init() }

    var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return RPScreenRecorder.shared().isAvailable
        #endif
    }

    /// Record ~`seconds` of the AR screen. Returns MP4 bytes or nil.
    func recordClip(seconds: TimeInterval = 5) async -> Data? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard !isRecording, isAvailable else { return nil }
        isRecording = true
        defer { isRecording = false }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("locolo-ar-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)
        outputURL = url

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 720,
            AVVideoHeightKey: 1280
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        self.writer = writer
        self.videoInput = input
        writer.startWriting()
        startedAt = nil

        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            finishContinuation = cont
            RPScreenRecorder.shared().startCapture { [weak self] sample, bufferType, error in
                guard error == nil, bufferType == .video, let self else { return }
                Task { @MainActor in
                    self.append(sample)
                }
            } completionHandler: { [weak self] error in
                if error != nil {
                    Task { @MainActor in self?.fail() }
                }
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await self.stopAndFinish()
            }
        }
        #endif
    }

    #if !targetEnvironment(simulator)
    private func append(_ sample: CMSampleBuffer) {
        guard let writer, let input = videoInput, writer.status == .writing else { return }
        if startedAt == nil {
            let t = CMSampleBufferGetPresentationTimeStamp(sample)
            writer.startSession(atSourceTime: t)
            startedAt = Date()
        }
        if input.isReadyForMoreMediaData {
            input.append(sample)
        }
    }

    private func fail() {
        RPScreenRecorder.shared().stopCapture { _ in }
        writer?.cancelWriting()
        writer = nil
        videoInput = nil
        finishContinuation?.resume(returning: nil)
        finishContinuation = nil
    }

    private func stopAndFinish() async {
        RPScreenRecorder.shared().stopCapture { _ in }
        videoInput?.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer?.finishWriting { c.resume() }
        }
        let data = outputURL.flatMap { try? Data(contentsOf: $0) }
        writer = nil
        videoInput = nil
        finishContinuation?.resume(returning: data)
        finishContinuation = nil
    }
    #endif
}
