//
//  OnboardingPreviews.swift
//  HapticRemote (iPhone)
//
//  Xcode previews of every tutorial screen, one per Figma frame (04.1 – 04.10).
//  They are muted: no vibration and no voice. The full flow, with sound, is
//  the "Onboarding flow" preview in OnboardingView.swift.
//

import SwiftUI

/// Shows a tutorial screen the way the app does: dark, in a navigation stack,
/// with the Back button when it isn't the first screen.
@MainActor
private func tutorialPreview<Screen: View>(showsBack: Bool = true,
                                           @ViewBuilder _ screen: (TutorialCoach) -> Screen) -> some View {
    Typography.registerFonts()
    let coach = TutorialCoach(muted: true)

    return NavigationStack {
        // An empty first screen, so the real one gets a Back button.
        Palette.background
            .ignoresSafeArea()
            .navigationDestination(isPresented: .constant(showsBack)) {
                screen(coach)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .overlay {
                if !showsBack {
                    screen(coach)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
    }
    .tint(Palette.accent)
    .preferredColorScheme(.dark)
}

/// The signals screen, showing signal number `index + 1`.
@MainActor
private func signalPreview(_ index: Int) -> some View {
    tutorialPreview { coach in
        SignalsView(coach: coach, startIndex: index, onFinish: {})
    }
}

private func practiceSignal(_ pattern: Pattern) -> TutorialSignal {
    TutorialSignal.all.first { $0.pattern == pattern }!
}

#Preview("04.1 Intro") {
    tutorialPreview(showsBack: false) { _ in
        IntroView(onStart: {}, onSkip: {})
    }
}

#Preview("04.2 Turn left") { signalPreview(0) }
#Preview("04.3 Turn right") { signalPreview(1) }
#Preview("04.4 Go straight") { signalPreview(2) }
#Preview("04.5 Turn around") { signalPreview(3) }
#Preview("04.6 Arrived") { signalPreview(4) }
#Preview("04.7 Signal lost") { signalPreview(5) }

#Preview("04.8 Practice") {
    tutorialPreview { coach in
        PracticeView(coach: coach, target: practiceSignal(.right), onNext: {})
    }
}

#Preview("04.9 Practice, correct") {
    tutorialPreview { coach in
        PracticeView(coach: coach, target: practiceSignal(.right), picked: .right, onNext: {})
    }
}

#Preview("04.9 Practice, wrong") {
    tutorialPreview { coach in
        PracticeView(coach: coach, target: practiceSignal(.right), picked: .left, onNext: {})
    }
}

#Preview("04.10 Ready") {
    tutorialPreview { coach in
        ReadyView(coach: coach, onFinish: {})
    }
}

#Preview("Intro, largest text") {
    tutorialPreview(showsBack: false) { _ in
        IntroView(onStart: {}, onSkip: {})
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Dial, normal and lit") {
    Typography.registerFonts()
    return VStack(spacing: 24) {
        DirectionDial(signal: TutorialSignal.all[3])
        DirectionDial(signal: TutorialSignal.all[3], isLit: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.background)
}
