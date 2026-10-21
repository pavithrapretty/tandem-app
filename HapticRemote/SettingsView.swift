//
//  SettingsView.swift
//  HapticRemote (iPhone)
//
//  "20 Settings" in Figma, opened from the sliders button on the home screen.
//  The back button is the system one from the navigation stack ("Home").
//
//  In sections. Voice: voice guidance (the navigation screen's Voice
//  button is the same setting), the voice for Dutch names, and departures
//  at the stop. Vibration: on or off. Route: the dial's look-ahead and the
//  reroute distance, kept for every route. Learn: "Feel the signals again"
//  opens the tutorial. Testing: "Simulate a walk to Centraal" opens the
//  navigation screen with buttons to walk the route by hand; "Simulate by
//  dragging the map" opens it with a map to drag the user around on.
//  "Recorded walks" lists the real walks recorded on this phone, to share
//  or replay.
//

import AVFoundation
import SwiftUI

/// The guidance settings kept between walks (UserDefaults keys).
enum GuidanceSettings {
    /// The voice says each direction. Off at first: the vibration leads.
    static let voiceKey = "voiceGuidance"
    /// The iPhone vibrates the signals. On at first.
    static let vibrationKey = "vibration"
    /// Going to a stop: what can be caught there is said as guidance starts. On at first.
    static let departuresKey = "announceDepartures"
    /// The voice for the names of streets, stops and places (its
    /// identifier). Empty or missing: the best Dutch voice there is.
    static let dutchVoiceKey = "dutchVoice"
}

struct SettingsView: View {
    /// For the simulated walk, which vibrates here and on the watch.
    @ObservedObject var connectivity: ConnectivityManager
    @ObservedObject var phoneHaptics: PhoneHapticPlayer

    /// Set back to false to show the tutorial again (see HapticRemoteApp).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    /// The simulated walk that is open, if any.
    @State private var simulation: RouteNavigator.Simulation?
    /// Read by GuidanceView when a route starts.
    @AppStorage("dialLookAhead") private var lookAhead = RouteNavigator.defaultLookAhead
    @AppStorage("rerouteDistance") private var rerouteDistance = RouteNavigator.defaultRerouteDistance
    @AppStorage(GuidanceSettings.voiceKey) private var voiceOn = false
    @AppStorage(GuidanceSettings.vibrationKey) private var vibrationOn = true
    @AppStorage(GuidanceSettings.departuresKey) private var announcesDepartures = true
    @AppStorage(GuidanceSettings.dutchVoiceKey) private var dutchVoice = ""

    var body: some View {
        TutorialPage {
            Text("Settings")
                .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.68)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            section("VOICE", footer: "Siri can switch it too: “Turn the voice off in Tandem”.") {
                toggleRow(icon: "icon-settings-volume", title: "Voice guidance", isOn: $voiceOn,
                          hint: "Says each direction out loud while navigating. VoiceOver reads them either way.")
                divider
                NavigationLink {
                    DutchVoiceView()
                } label: {
                    row(icon: "icon-settings-volume", title: "Dutch names",
                        value: AVSpeechSynthesisVoice(identifier: dutchVoice)?.name ?? "Automatic")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("The voice that says the names of streets, stops and places.")
                divider
                toggleRow(systemImage: "tram", title: "Departures at the stop", isOn: $announcesDepartures,
                          hint: "Walking to a stop, says which trams, metros or buses you can catch when you get there.")
            }

            section("VIBRATION", footer: "Off, the dial still lights up with the signals, and a connected Apple Watch keeps vibrating.") {
                toggleRow(icon: "icon-settings-wave", title: "Vibration", isOn: $vibrationOn,
                          hint: "The iPhone vibrates the signals. Off, the dial still lights up with them; a connected Apple Watch keeps vibrating.")
            }

            section("ROUTE") {
                SettingSlider(title: "Dial looks ahead", value: $lookAhead,
                              range: RouteNavigator.lookAheadRange,
                              defaultValue: RouteNavigator.defaultLookAhead,
                              explanation: "How far along the route the pointer on the dial aims. Further ahead turns it towards a corner earlier; closer follows the street you're on. With the compass, it also decides when a turn is signalled.")
                divider
                SettingSlider(title: "New route after", value: $rerouteDistance,
                              range: RouteNavigator.rerouteDistanceRange,
                              defaultValue: RouteNavigator.defaultRerouteDistance,
                              explanation: "How far off the route you can get before a new route is found. Closer notices a wrong street sooner, but GPS drift may find new routes you don't need. With a weak GPS signal, up to 35 m is waited for anyway.")
            }

            section("LEARN") {
                Button {
                    hasCompletedOnboarding = false
                } label: {
                    linkLabel("Feel the signals again", icon: Image("icon-settings-play"))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the tutorial with the six signals.")
            }

            section("TESTING", footer: "Try the guidance without walking, or look back at real walks.") {
                simulationButton(.walk, title: "Simulate a walk to Centraal", systemImage: "figure.walk",
                                 hint: "Follows the route from where you are, moved with Forward and Back buttons instead of by walking.")
                divider
                simulationButton(.drag, title: "Simulate by dragging the map", systemImage: "hand.draw",
                                 hint: "Follows the route to Centraal, with you at the pin in the middle of a map you drag around.")
                divider
                NavigationLink {
                    RecordedWalksView(connectivity: connectivity, phoneHaptics: phoneHaptics)
                } label: {
                    linkLabel("Recorded walks", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Your recorded walks, to share or replay.")
            }

            Spacer(minLength: 0)
        }
        .fullScreenCover(item: $simulation) { simulation in
            GuidanceView(destination: .centraal, simulation: simulation,
                         connectivity: connectivity, phoneHaptics: phoneHaptics)
        }
        // The big title above is the page title, so the bar stays empty.
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// A group of settings: its name above (a heading for VoiceOver), its
    /// rows on one card, and a line about them under it.
    private func section<Content: View>(_ title: String, footer: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
                .padding(.horizontal, 18)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 18)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
            if let footer {
                Text(footer)
                    .font(.atkinson(15, relativeTo: .footnote))
                    .foregroundStyle(Palette.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
            }
        }
        .padding(.top, 8)
    }

    private func simulationButton(_ mode: RouteNavigator.Simulation, title: String,
                                  systemImage: String, hint: String) -> some View {
        Button {
            simulation = mode
        } label: {
            linkLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    /// A row that opens something: its symbol, title and a chevron.
    private func linkLabel(_ title: String, systemImage: String) -> some View {
        linkLabel(title, icon: Image(systemName: systemImage))
    }

    private func linkLabel(_ title: String, icon: Image) -> some View {
        HStack(spacing: 14) {
            icon
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.caption)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(.atkinson(19, .bold, relativeTo: .headline))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image("icon-chevron-right")
                .accessibilityHidden(true)
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.track)
            .frame(height: 1)
    }

    /// A setting that is on or off: VoiceOver reads "Voice guidance, switch, on".
    /// `icon`: one of the Settings icons; or `systemImage`, an SF Symbol in their grey.
    private func toggleRow(icon: String? = nil, systemImage: String? = nil, title: String,
                           isOn: Binding<Bool>, hint: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 14) {
                Group {
                    if let icon {
                        Image(icon)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Palette.caption)
                            .frame(width: 24, height: 24)
                    }
                }
                .accessibilityHidden(true)
                Text(title)
                    .font(.atkinson(19, .bold, relativeTo: .headline))
                    .foregroundStyle(Palette.text)
            }
        }
        // The system's own green: the screen's tint (cream, for the back
        // button) would otherwise colour the switch.
        .tint(.green)
        .padding(.vertical, 14)
        .accessibilityHint(hint)
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(icon)
                .accessibilityHidden(true)
            // The title in full; a long value (a voice's name) is cut short
            // on one line instead.
            Text(title)
                .font(.atkinson(19, .bold, relativeTo: .headline))
                .foregroundStyle(Palette.text)
                .fixedSize()
            Spacer(minLength: 8)
            Text(value)
                .font(.atkinson(18, .bold, relativeTo: .headline))
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
                .truncationMode(.tail)
            Image("icon-chevron-right")
                .accessibilityHidden(true)
        }
        .padding(.vertical, 18)
        // VoiceOver reads "Dutch names, Automatic".
        .accessibilityElement(children: .combine)
    }
}

