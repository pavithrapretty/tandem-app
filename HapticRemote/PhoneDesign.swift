//
//  PhoneDesign.swift
//  HapticRemote (iPhone)
//
//  The vibrations the iPhone can play for a signal, to choose from in
//  Settings (Vibration patterns): each signal can feel like any of them. A
//  design is a rhythm (`steps`) and, for some, a Pulsar preset played on
//  every step instead of the step's own taps (see PhoneHapticPlayer).
//
//  Only the iPhone: the watch keeps its own haptics (Pattern.steps). A
//  choice is read every time a signal starts, so it applies from the next
//  vibration on, also in the middle of a walk.
//

import Foundation

enum PhoneDesign: String, CaseIterable, Identifiable {
    case coil
    case fourTaps
    case twoTaps
    case anvilBeat
    case fastAnvilBeat
    case risingBeat
    case barrage
    case doubleBuzz
    case risingTaps
    case shortBuzz

    var id: String { rawValue }

    /// Short name, for the Settings row.
    var title: String {
        switch self {
        case .coil: "Coil"
        case .fourTaps: "Four taps"
        case .twoTaps: "Two taps"
        case .anvilBeat: "Anvil"
        case .fastAnvilBeat: "Fast anvil"
        case .risingBeat: "Rising tap"
        case .barrage: "Barrage"
        case .doubleBuzz: "Double buzz"
        case .risingTaps: "Three taps"
        case .shortBuzz: "Short buzz"
        }
    }

    /// What it feels like.
    var detail: String {
        switch self {
        case .coil: "A buzz that winds up into one hard tap"
        case .fourTaps: "Four strong taps in a row"
        case .twoTaps: "Two strong taps with a gap"
        case .anvilBeat: "A heavy thud every second"
        case .fastAnvilBeat: "A heavy thud twice a second"
        case .risingBeat: "A light rising tap every second"
        case .barrage: "Two bursts of rapid, sharp taps"
        case .doubleBuzz: "Two heavy buzzes"
        case .risingTaps: "Three taps getting stronger"
        case .shortBuzz: "One short buzz every 10 seconds"
        }
    }

    /// Played on every step instead of the step's haptic, or nil.
    var preset: PhonePreset? {
        switch self {
        case .coil: .coil
        case .anvilBeat, .fastAnvilBeat: .anvil
        case .barrage: .barrage
        default: nil
        }
    }

    /// The rhythm. For a repeating signal, the last delay is the pause
    /// before it starts again.
    var steps: [PatternStep] {
        switch self {
        case .coil:
            // Coil is about 0.65 seconds on its own: then 1 second of quiet.
            [PatternStep(haptic: .start, delay: 0.65 + 1.0)]
        case .fourTaps:
            [PatternStep(haptic: .start, delay: 0.35),
             PatternStep(haptic: .start, delay: 0.35),
             PatternStep(haptic: .start, delay: 0.35),
             PatternStep(haptic: .start, delay: 1.0)]
        case .twoTaps:
            [PatternStep(haptic: .start, delay: 0.9),
             PatternStep(haptic: .start, delay: 1.0)]
        case .anvilBeat, .risingBeat:
            [PatternStep(haptic: .directionUp, delay: 1.0)]
        case .fastAnvilBeat:
            [PatternStep(haptic: .directionUp, delay: 0.5)]
        case .barrage:
            // Barrage lasts about 0.3 seconds: 1 second of quiet after the second one.
            [PatternStep(haptic: .failure, delay: 1.0),
             PatternStep(haptic: .failure, delay: 0.31 + 1.0)]
        case .doubleBuzz:
            [PatternStep(haptic: .failure, delay: 1.0),
             PatternStep(haptic: .failure, delay: 1.0)]
        case .risingTaps:
            [PatternStep(haptic: .success, delay: 2.0)]
        case .shortBuzz:
            [PatternStep(haptic: .retry, delay: 10.0)]
        }
    }
}

extension Pattern {
    /// UserDefaults key for the design chosen for this signal.
    var designKey: String { "phoneDesign.\(rawValue)" }

    /// What the signal felt like before it could be chosen.
    var defaultDesign: PhoneDesign {
        switch self {
        case .forward: .anvilBeat
        case .almostThere: .fastAnvilBeat
        case .left: .coil
        case .right: .twoTaps
        case .turnAround: .barrage
        case .arrived: .risingTaps
        case .signalLost: .shortBuzz
        }
    }

    /// The design chosen in Settings, or the default.
    var phoneDesign: PhoneDesign {
        UserDefaults.standard.string(forKey: designKey).flatMap(PhoneDesign.init) ?? defaultDesign
    }
}
