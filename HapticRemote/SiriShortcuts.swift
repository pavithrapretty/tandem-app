//
//  SiriShortcuts.swift
//  HapticRemote (iPhone)
//
//  What Siri can do in Tandem, with no setup in the Shortcuts app: "Turn the
//  voice off in Tandem", "Turn vibration on in Tandem". They change the same
//  settings as the switches in Settings and the navigation's Voice button,
//  so a walk under way follows at once, without the app coming forward.
//

import AppIntents

/// On or off, as said to Siri.
enum OnOff: String, AppEnum {
    case on, off

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "On or off"
    static let caseDisplayRepresentations: [OnOff: DisplayRepresentation] = [
        .on: "on",
        .off: "off",
    ]
}

/// The spoken directions on or off.
struct SetVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn the voice on or off"
    static let description = IntentDescription("Turns Tandem's spoken directions on or off, also during a walk.")

    @Parameter(title: "Voice")
    var state: OnOff

    static var parameterSummary: some ParameterSummary {
        Summary("Turn the voice \(\.$state)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(state == .on, forKey: GuidanceSettings.voiceKey)
        return .result(dialog: state == .on ? "Voice is on." : "Voice is off.")
    }
}

/// The vibration of the directions on this iPhone on or off.
struct SetVibrationIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn vibration on or off"
    static let description = IntentDescription("Turns the vibration of Tandem's directions on this iPhone on or off, also during a walk.")

    @Parameter(title: "Vibration")
    var state: OnOff

    static var parameterSummary: some ParameterSummary {
        Summary("Turn vibration \(\.$state)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(state == .on, forKey: GuidanceSettings.vibrationKey)
        return .result(dialog: state == .on ? "Vibration is on." : "Vibration is off.")
    }
}

/// The phrases Siri knows as soon as the app is installed. Each has the
/// app's name in it, as Siri needs.
struct TandemShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetVoiceIntent(), phrases: [
            "Turn the voice \(\.$state) in \(.applicationName)",
            "Turn voice \(\.$state) in \(.applicationName)",
            "Turn the voice navigation \(\.$state) in \(.applicationName)",
            "Turn \(.applicationName) voice \(\.$state)",
        ], shortTitle: "Voice on or off", systemImageName: "speaker.wave.2")

        AppShortcut(intent: SetVibrationIntent(), phrases: [
            "Turn vibration \(\.$state) in \(.applicationName)",
            "Turn the vibration \(\.$state) in \(.applicationName)",
            "Turn vibrations \(\.$state) in \(.applicationName)",
            "Turn \(.applicationName) vibration \(\.$state)",
        ], shortTitle: "Vibration on or off", systemImageName: "iphone.radiowaves.left.and.right")
    }
}
