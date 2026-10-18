//
//  SettingsView.swift
//  HapticRemote (iPhone)
//
//  "20 Settings" in Figma, opened from the sliders button on the home screen.
//  The back button is the system one from the navigation stack ("Home").
//
//  The two navigation sliders (dial look-ahead, reroute distance) work and
//  are kept for every route. The other values are only shown for now.
//  "Feel the signals again" works and
//  opens the tutorial. "Simulate a walk to Centraal" opens the navigation
//  screen with buttons to walk the route by hand; "Simulate by dragging the
//  map" opens it with a map to drag the user around on. Appearance doesn't
//  lead anywhere yet.
//

import SwiftUI

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

    var body: some View {
        TutorialPage {
            Text("Settings")
                .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.68)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            settingsList

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

    private func simulationButton(_ mode: RouteNavigator.Simulation, title: String,
                                  systemImage: String, hint: String) -> some View {
        Button {
            simulation = mode
        } label: {
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
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private var settingsList: some View {
        VStack(spacing: 0) {
            row(icon: "icon-settings-volume", title: "Voice guidance", value: "On")
            divider
            row(icon: "icon-settings-gauge", title: "Voice speed", value: "Normal")
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
