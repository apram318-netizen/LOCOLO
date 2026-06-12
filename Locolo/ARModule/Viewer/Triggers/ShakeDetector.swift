//
//  ShakeDetector.swift
//  Locolo
//
//  Detects the preset shake patterns (single shake, double shake, tilt)
//  with CoreMotion during an AR session. Started only when a placed asset
//  has a shake trigger.
//

import Foundation
import CoreMotion

@MainActor
final class ShakeDetector {

    private let motion = CMMotionManager()
    private var onPattern: ((ShakePattern) -> Void)?

    // Shake state
    private var lastShakeEvent: Date?
    private var previousShakeEvent: Date?
    private var inShake = false

    // Tilt state
    private var referenceRoll: Double?
    private var referencePitch: Double?
    private var referenceTime: Date?

    private var lastFired: [ShakePattern: Date] = [:]

    // MARK: Start
    func start(onPattern: @escaping (ShakePattern) -> Void) {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else {
            self.onPattern = onPattern
            return
        }
        self.onPattern = onPattern

        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.process(data)
        }
    }

    private func process(_ data: CMDeviceMotion) {
        let now = Date()

        // MARK: Shake events (acceleration spike followed by calm)
        let a = data.userAcceleration
        let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()

        if magnitude > 2.0 {
            if !inShake {
                inShake = true
                if let last = lastShakeEvent, now.timeIntervalSince(last) < 1.0 {
                    // Two distinct shakes inside one second
                    previousShakeEvent = last
                    fire(.double)
                }
                lastShakeEvent = now
            }
        } else if magnitude < 0.5, inShake {
            inShake = false
            // A lone shake counts as "single" once no second one follows
            let eventTime = lastShakeEvent
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                if self.lastShakeEvent == eventTime, self.previousShakeEvent != eventTime {
                    self.fire(.single)
                }
            }
        }

        // MARK: Tilt (large attitude change inside half a second)
        let roll = data.attitude.roll
        let pitch = data.attitude.pitch

        if let refRoll = referenceRoll, let refPitch = referencePitch,
           let refTime = referenceTime, now.timeIntervalSince(refTime) <= 0.5 {
            let deltaRoll = abs(roll - refRoll)
            let deltaPitch = abs(pitch - refPitch)
            if deltaRoll > .pi / 3 || deltaPitch > .pi / 3 {
                fire(.tilt)
                referenceRoll = nil
                referencePitch = nil
                referenceTime = nil
            }
        } else {
            referenceRoll = roll
            referencePitch = pitch
            referenceTime = now
        }
    }

    private func fire(_ pattern: ShakePattern) {
        if let last = lastFired[pattern], Date().timeIntervalSince(last) < 3 { return }
        lastFired[pattern] = Date()
        onPattern?(pattern)
    }

    // MARK: Stop
    func stop() {
        motion.stopDeviceMotionUpdates()
        onPattern = nil
        lastShakeEvent = nil
        previousShakeEvent = nil
        inShake = false
        referenceRoll = nil
        referencePitch = nil
        referenceTime = nil
        lastFired.removeAll()
    }
}
