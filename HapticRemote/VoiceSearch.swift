//
//  VoiceSearch.swift
//  HapticRemote (iPhone)
//
//  The parts of the voice search in SearchView ("06 Search · Listening" in
//  Figma): the speech recognition (SpeechListener), the microphone in its
//  circles, which move with the voice, and the lookup
//  of what was said (PlaceLookup).
//

import AVFoundation
import Combine
import CoreLocation
import MapKit
import Speech
import SwiftUI

/// Finds a place for what the user said, near them first.
enum PlaceLookup {
    static func find(_ words: String) async -> Destination? {
        let center = CLLocationManager().location?.coordinate
            ?? CLLocationCoordinate2D(latitude: 52.3731, longitude: 4.8926)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = words
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        request.resultTypes = [.pointOfInterest, .address]
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let name = item.name ?? words
        let address = item.placemark.title ?? ""
        return Destination(name: name, subtitle: address == name ? "" : address,
                           coordinate: item.placemark.coordinate,
                           isStop: item.pointOfInterestCategory == .publicTransport)
    }
}

// MARK: - Circles

/// The microphone in its circles ("Listening" in Figma). The rings swell
/// with the loudness of the voice, like the navigation dial's rings with
/// each vibration: out fast, back slowly (SpeechListener smooths the level).
/// With Reduce Motion they stay put and only the halo brightens.
struct ListeningCircles: View {
    /// Loudness, 0 to 1.
    var level: Double
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            // Halo
            Circle()
                .fill(Palette.accent.opacity(0.1 + 0.25 * level))
                .frame(width: 220, height: 220)
                .scaleEffect(swell(0.22))
            Circle()
                .stroke(Palette.accent.opacity(0.4 + 0.6 * level), lineWidth: 2 + 2 * level)
                .frame(width: 168, height: 168)
                .scaleEffect(swell(0.32))
            Circle()
                .fill(Palette.accent)
                .frame(width: 120, height: 120)
                .scaleEffect(swell(0.1))
            Image("icon-mic-dark")
                .accessibilityHidden(true)
        }
        .frame(width: 220, height: 220)
        .animation(.easeOut(duration: 0.1), value: level)
    }

    /// 1 when quiet, up to `1 + amount` at full loudness.
    private func swell(_ amount: Double) -> CGFloat {
        reduceMotion ? 1 : 1 + amount * level
    }
}

// MARK: - Speech

/// Listens to the microphone and turns speech into text with Apple's speech
/// recognition. Calls `onFinish` once the user has been quiet for a moment.
///
/// Without looking at the screen: a rising two-note chime says the
/// microphone is listening, a soft tap on every burst of speech says it hears
/// the voice, and a falling chime says it has stopped. The chimes play
/// through the app's own audio, so they are heard on silent mode too.
@MainActor
final class SpeechListener: ObservableObject {
    struct Failure: Equatable {
        let title: String
        let detail: String
    }

    @Published private(set) var transcript = ""
    /// Loudness of the microphone, 0 to 1, smoothed, for the circles.
    @Published private(set) var level: Double = 0
    @Published private(set) var isRunning = false
    @Published private(set) var failure: Failure?

    /// What was said, once the user stops talking. Empty if nothing was heard.
    var onFinish: ((String) -> Void)?

    /// Quiet this long after speaking: done.
    private let pauseAfterSpeech: Duration = .milliseconds(1500)
    /// Nothing said for this long: give up.
    private let waitForSpeech: Duration = .seconds(8)

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    /// From `start()` until the microphone is on: asking permission, the tone.
    private var startTask: Task<Void, Never>?

    /// Plays the chimes, on the same engine as the microphone.
    private let chimePlayer = AVAudioPlayerNode()
    private static let chimeFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    /// Listening: up from A5 to E6. Done: back down.
    private static let listeningChime = chime([880, 1318.5])
    private static let doneChime = chime([1318.5, 880])

    /// A soft tap for each burst of speech.
    private let speechTap = UIImpactFeedbackGenerator(style: .soft)
    /// A tap needs the voice to get this loud (0 to 1, see `loudness(of:)`),
    /// and to drop below `quietLevel` before the next one, so one word is one
    /// tap instead of a buzz.
    private let loudLevel = 0.55
    private let quietLevel = 0.35
    private let minimumTapGap: TimeInterval = 0.12
    private var tapArmed = true
    private var lastTap = Date.distantPast

    func start() {
        stop()
        transcript = ""
        failure = nil
        startTask = Task {
            guard await Self.askPermission() else {
                failure = Failure(title: "Microphone is off",
                                  detail: "Turn on Microphone and Speech Recognition for Tandem in Settings, or type instead")
                return
            }
            guard let recognizer, recognizer.isAvailable else {
                failure = Failure(title: "Voice search isn't available",
                                  detail: "Check the internet connection, or type instead")
                return
            }
            do {
                try await startAudio()
                // The chime first, and only then the microphone, so it isn't heard as speech.
                await play(Self.listeningChime)
                guard !Task.isCancelled else { return }
                try begin(with: recognizer)
            } catch {
                stop()
                failure = Failure(title: "Couldn't start listening", detail: "Try again, or type instead")
            }
        }
    }

