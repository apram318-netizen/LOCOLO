//
//  SpeechTriggerService.swift
//  Locolo
//
//  Listens for spoken trigger phrases during an AR session using
//  SFSpeechRecognizer. Started lazily — only when a placed asset actually
//  has a speech trigger — and restarts its recognition task periodically
//  because Apple caps continuous recognition at roughly one minute.
//

import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechTriggerService {

    /// phrase (lowercased) → callback when heard
    private var phrases: [String: () -> Void] = [:]

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var lastFired: [String: Date] = [:]
    private(set) var isListening = false

    // MARK: Register a phrase
    func listen(for phrase: String, onHear: @escaping () -> Void) {
        let normalized = phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        phrases[normalized] = onHear
        startIfNeeded()
    }

    // MARK: Start listening (requests permissions lazily)
    private func startIfNeeded() {
        guard !isListening, !phrases.isEmpty else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                print(" Speech recognition not authorized")
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                guard granted else {
                    print(" Microphone permission denied")
                    return
                }
                Task { @MainActor in
                    self?.startEngine()
                }
            }
        }
    }

    private func startEngine() {
        guard !isListening else { return }

        do {
            // Mix with others so we don't fight the AR session's audio
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            recognizer = SFSpeechRecognizer()
            startRecognitionTask()

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            // Apple limits continuous recognition to ~1 minute; cycle the task
            restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.startRecognitionTask()
                }
            }
        } catch {
            print(" Speech engine failed to start:", error.localizedDescription)
            stop()
        }
    }

    private func startRecognitionTask() {
        task?.cancel()
        task = nil

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            newRequest.requiresOnDeviceRecognition = true
        }
        request = newRequest

        task = recognizer?.recognitionTask(with: newRequest) { [weak self] result, _ in
            guard let self, let result else { return }
            let heard = result.bestTranscription.formattedString.lowercased()
            Task { @MainActor in
                self.match(heard)
            }
        }
    }

    private func match(_ heard: String) {
        for (phrase, fire) in phrases where heard.contains(phrase) {
            // Per-phrase cooldown so one utterance doesn't machine-gun the animation
            if let last = lastFired[phrase], Date().timeIntervalSince(last) < 5 { continue }
            lastFired[phrase] = Date()
            fire()
        }
    }

    // MARK: Stop and release the mic
    func stop() {
        restartTimer?.invalidate()
        restartTimer = nil
        task?.cancel()
        task = nil
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        phrases.removeAll()
        lastFired.removeAll()
        isListening = false
    }

    /// First registered phrase, for the "Listening for…" banner.
    var listeningHint: String? {
        phrases.keys.sorted().first
    }
}
