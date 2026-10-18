//
//  PhoneHapticPlayer.swift
//  HapticRemote (iPhone)
//
//  Plays the same patterns on the iPhone's own Taptic Engine, with Apple's
//  CoreHaptics.
//
//  The watch has ready-made haptics (WKHapticType). The iPhone doesn't have
//  those, so each one is rebuilt here from single taps. They are imitations:
//  tune the numbers in `phoneTaps` below until they feel right in your hand.
//  Two patterns use a preset from the Pulsar haptics library instead
//  (https://docs.swmansion.com/pulsar/), copied in below as plain data.
//
//  Robustness: one haptic engine for the whole player, without an audio
//  session (so speech or music can't stop it), restarted whenever iOS stops
//  it. The button or dial only blinks when the vibration really started, so
//  a blink never shows without a vibration.
//

import Combine
import CoreHaptics
import Foundation
import SwiftUI
import UIKit

/// One tap on the iPhone's Taptic Engine.
struct PhoneTap {
    /// When the tap happens, in seconds after the haptic starts.
    let time: TimeInterval
    /// How strong it is: 0 (nothing) to 1 (full).
    let intensity: Float
    /// How it feels: 0 (soft, round thud) to 1 (crisp, sharp tick).
    let sharpness: Float
    /// 0 for a single tap. Anything higher makes a buzz of that many seconds.
    var duration: TimeInterval = 0
}

extension Haptic {
    /// The iPhone version of each watch haptic.
    var phoneTaps: [PhoneTap] {
        switch self {
        case .click:
            // One light, crisp tick.
            [PhoneTap(time: 0, intensity: 0.5, sharpness: 0.9)]

        case .notification:
            // Two firm taps.
            [PhoneTap(time: 0, intensity: 1.0, sharpness: 0.5),
             PhoneTap(time: 0.15, intensity: 1.0, sharpness: 0.5)]

        case .directionUp:
            // Soft, then strong: feels like it rises.
            [PhoneTap(time: 0, intensity: 0.5, sharpness: 0.3),
             PhoneTap(time: 0.12, intensity: 1.0, sharpness: 0.7)]

        case .directionDown:
            // Strong, then soft: feels like it falls.
            [PhoneTap(time: 0, intensity: 1.0, sharpness: 0.7),
             PhoneTap(time: 0.12, intensity: 0.5, sharpness: 0.3)]

        case .success:
            // Three taps getting stronger.
            [PhoneTap(time: 0, intensity: 0.5, sharpness: 0.5),
             PhoneTap(time: 0.1, intensity: 0.7, sharpness: 0.6),
             PhoneTap(time: 0.2, intensity: 1.0, sharpness: 0.8)]

        case .failure:
            // A heavy buzz followed by a hard tap.
            [PhoneTap(time: 0, intensity: 1.0, sharpness: 0.2, duration: 0.35),
             PhoneTap(time: 0.45, intensity: 1.0, sharpness: 0.4)]

        case .retry:
            // A short buzz.
            [PhoneTap(time: 0, intensity: 0.7, sharpness: 0.4, duration: 0.2)]

        case .start:
            // One strong tap.
            [PhoneTap(time: 0, intensity: 1.0, sharpness: 0.6)]

        case .stop:
            // Two strong taps.
            [PhoneTap(time: 0, intensity: 1.0, sharpness: 0.6),
             PhoneTap(time: 0.2, intensity: 1.0, sharpness: 0.6)]

        case .navigationLeftTurn:
            // Three pairs of taps.
            [0, 0.5, 1.0].flatMap { pairStart in
                [PhoneTap(time: pairStart, intensity: 1.0, sharpness: 0.6),
                 PhoneTap(time: pairStart + 0.12, intensity: 1.0, sharpness: 0.6)]
            }

        case .navigationRightTurn:
            // A steady run of twelve taps.
            (0..<12).map { index in
                PhoneTap(time: Double(index) * 0.1, intensity: 1.0, sharpness: 0.6)
            }

        case .navigationGenericManeuver:
            // Three evenly spaced taps.
            [PhoneTap(time: 0, intensity: 0.8, sharpness: 0.5),
             PhoneTap(time: 0.2, intensity: 0.8, sharpness: 0.5),
             PhoneTap(time: 0.4, intensity: 0.8, sharpness: 0.5)]
        }
    }
}

