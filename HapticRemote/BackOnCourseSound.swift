//
//  BackOnCourseSound.swift
//  HapticRemote (iPhone)
//
//  The sound for turning back the right way: when the user faced away and
//  the blue dot comes back into the green Go straight arc, a short rising
//  chime (three notes, C E G, ringing into each other). Made here rather
//  than from a file, like the voice search chimes. It plays over music and
//  podcasts without stopping them, and with the silent switch on.
//

import AVFoundation

@MainActor
final class BackOnCourseSound {
    private let player: AVAudioPlayer?

    init() {
        player = try? AVAudioPlayer(data: Self.wav(Self.chime()))
        player?.prepareToPlay()
    }

    /// Guidance starts: the app's audio session, mixed with other apps'.
    func start() {
        Task {
            try? await AudioSessionQueue.run { session in
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            }
        }
    }

    func stop() {
        player?.stop()
        AudioSessionQueue.deactivate()
    }

    /// Played here, on the main thread, the moment it is asked for: through
    /// the audio session's queue it could wait behind a slow session call,
    /// and the chime has to come as the user turns. The session is already
    /// on by then (`start`), so playing doesn't switch it on.
    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private static let rate = 44_100.0

    /// C6, E6 and G6, 70 ms apart, each ringing out over about a third of a
    /// second, with a soft octave above for a bell-like ring.
    private static func chime() -> [Float] {
        let notes = [1046.5, 1318.5, 1568.0]
        let gap = 0.07
        let ring = 0.45
        var samples = [Float](repeating: 0, count: Int(rate * (gap * Double(notes.count - 1) + ring)))
        for (n, frequency) in notes.enumerated() {
            let start = Int(rate * gap * Double(n))
            for i in 0..<Int(rate * ring) {
                let t = Double(i) / rate
                // Quick start, gentle fade, so it rings rather than clicks.
                let envelope = min(1, t / 0.004) * exp(-t * 9)
                let tone = sin(2 * .pi * frequency * t) + 0.25 * sin(4 * .pi * frequency * t)
                samples[start + i] += Float(tone * envelope * 0.12)
            }
        }
        return samples
    }

    /// The samples as a 16-bit mono WAV file, for AVAudioPlayer.
    private static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))                  // PCM, mono
        append(UInt32(rate)); append(UInt32(rate * 2))        // sample rate, bytes a second
        append(UInt16(2)); append(UInt16(16))                 // bytes a frame, bits a sample
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }
}