/// A setting in metres: its name and value, a slider, what it does, and a
/// button back to the default once it has been changed.
private struct SettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let explanation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.atkinson(19, .bold, relativeTo: .headline))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("\(Int(value)) m")
                    .font(.atkinson(18, .bold, relativeTo: .headline))
                    .monospacedDigit()
                    .foregroundStyle(Palette.accent)
            }
            .accessibilityHidden(true)

            Slider(value: $value, in: range, step: 1)
                .tint(Palette.accent)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value)) metres")

            Text(explanation)
                .font(.atkinson(16, relativeTo: .callout))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if value != defaultValue {
                Button("Reset to \(Int(defaultValue)) m") {
                    value = defaultValue
                }
                .font(.atkinson(16, .bold, relativeTo: .callout))
                .foregroundStyle(Palette.accent)
            }
        }
        .padding(.vertical, 20)
    }
}

#Preview {
    Typography.registerFonts()
    return NavigationStack {
        SettingsView(connectivity: ConnectivityManager(), phoneHaptics: PhoneHapticPlayer())
    }
    .tint(Palette.text)
    .preferredColorScheme(.dark)
}

/// "Dutch names": the voice that says the names of streets, stops and
/// places. Picking one says a street name in it.
private struct DutchVoiceView: View {
    @AppStorage(GuidanceSettings.dutchVoiceKey) private var chosen = ""
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var preview = AVSpeechSynthesizer()

    var body: some View {
        TutorialPage {
            Text("Dutch names")
                .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.68)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text("Streets, stops and places are said in this voice. To add voices, download them in the iPhone's Settings, under Accessibility, Spoken Content, Voices, Dutch.")
                .font(.atkinson(17, .regular, relativeTo: .body))
                .foregroundStyle(Palette.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                option("Automatic", detail: TandemVoice.automaticDutch.map { TandemVoice.detail(of: $0) } ?? "No Dutch voice",
                       id: "")
                ForEach(voices, id: \.identifier) { voice in
                    divider
                    option(voice.name, detail: TandemVoice.detail(of: voice), id: voice.identifier)
                }
            }
            .padding(.horizontal, 18)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))

            Spacer(minLength: 0)
        }
        // Downloaded in the iPhone's Settings meanwhile: in the list on return.
        .onAppear { voices = TandemVoice.dutchVoices }
        .onDisappear { preview.stopSpeaking(at: .immediate) }
        .navigationTitle("Dutch names")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func option(_ title: String, detail: String, id: String) -> some View {
        Button {
            chosen = id
            preview.stopSpeaking(at: .immediate)
            preview.speak(.tandem("Nieuwezijds Voorburgwal", dutch: true))
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.atkinson(19, .bold, relativeTo: .headline))
                        .foregroundStyle(Palette.text)
                    Text(detail)
                        .font(.atkinson(16, .regular, relativeTo: .subheadline))
                        .foregroundStyle(Palette.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if chosen == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen == id ? .isSelected : [])
        .accessibilityHint("Says a street name in this voice.")
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.track)
            .frame(height: 1)
    }
}
