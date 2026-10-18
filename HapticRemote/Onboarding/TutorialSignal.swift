//
//  TutorialSignal.swift
//  HapticRemote (iPhone)
//
//  The six signals the tutorial teaches, in order. The wording describes the
//  vibrations the app really plays (see `Pattern.steps` and the iPhone taps in
//  PhoneHapticPlayer.swift): if a pattern changes, update its text here too.
//

import SwiftUI

struct TutorialSignal: Identifiable {
    let pattern: Pattern
    /// Big title, e.g. "Turn left".
    let title: String
    /// What the vibration feels like.
    let feel: String
    /// The voice line, spoken aloud and shown in the card.
    let voiceLine: String
    /// One line that helps remember it.
    let tip: String
    let color: Color
    /// The arrow or icon in the middle of the big dial (92 pt).
    let dialIcon: String
    /// Small icon for the practice answers (30 pt), nil if it isn't a practice answer.
    let practiceIcon: String?
    /// Small icon for the summary list (18 pt).
    let summaryIcon: String

    var id: Pattern { pattern }

    static let all: [TutorialSignal] = [
        TutorialSignal(pattern: .left,
                       title: "Turn left",
                       feel: "Four quick taps",
                       voiceLine: "Turn left in 20 metres",
                       tip: "Count the taps: four in a row means left.",
                       color: Palette.left,
                       dialIcon: "dial-icon-left",
                       practiceIcon: "arrow-left-30",
                       summaryIcon: "arrow-left-18"),
        TutorialSignal(pattern: .right,
                       title: "Turn right",
                       feel: "Two taps with a gap",
                       voiceLine: "Turn right in 10 metres",
                       tip: "Two taps, apart, means right.",
                       color: Palette.right,
                       dialIcon: "dial-icon-right",
                       practiceIcon: "arrow-right-30",
                       summaryIcon: "arrow-right-18"),
        TutorialSignal(pattern: .forward,
                       title: "Go straight",
                       feel: "One heavy thud every second",
                       voiceLine: "Go straight for 80 metres",
                       tip: "A steady beat means keep going.",
                       color: Palette.text,
                       dialIcon: "dial-icon-straight",
                       practiceIcon: "arrow-straight-30",
                       summaryIcon: "arrow-straight-18"),
        TutorialSignal(pattern: .turnAround,
                       title: "Turn around",
                       feel: "Two rapid bursts",
                       voiceLine: "Wrong way. Turn around",
                       tip: "Bursts always mean: stop and turn.",
                       color: Palette.turnAround,
                       dialIcon: "dial-icon-uturn",
                       practiceIcon: "arrow-uturn-30",
                       summaryIcon: "arrow-uturn-18"),
        TutorialSignal(pattern: .arrived,
                       title: "Arrived",
                       feel: "Three taps, getting stronger",
                       voiceLine: "You've arrived at Centraal",
                       tip: "The journey is done.",
                       color: Palette.success,
                       dialIcon: "dial-icon-arrived",
                       practiceIcon: nil,
                       summaryIcon: "icon-check-18"),
        TutorialSignal(pattern: .signalLost,
                       title: "Signal lost",
                       feel: "A short buzz every 10 seconds",
                       voiceLine: "Signal lost. Keep walking straight",
                       tip: "We'll buzz again as soon as we find you.",
                       color: Palette.secondaryText,
                       dialIcon: "dial-icon-signal-lost",
                       practiceIcon: nil,
                       summaryIcon: "icon-nosig-18"),
    ]

    /// The four directions you can be asked about in practice.
    static var practice: [TutorialSignal] {
        all.filter { $0.practiceIcon != nil }
    }
}
