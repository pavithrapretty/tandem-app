//
//  OnboardingView.swift
//  HapticRemote (iPhone)
//
//  The tutorial shown after installing the app ("04 Tutorial" in Figma):
//  intro → six signals → practice → ready. The screens sit in a navigation
//  stack, so the back button and the swipe from the left edge go back one
//  screen. The six signals are one screen, which slides from signal to
//  signal by itself (SignalsView). "Skip for now" and "Go to Home" both call
//  `onFinish`. Next to the back arrow, a button mutes the recorded voice
//  (VoiceMuteButton; SignalsView has its own back arrow, so it adds it there).
//

import SwiftUI

struct OnboardingView: View {
    /// Called when the user leaves the tutorial.
    var onFinish: () -> Void

    private enum Step: Hashable {
        case signals
        case practice
        case ready
    }

    @State private var path: [Step] = []
    @StateObject private var coach = TutorialCoach()
    /// The glow round the screen's edge while the intro listens for an answer.
    @State private var glowWidth: CGFloat = 0

    var body: some View {
        NavigationStack(path: $path) {
            IntroView(onStart: { path.append(.signals) }, onSkip: onFinish, glowWidth: $glowWidth)
                // The bar only for the mute button: see-through, as on the others.
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationDestination(for: Step.self) { step in
                    screen(for: step)
                        .navigationBarTitleDisplayMode(.inline)
                        // See-through bar: the page (and its tint) shows behind it.
                        .toolbarBackground(.hidden, for: .navigationBar)
                }
        }
        // Above the whole stack, so it covers the screens without moving them.
        .overlay { ScreenEdgeGlow(width: glowWidth) }
        // The back button is lavender on the dark background.
        .tint(Palette.accent)
        // Dark by default, so the status bar text is light.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func screen(for step: Step) -> some View {
        switch step {
        case .signals:
            SignalsView(coach: coach) { path.append(.practice) }
        case .practice:
            PracticeView(coach: coach) { path.append(.ready) }
                .toolbar { ToolbarItem(placement: .topBarLeading) { VoiceMuteButton() } }
        case .ready:
            ReadyView(coach: coach, onFinish: onFinish)
                .toolbar { ToolbarItem(placement: .topBarLeading) { VoiceMuteButton() } }
        }
    }
}

// The whole flow, with sound and vibration. Run it in Live mode to tap
// through it. The single screens are in OnboardingPreviews.swift.
#Preview("Onboarding flow") {
    Typography.registerFonts()
    return OnboardingView(onFinish: {})
}
