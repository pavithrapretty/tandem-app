//
//  Pattern.swift
//  Shared between the iPhone app and the Watch app
//
//  This is the single place where haptic patterns are defined.
//  To add a new pattern: add a `case` to `Pattern`, then fill in its
//  `title`, `symbol` and `steps` below. Both apps pick it up automatically.
//

import Foundation
import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// The haptics we use. These mirror the names of `WKHapticType` on the watch.
/// (`WKHapticType` itself only exists on watchOS, so the iPhone needs its own list.)
enum Haptic {
    case notification
    case click
    case directionUp
    case directionDown
    case success
    case failure
    case retry
    case start
    case stop
    // The haptics Apple Maps uses for turn-by-turn directions.
    case navigationLeftTurn
    case navigationRightTurn
    case navigationGenericManeuver
}

/// One step of a pattern: play a haptic, then wait before the next step.
struct PatternStep {
    let haptic: Haptic
    /// Seconds to wait after this haptic before playing the next one.
    let delay: TimeInterval
}

/// All available patterns. The raw value (e.g. "heartbeat") is what gets sent
/// from the iPhone to the watch.
enum Pattern: String, CaseIterable, Identifiable {
    case forward
    case left
    case right
    case turnAround
    /// Close to the destination: the forward beat, twice as fast.
    case almostThere
    case arrived
    // Only used in the tutorial for now.
    case signalLost

    var id: String { rawValue }

    /// watchOS drops haptics that are fired too close together,
    /// so no step is ever allowed to be shorter than this.
    static let minimumGap: TimeInterval = 0.25

    /// Name shown in the UI.
    var title: String {
        switch self {
        case .forward: "Forward"
        case .left: "Left"
        case .right: "Right"
        case .turnAround: "Turn around"
        case .almostThere: "Almost there"
        case .arrived: "Arrived"
        case .signalLost: "Signal lost"
        }
    }

    /// SF Symbol shown on the iPhone button.
    var symbol: String {
        switch self {
        case .forward: "arrow.up"
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .turnAround: "arrow.uturn.down"
        case .almostThere: "flag.fill"
        case .arrived: "checkmark"
        case .signalLost: "wifi.slash"
        }
    }

    /// Colour of the watch background while this pattern plays.
    var color: Color {
        switch self {
        case .forward: .green
        case .left: .blue
        case .right: .purple
        case .turnAround: .red
        case .almostThere: .green
        case .arrived: Palette.success
        case .signalLost: .gray
        }
    }

    /// A repeating pattern keeps looping until it is stopped or replaced.
    /// Every button works like a switch: on with the first press, off with the
    /// second. Return false for a pattern that should play only once.
    var repeats: Bool {
        true
    }

    /// The haptics to play, in order. For a repeating pattern, the delay of the
    /// last step is the pause before the pattern starts again.
    var steps: [PatternStep] {
        switch self {
        case .forward:
            // One short rising tap per second: "keep going".
            return [PatternStep(haptic: .directionUp, delay: 1.0)]

        // Left and right are designed for a watch worn on the LEFT wrist.
        // One watch can't make a vibration feel like it comes from a side,
        // so the side is in the rhythm instead:
        //   one unbroken signal  = "this side, where the watch is" = left
        //   two separate signals = "the other side"                = right

        case .left:
            // One steady run of four strong taps, close together.
            // (Apple's navigation presets would fit here, but they stayed
            // silent on the test watch, so this is built from a basic one.)
            return [
                PatternStep(haptic: .start, delay: 0.35),
                PatternStep(haptic: .start, delay: 0.35),
                PatternStep(haptic: .start, delay: 0.35),
                // Pause, so each run of four is felt as one group.
                PatternStep(haptic: .start, delay: 1.0),
            ]

        case .right:
            // Two strong taps with a long gap between them.
            return [
                PatternStep(haptic: .start, delay: 0.9),
                // The pause is clearly longer than the gap inside the pair,
                // otherwise it would blur into one even row of taps.
                PatternStep(haptic: .start, delay: 1.0),
            ]

        case .turnAround:
            // Wrong way: the strong "failure" haptic, twice, so it can't be
            // mistaken for the single short "forward" tap.
            return [
                PatternStep(haptic: .failure, delay: 1.0),
                PatternStep(haptic: .failure, delay: 1.0),
            ]

        case .almostThere:
            // The forward tap, twice as fast: "nearly there, keep going"
            // (the hot and cold game: faster means closer).
            return [PatternStep(haptic: .directionUp, delay: 0.5)]

        case .arrived:
            // Three taps getting stronger: "you made it".
            return [PatternStep(haptic: .success, delay: 2.0)]

        case .signalLost:
            // One short buzz every 10 seconds, until the signal is back.
            return [PatternStep(haptic: .retry, delay: 10.0)]
        }
    }
}

/// The keys of the dictionary we send over WatchConnectivity.
/// Example: ["pattern": "heartbeat", "id": "8F2C…", "sentAt": 1791878400.0]
/// (`nonisolated` = may be used from any thread, not only the main one.)
nonisolated enum MessageKey {
    static let pattern = "pattern"
    static let id = "id"
    static let sentAt = "sentAt"
    /// Seconds between Go straight taps, sent while navigating: they come
    /// faster as a turn gets close. Sent with a pattern, or on its own to
    /// change the speed of the Go straight that is playing.
    static let interval = "interval"

    /// Sent in place of a pattern name to stop whatever is playing.
    static let stopCommand = "stop"
}

#if os(watchOS)
extension Haptic {
    /// The real watchOS haptic for this step.
    var watchType: WKHapticType {
        switch self {
        case .notification: .notification
        case .click: .click
        case .directionUp: .directionUp
        case .directionDown: .directionDown
        case .success: .success
        case .failure: .failure
        case .retry: .retry
        case .start: .start
        case .stop: .stop
        case .navigationLeftTurn: .navigationLeftTurn
        case .navigationRightTurn: .navigationRightTurn
        case .navigationGenericManeuver: .navigationGenericManeuver
        }
    }
}
#endif
