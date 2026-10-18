//
//  HapticPlayer.swift
//  HapticRemote Watch App
//
//  Plays a pattern step by step on the watch's Taptic Engine.
//

import Combine
import Foundation
import WatchKit

final class HapticPlayer: ObservableObject {
    /// Goes up by one every time a haptic fires. The view watches this to flash the screen.
    @Published var flashCount = 0

    /// The pattern that is playing right now (nil when idle).
    @Published var playing: Pattern?

    /// Seconds between Go straight taps, from the iPhone while navigating; nil
    /// for the pattern's own 1 second. Read at every tap, so a change speeds
    /// up the pattern that is playing without starting it over.
    var forwardInterval: TimeInterval?

    private var task: Task<Void, Never>?
    private var lastHapticAt = Date.distantPast

    /// Play a pattern. If another one is still playing, it is cancelled first.
    func play(_ pattern: Pattern) {
        task?.cancel()
        playing = pattern

        task = Task {
            do {
                // If the cancelled pattern fired a haptic a moment ago, wait a little
                // so watchOS doesn't drop our first one.
                let sinceLast = Date().timeIntervalSince(lastHapticAt)
                if sinceLast < Pattern.minimumGap {
                    try await Task.sleep(for: .seconds(Pattern.minimumGap - sinceLast))
                }

                let steps = pattern.steps
                // A normal pattern runs through its steps once.
                // A repeating pattern starts over until it is cancelled.
                repeat {
                    for (index, step) in steps.enumerated() {
                        WKInterfaceDevice.current().play(step.haptic.watchType)
                        lastHapticAt = Date()
                        flashCount += 1

                        // Wait before the next step, never less than the minimum gap.
                        // `Task.sleep` throws when the task is cancelled, which stops the loop.
                        let isLastStep = index == steps.count - 1
                        if !isLastStep || pattern.repeats {
                            var delay = step.delay
                            if pattern == .forward, isLastStep, let forwardInterval { delay = forwardInterval }
                            try await Task.sleep(for: .seconds(max(delay, Pattern.minimumGap)))
                        }
                    }
                } while pattern.repeats
                playing = nil
            } catch {
                // Cancelled by `stop()` or because a newer pattern arrived.
            }
        }
    }

    /// Stop whatever is playing.
    func stop() {
        task?.cancel()
        task = nil
        playing = nil
    }
}