/// How far the dial's rings have swelled outwards, and how they get there.
/// Used for a preset whose feel isn't a row of taps, such as Coil's slow
/// wind-up: the rings then follow the vibration itself instead of the blinks.
struct RingSwell {
    /// 0 = at rest, 1 = as far out as a full-strength tap.
    let level: Double
    let animation: Animation
}

/// A ready-made haptic from the Pulsar library, copied in as data. Times are
/// in milliseconds, like on the preset's page in the Pulsar playground.
struct PhonePreset {
    /// Single taps: time, strength (0–1), sharpness (0–1).
    var taps: [(time: Double, intensity: Float, sharpness: Float)] = []
    /// A buzz drawn as two lines: strength over time and sharpness over time.
    /// Empty for a preset made of taps only.
    var buzzStrength: [(time: Double, value: Float)] = []
    var buzzSharpness: [(time: Double, value: Float)] = []
    /// How the dial's rings move along, in milliseconds like the rest.
    /// Empty = the rings swell with every blink, as for single taps.
    var rings: [(time: Double, swell: RingSwell)] = []

    /// "Anvil": a heavy thud with a short ring, about half a second long.
    static let anvil = PhonePreset(
        taps: [(0, 1.0, 0.15), (80, 0.5, 0.2)],
        buzzStrength: [(0, 0.0), (5, 1.0), (60, 0.6), (150, 0.3), (300, 0.1), (500, 0.0)],
        buzzSharpness: [(0, 0.12), (5, 0.1), (500, 0.08)])

    /// "Barrage": a rapid burst of seven hard, sharp taps, about a third of a second long.
    static let barrage = PhonePreset(
        taps: [(1, 0.994, 0.994), (51, 0.994, 0.994), (100, 0.991, 0.991), (156, 1.0, 1.0),
               (208, 0.991, 0.991), (260, 1.0, 1.0), (309, 1.0, 1.0)])

    /// "Coil": a buzz that slowly winds up, then snaps into one hard tap,
    /// about two thirds of a second long.
    static let coil = PhonePreset(
        taps: [(0, 0.2, 0.4), (600, 1.0, 0.7)],
        buzzStrength: [(0, 0.0), (50, 0.15), (200, 0.2), (400, 0.3), (570, 0.4), (590, 0.0),
                       (600, 1.0), (650, 0.0)],
        buzzSharpness: [(0, 0.3), (570, 0.5), (600, 0.8), (650, 0.8)],
        // The rings creep outwards while the buzz builds, snap fully out on
        // the hard tap, and settle back once it is over.
        rings: [(0, RingSwell(level: 0.4, animation: .easeIn(duration: 0.57))),
                (600, RingSwell(level: 1, animation: .easeOut(duration: 0.08))),
                (650, RingSwell(level: 0, animation: .easeOut(duration: 0.4)))])
}

/// How strong the phone vibrates, on top of the numbers above.
enum PhoneStrength {
    /// Every strength is multiplied by this (and capped at full). Raise it for
    /// stronger vibrations; 1 plays the numbers exactly as written.
    static let boost: Float = 1.4
    /// A single tap on its own lasts only a few milliseconds. This much
    /// buzz (seconds) under every tap gives it more body, so it is felt
    /// clearly through a pocket or a loose grip. 0 = plain taps.
    static let tapBody: TimeInterval = 0.04

    static func boosted(_ intensity: Float) -> Float { min(1, intensity * boost) }
}

extension Pattern {
    /// A preset to play on the phone instead of the hand-built taps, or nil to
    /// use the taps. Try presets out at
    /// https://docs.swmansion.com/pulsar/presets-playground/ and copy their
    /// numbers into `PhonePreset`. The rhythm still comes from `steps`: the
    /// preset is played once for every step, in place of that step's haptic.
    var phonePreset: PhonePreset? {
        switch self {
        case .forward, .almostThere: .anvil
        case .turnAround: .barrage
        case .left: .coil
        default: nil
        }
    }

    /// The steps the phone plays. Usually the same as the watch, but Coil is
    /// one long signal on its own, so Left plays it once per run (instead of
    /// once for each of the watch's four taps), followed by 1 second of quiet.
    var phoneSteps: [PatternStep] {
        switch self {
        case .left:
            [PatternStep(haptic: .start, delay: 0.65 + 1.0)]
        case .turnAround:
            // Barrage lasts about 0.3 seconds: 1 second of quiet after the second one.
            [PatternStep(haptic: .failure, delay: 1.0),
             PatternStep(haptic: .failure, delay: 0.31 + 1.0)]
        default:
            steps
        }
    }

