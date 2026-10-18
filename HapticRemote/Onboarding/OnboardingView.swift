//
//  OnboardingView.swift
//  HapticRemote (iPhone)
//
//  The tutorial shown after installing the app ("04 Tutorial" in Figma):
//  intro → six signals → practice → ready. The screens sit in a navigation
//  stack, so the back button and the swipe from the left edge go back one
//  screen. The six signals are one screen, which slides from signal to
//  signal by itself (SignalsView). "Skip for now" and "Go to Home" both call
//  `onFinish`.
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

    var body: some View {
        NavigationStack(path: $path) {
            IntroView(onStart: { path.append(.signals) }, onSkip: onFinish)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Step.self) { step in
                    screen(for: step)
                        .navigationBarTitleDisplayMode(.inline)
                        // See-through bar: the page (and its tint) shows behind it.
                        .toolbarBackground(.hidden, for: .navigationBar)
                }
        }
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
        case .ready:
            ReadyView(coach: coach, onFinish: onFinish)
        }
    }
}

// The whole flow, with sound and vibration. Run it in Live mode to tap
// through it. The single screens are in OnboardingPreviews.swift.
#Preview("Onboarding flow") {
    Typography.registerFonts()
    return OnboardingView(onFinish: {})
}
