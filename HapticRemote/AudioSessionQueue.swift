//
//  AudioSessionQueue.swift
//  HapticRemote (iPhone)
//
//  The audio session's calls wait on the audio hardware, and can hang the
//  screen on the main thread (Xcode's "AVAudioSession Hang Risk"). So they
//  are made here, on a queue of their own: one after another, so switching
//  off and back on happen in the order they were asked for.
//

import AVFoundation

nonisolated enum AudioSessionQueue {
    private static let queue = DispatchQueue(label: "Tandem.audioSession")

    /// Runs `work` on the queue and waits for it.
    @discardableResult
    static func run<T: Sendable>(_ work: @escaping @Sendable (AVAudioSession) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work(.sharedInstance()) })
            }
        }
    }

    /// Switches the session off, letting other apps' audio back up. Doesn't
    /// wait: a later `run` still comes after it.
    static func deactivate() {
        queue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
