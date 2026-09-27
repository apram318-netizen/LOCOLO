//
//  HandTracker.swift
//  Locolo
//
//  Wraps Vision's hand-pose request to track the index fingertip and detect a
//  thumb–index pinch from AR camera frames (WS7). iOS has no world-space hand
//  skeleton (that's visionOS), so we detect the pinch in 2D and the draw view
//  projects it to a fixed depth in front of the camera.
//

import Foundation
import Vision
import CoreGraphics

final class HandTracker {
    /// Pinch hysteresis (normalized image distance between index & thumb tips).
    private let pinchOnThreshold: CGFloat = 0.04
    private let pinchOffThreshold: CGFloat = 0.06
    private let minConfidence: Float = 0.3

    private(set) var isPinching = false

    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()

    struct Result {
        /// Index fingertip in Vision normalized coords (origin bottom-left).
        let indexTip: CGPoint
        let isPinching: Bool
        /// True on the frame the pinch started, false on the frame it ended.
        let pinchChanged: Bool
    }

    /// Run detection on a camera pixel buffer. Returns nil if no confident hand.
    func process(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .right) -> Result? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let hand = request.results?.first else { return nil }
        guard
            let index = try? hand.recognizedPoint(.indexTip),
            let thumb = try? hand.recognizedPoint(.thumbTip),
            index.confidence > minConfidence, thumb.confidence > minConfidence
        else { return nil }

        let dist = hypot(index.location.x - thumb.location.x,
                         index.location.y - thumb.location.y)

        let wasPinching = isPinching
        if isPinching {
            if dist > pinchOffThreshold { isPinching = false }
        } else {
            if dist < pinchOnThreshold { isPinching = true }
        }

        return Result(indexTip: index.location,
                      isPinching: isPinching,
                      pinchChanged: wasPinching != isPinching)
    }

    func reset() { isPinching = false }
}