    /// One run of the pattern, laid out on a single timeline (in seconds):
    /// the haptic events, the moments a light should blink (one for every tap
    /// or buzz you feel), how the dial's rings move (empty = with the blinks),
    /// and how long the run lasts including the pause at the end, which is
    /// when a repeating pattern starts over.
    var phoneTimeline: (events: [CHHapticEvent], curves: [CHHapticParameterCurve],
                        blinks: [TimeInterval], rings: [(time: TimeInterval, swell: RingSwell)],
                        end: TimeInterval, length: TimeInterval) {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        var blinks: [TimeInterval] = []
        var rings: [(time: TimeInterval, swell: RingSwell)] = []
        var end: TimeInterval = 0

        func tap(at time: TimeInterval, intensity: Float, sharpness: Float, duration: TimeInterval = 0) {
            let intensity = PhoneStrength.boosted(intensity)
            let parameters = [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                              CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)]
            if duration > 0 {
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: parameters,
                                            relativeTime: time, duration: duration))
            } else {
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: parameters,
                                            relativeTime: time))
                if PhoneStrength.tapBody > 0 {
                    // A short, rounder buzz under the tap: same strength, a bit softer.
                    events.append(CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                     CHHapticEventParameter(parameterID: .hapticSharpness,
                                                            value: sharpness * 0.6)],
                        relativeTime: time, duration: PhoneStrength.tapBody))
                }
            }
            blinks.append(time)
            end = max(end, time + max(duration, PhoneStrength.tapBody))
        }

        var stepStart: TimeInterval = 0
        for step in phoneSteps {
            if let preset = phonePreset {
                for t in preset.taps {
                    tap(at: stepStart + t.time / 1000, intensity: t.intensity, sharpness: t.sharpness)
                }
                rings += preset.rings.map { (stepStart + $0.time / 1000, $0.swell) }
                if let last = preset.buzzStrength.last {
                    // A full-strength buzz, shaped by the two lines. (CoreHaptics
                    // multiplies the strength by the line, and adds the
                    // sharpness line to a sharpness of 0.)
                    let duration = last.time / 1000
                    events.append(CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                                     CHHapticEventParameter(parameterID: .hapticSharpness, value: 0)],
                        relativeTime: stepStart, duration: duration))
                    curves.append(CHHapticParameterCurve(
                        parameterID: .hapticIntensityControl,
                        controlPoints: preset.buzzStrength.map {
                            .init(relativeTime: $0.time / 1000, value: PhoneStrength.boosted($0.value))
                        },
                        relativeTime: stepStart))
                    curves.append(CHHapticParameterCurve(
                        parameterID: .hapticSharpnessControl,
                        controlPoints: preset.buzzSharpness.map {
                            .init(relativeTime: $0.time / 1000, value: $0.value)
                        },
                        relativeTime: stepStart))
                    end = max(end, stepStart + duration)
                }
            } else {
                for t in step.haptic.phoneTaps {
                    tap(at: stepStart + t.time, intensity: t.intensity, sharpness: t.sharpness,
                        duration: t.duration)
                }
            }
            stepStart += max(step.delay, Pattern.minimumGap)
        }
        return (events, curves, blinks.sorted(), rings.sorted { $0.time < $1.time }, end, stepStart)
    }

    /// Roughly how long the pattern takes to play, in seconds.
    /// The phone uses this to know how long to keep a button lit.
    var playbackDuration: TimeInterval {
        // A little extra so the button doesn't go dim before the last tap is felt.
        phoneTimeline.end + 0.3
    }
}

final class PhoneHapticPlayer: ObservableObject {
    /// True for a short moment every time a haptic of the pattern fires.
    /// The view watches this to blink the button.
    @Published var isLit = false

    /// How the dial's rings move right now, for a preset that moves them its
    /// own way (Coil). Nil = the rings swell with `isLit`.
    @Published var ringSwell: RingSwell?

    /// How long the button stays lit after one haptic, in seconds. Taps that
    /// follow each other faster than this show as one longer blink, so a rapid
    /// burst never turns the button into a strobe light.
    private let blinkDuration: TimeInterval = 0.1

    /// Switches the light off again when the blink is over.
    private var blinkTask: Task<Void, Never>?

    /// Off = keep counting the beats (so the button still blinks along with
    /// the watch) but leave the phone's Taptic Engine silent.
    /// Seconds between Go straight taps while navigating; nil for the normal
    /// 1 second. Read at every tap, so changing it speeds up or slows down
    /// the pattern that is playing, without starting it over.
    var forwardInterval: TimeInterval?