    /// The user says they are done: finish with what was heard.
    func finishNow() {
        guard isRunning else { return }
        let words = transcript
        stopListening()
        onFinish?(words)
        // The microphone is off already; the audio stays on for the chime.
        let finishing = Task { [weak self] in
            guard let self else { return }
            await self.play(Self.doneChime)
            guard !Task.isCancelled else { return }
            self.stopAudio()
        }
        startTask = finishing
    }

    /// Stops listening and all sound, at once and without a chime.
    func stop() {
        startTask?.cancel()
        startTask = nil
        stopListening()
        stopAudio()
    }

    /// The microphone and the recognition; the audio engine keeps running.
    private func stopListening() {
        silenceTimer?.cancel()
        silenceTimer = nil
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        level = 0
        isRunning = false
    }

    private var hasTap = false
    private var audioIsOn = false

    /// The audio session and engine, for both the microphone and the chimes:
    /// play and record, out of the loudspeaker (not the earpiece), and not
    /// muted by the silent switch. With AirPods (or another headset) in:
    /// their microphone and the chimes in them, not the iPhone's.
    private func startAudio() async throws {
        // On before the wait: a `stop()` meanwhile switches it off again.
        audioIsOn = true
        let hasMicrophone = try await AudioSessionQueue.run { session in
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
            // iOS silences vibrations while recording; the speech taps need them.
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            return session.isInputAvailable
        }
        try Task.checkCancellation()
        guard hasMicrophone else { throw CocoaError(.featureUnsupported) }

        if chimePlayer.engine == nil {
            engine.attach(chimePlayer)
            engine.connect(chimePlayer, to: engine.mainMixerNode, format: Self.chimeFormat)
        }
        // Touch the microphone before the engine starts, so it is part of it.
        _ = engine.inputNode
        // Starting switches the session on too: off the main thread, after
        // the session calls above.
        nonisolated(unsafe) let engine = engine
        try await AudioSessionQueue.run { _ in
            engine.prepare()
            try engine.start()
        }
    }

    private func stopAudio() {
        chimePlayer.stop()
        if engine.isRunning { engine.stop() }
        if audioIsOn {
            audioIsOn = false
            AudioSessionQueue.deactivate()
        }
    }

    /// Plays a chime and returns once it has been heard.
    private func play(_ chime: AVAudioPCMBuffer) async {
        guard engine.isRunning else { return }
        chimePlayer.play()
        await chimePlayer.scheduleBuffer(chime, completionCallbackType: .dataPlayedBack)
    }

    /// Two short soft notes, one after the other.
    private static func chime(_ notes: [Double]) -> AVAudioPCMBuffer {
        let rate = chimeFormat.sampleRate
        let noteLength = Int(rate * 0.11)
        let buffer = AVAudioPCMBuffer(pcmFormat: chimeFormat,
                                      frameCapacity: AVAudioFrameCount(noteLength * notes.count))!
        buffer.frameLength = buffer.frameCapacity
        let samples = buffer.floatChannelData![0]
        for (n, frequency) in notes.enumerated() {
            for i in 0..<noteLength {
                let t = Double(i) / rate
                // Quick start, gentle fade, so it rings rather than clicks.
                let envelope = min(1, t / 0.005) * exp(-t * 18)
                samples[n * noteLength + i] = Float(sin(2 * .pi * frequency * t) * envelope * 0.2)
            }
        }
        return buffer
    }

    private func begin(with recognizer: SFSpeechRecognizer) throws {
        speechTap.prepare()
        tapArmed = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        hasTap = true
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let loudness = Self.loudness(of: buffer)
            Task { @MainActor in
                guard let self else { return }
                // Up at once, down slowly: the rings swell on a word and settle after it.
                self.level = loudness > self.level ? loudness : self.level * 0.8 + loudness * 0.2
                self.tapForSpeech(loudness)
            }
        }
        isRunning = true
        waitForSilence(waitForSpeech)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.waitForSilence(self.pauseAfterSpeech)
                }
                if isFinal || failed { self.finishNow() }
            }
        }
    }

    /// A tap as the voice gets loud, as strong as it is loud.
    private func tapForSpeech(_ loudness: Double) {
        guard isRunning else { return }
        if loudness < quietLevel {
            tapArmed = true
        } else if tapArmed, loudness >= loudLevel, Date().timeIntervalSince(lastTap) >= minimumTapGap {
            tapArmed = false
            lastTap = Date()
            speechTap.impactOccurred(intensity: 0.5 + 0.5 * loudness)
            speechTap.prepare()
        }
    }

    /// Finishes once nothing new has been heard for `duration`.
    private func waitForSilence(_ duration: Duration) {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.finishNow()
        }
    }

    private static func askPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Roughly how loud a buffer is, 0 to 1 (about -55 dB to -20 dB), so
    /// normal speech at arm's length already reaches most of the range.
    nonisolated private static func loudness(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        let linear = Double(min(1, max(0, (decibels + 55) / 35)))
        // Lifts the quieter part, so soft words still move the circles.
        return linear.squareRoot()
    }
}
