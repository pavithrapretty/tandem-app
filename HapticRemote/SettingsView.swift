//
//  SettingsView.swift
//  HapticRemote (iPhone)
//
//  "20 Settings" in Figma, opened from the sliders button on the home screen.
//  The back button is the system one from the navigation stack ("Home").
//
//  Voice guidance, departures at the stop and vibration switch on and
//  off, and are kept (the
//  navigation screen's Voice button is the same setting). The two
//  navigation sliders (dial look-ahead, reroute distance) work and are kept
//  for every route. The other values are only shown for now.
//  "Feel the signals again" works and
//  opens the tutorial. "Simulate a walk to Centraal" opens the navigation
//  screen with buttons to walk the route by hand; "Simulate by dragging the
//  map" opens it with a map to drag the user around on. "Recorded walks"
//  lists the real walks recorded on this phone, to share or replay.
//  Appearance doesn't lead anywhere yet.
//

import SwiftUI

/// The guidance settings kept between walks (UserDefaults keys).
enum GuidanceSettings {
    /// The voice says each direction. Off at first: the vibration leads.
    static let voiceKey = "voiceGuidance"
    /// The iPhone vibrates the signals. On at first.
    static let vibrationKey = "vibration"
    /// Going to a stop: what can be caught there is said as guidance starts. On at first.
    static let departuresKey = "announceDepartures"
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

    @AppStorage(VoiceSearchProvider.settingsKey) private var speechProvider = VoiceSearchProvider.apple.rawValue
    @State private var apiKey = ""
    @State private var keyStatus = ""
    @State private var hasAPIKey = false

    var body: some View {
        TutorialPage {
            Text("Settings")
                .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.68)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            settingsList

            voiceSearchSettings

            navigationSettings

            Button {
                hasCompletedOnboarding = false
            } label: {
                HStack(spacing: 14) {
                    Image("icon-settings-play")
                        .accessibilityHidden(true)
                    Text("Feel the signals again")
                        .font(.atkinson(19, .bold, relativeTo: .headline))
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image("icon-chevron-right")
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .glassButtonBackground(tint: nil, fallback: Palette.card,
                                       in: RoundedRectangle(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the tutorial with the six signals.")

            simulationButton(.walk, title: "Simulate a walk to Centraal", systemImage: "figure.walk",
                             hint: "Follows the route from where you are, moved with Forward and Back buttons instead of by walking.")

            simulationButton(.drag, title: "Simulate by dragging the map", systemImage: "hand.draw",
                             hint: "Follows the route to Centraal, with you at the pin in the middle of a map you drag around.")

            NavigationLink {
                RecordedWalksView(connectivity: connectivity, phoneHaptics: phoneHaptics)
            } label: {
                linkLabel("Recorded walks", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Your recorded walks, to share or replay.")

            Spacer(minLength: 0)
        }
        .onAppear { refreshKeyStatus() }
        .onDisappear { apiKey = "" }
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

    private var voiceSearchSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Destination voice search")
                .font(.atkinson(19, .bold, relativeTo: .headline))
                .accessibilityAddTraits(.isHeader)
            Picker("Speech provider", selection: $speechProvider) {
                ForEach(VoiceSearchProvider.allCases) { provider in
                    Text(provider.title).tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text("Apple Speech is the default. Deepgram streams microphone audio to Deepgram while you search and requires internet. Typed search is always available.")
                .font(.atkinson(16, relativeTo: .callout))
                .foregroundStyle(Palette.secondaryText)
            if speechProvider == VoiceSearchProvider.deepgram.rawValue {
                SecureField(hasAPIKey ? "Replace Deepgram API key" : "Deepgram API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .accessibilityLabel("Deepgram API key")
                HStack(spacing: 20) {
                    Button("Save key") {
                        do {
                            try DeepgramKeychain.save(apiKey)
                            apiKey = ""
                            refreshKeyStatus()
                        } catch { keyStatus = error.localizedDescription }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Delete key") {
                        do {
                            try DeepgramKeychain.delete()
                            apiKey = ""
                            refreshKeyStatus()
                        } catch { keyStatus = error.localizedDescription }
                    }
                    .disabled(!hasAPIKey)
                }
                .foregroundStyle(Palette.accent)
                Text(keyStatus)
                    .font(.atkinson(16, relativeTo: .callout))
                    .foregroundStyle(Palette.secondaryText)
                Text("Stored only in this iPhone’s Keychain. The saved key is never displayed. Streaming uses English for this experiment.")
                    .font(.atkinson(16, relativeTo: .callout))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .foregroundStyle(Palette.text)
        .padding(18)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .onChange(of: speechProvider) { _, _ in apiKey = "" }
    }

    private func refreshKeyStatus() {
        do {
            hasAPIKey = try DeepgramKeychain.read() != nil
            keyStatus = hasAPIKey ? "API key saved in Keychain." : "No API key saved."
        } catch { keyStatus = error.localizedDescription }
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

    /// A row that opens something: its symbol, title and a chevron, on glass.
    private func linkLabel(_ title: String, systemImage: String) -> some View {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.atkinson(19, .bold, relativeTo: .headline))
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image("icon-chevron-right")
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .glassButtonBackground(tint: nil, fallback: Palette.card,
                                   in: RoundedRectangle(cornerRadius: 24))
    }

    private var settingsList: some View {
        VStack(spacing: 0) {
            toggleRow(icon: "icon-settings-volume", title: "Voice guidance", isOn: $voiceOn,
                      hint: "Says each direction out loud while navigating. VoiceOver reads them either way.")
            divider
            row(icon: "icon-settings-gauge", title: "Voice speed", value: "Normal")
            divider
            toggleRow(systemImage: "tram", title: "Departures at the stop", isOn: $announcesDepartures,
                      hint: "Walking to a stop, says which trams, metros or buses you can catch when you get there.")
            divider
            toggleRow(icon: "icon-settings-wave", title: "Vibration", isOn: $vibrationOn,
                      hint: "The iPhone vibrates the signals. Off, the dial still lights up with them; a connected Apple Watch keeps vibrating.")
            divider
            row(icon: "icon-settings-wave", title: "Vibration strength", value: "Strong")
            divider
            row(icon: "icon-settings-pulse", title: "Hot/cold pulses", value: "On")
            divider
            Button {
                // TODO: open the appearance options.
            } label: {
                row(icon: "icon-settings-contrast", title: "Appearance", value: "Automatic")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var navigationSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .padding(.horizontal, 18)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
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
        .tint(Palette.accent)
        .padding(.vertical, 14)
        .accessibilityHint(hint)
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(icon)
                .accessibilityHidden(true)
            Text(title)
                .font(.atkinson(19, .bold, relativeTo: .headline))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.atkinson(18, .bold, relativeTo: .headline))
                .foregroundStyle(Palette.accent)
        }
        .padding(.vertical, 20)
        // VoiceOver reads "Voice guidance, On".
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