    var vibrates = true {
        didSet {
            if !vibrates {
                stopPlayer()
            }
        }
    }

    private var engine: CHHapticEngine?
    /// True when iOS stopped the engine (app in the background, an error...)
    /// and it has to be started again before the next vibration.
    private var engineNeedsStart = true

    /// The run of the pattern that is vibrating right now.
    private var player: CHHapticPatternPlayer?

    /// Plays the pattern, again and again for a repeating one, until `stop()`.
    private var loopTask: Task<Void, Never>?

    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    init() {
        // iOS stops the haptic engine while the app is in the background.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineNeedsStart = true }
        }
    }

    /// Play a pattern. If another one is still playing, it is stopped first.
    /// `once` plays a repeating pattern a single time (the tutorial does this).
    /// (On an iPad or the simulator there is no Taptic Engine: the button still
    /// blinks, nothing vibrates.)
    func play(_ pattern: Pattern, vibrate: Bool, once: Bool = false) {
        stop()
        vibrates = vibrate
        let repeats = pattern.repeats && !once
        let timeline = pattern.phoneTimeline
        let hapticPattern = try? CHHapticPattern(events: timeline.events,
                                                 parameterCurves: timeline.curves)

        loopTask = Task {
            let clock = ContinuousClock()
            // Counting from the planned start (not from "now") keeps the
            // rhythm steady over many repeats.
            var runStart = clock.now
            do {
                repeat {
                    // Blink along only if the vibration really started (or if
                    // the phone is meant to stay silent, or can't vibrate).
                    let started = !vibrates || !supportsHaptics || startRun(of: hapticPattern)
                    if started {
                        // Blinks and ring moves, in the order they happen.
                        let cues = timeline.blinks.map { (time: $0, swell: RingSwell?.none) }
                            + timeline.rings.map { (time: $0.time, swell: Optional($0.swell)) }
                        for cue in cues.sorted(by: { $0.time < $1.time }) {
                            try await clock.sleep(until: runStart + .seconds(cue.time))
                            if let swell = cue.swell {
                                ringSwell = swell
                            } else {
                                blink()
                            }
                        }
                    }

                    let gap = pattern == .forward ? forwardInterval ?? timeline.length : timeline.length
                    runStart += .seconds(gap)
                    if repeats {
                        try await clock.sleep(until: runStart)
                    }
                } while repeats
            } catch {
                // Cancelled by `stop()` or because a newer pattern was started.
            }
        }
    }

    /// Light the button up now, and switch it off again a moment later.
    private func blink() {
        isLit = true
        // A new blink while the light is still on just keeps it on for longer.
        blinkTask?.cancel()
        blinkTask = Task {
            try? await Task.sleep(for: .seconds(blinkDuration))
            if !Task.isCancelled {
                isLit = false
            }
        }
    }

    /// Stop whatever is playing.
    func stop() {
        blinkTask?.cancel()
        isLit = false
        ringSwell = nil
        loopTask?.cancel()
        loopTask = nil
        stopPlayer()
    }

    private func stopPlayer() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    // MARK: - Engine

    /// Start one run of the pattern. Returns false if it could not vibrate.
    /// If the engine was stopped behind our back, it is started again and the
    /// run is tried a second time.
    private func startRun(of pattern: CHHapticPattern?) -> Bool {
        guard let pattern else { return false }
        for attempt in 1...2 {
            if attempt == 2 { engineNeedsStart = true }
            guard let engine = readyEngine() else { continue }
            do {
                stopPlayer()
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                self.player = player
                return true
            } catch {
                print("Haptics: could not start the pattern (try \(attempt)): \(error.localizedDescription)")
            }
        }
        return false
    }

    /// The engine, created and started if needed. Nil if that failed.
    private func readyEngine() -> CHHapticEngine? {
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                // Vibration only: no audio session, so speech, music or a call
                // can't switch the engine off.
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = false
                engine.stoppedHandler = { [weak self] reason in
                    print("Haptics: engine stopped (\(reason.rawValue))")
                    Task { @MainActor in self?.engineNeedsStart = true }
                }
                engine.resetHandler = { [weak self] in
                    Task { @MainActor in self?.engineNeedsStart = true }
                }
                self.engine = engine
                engineNeedsStart = true
            }
            if engineNeedsStart {
                try engine?.start()
                engineNeedsStart = false
            }
            return engine
        } catch {
            print("Haptics: could not start the engine: \(error.localizedDescription)")
            engine = nil
            return nil
        }
    }
}
