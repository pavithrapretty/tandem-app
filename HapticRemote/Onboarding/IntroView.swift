//
//  IntroView.swift
//  HapticRemote (iPhone)
//
//  "04.1 Tutorial · Intro": "Welcome to Tandem" and the three ways a
//  direction reaches you, with the voice's mute button top left and, while
//  the recording plays, a button beside it to skip straight to the
//  microphone. A
//  recorded voice (intro.mp3) says welcome, reads the screen and asks
//  whether to start, once, when the screen first appears (the line at the
//  top fills up as it plays);
//  leaving the screen stops it. After the question the microphone listens
//  for the answer: a yes ("yes", "continue", "do onboarding", "yep") is the
//  same as Start, a no ("no", "skip", "I don't want to") the same as Skip
//  for now. It waits for the user to stop talking, then confirms a yes or
//  a no with a chime before going on. Nothing understood, and the buttons
//  are still there. While it
//  listens, the screen's edge glows lavender, as when holding the home
//  screen for the voice search.
//

import SwiftUI

struct IntroView: View {
    var onStart: () -> Void
    var onSkip: () -> Void
    /// How wide the glow round the screen's edge is while the microphone
    /// listens. Drawn by OnboardingView, on top of everything, so it never
    /// moves anything on the screen.
    var glowWidth: Binding<CGFloat> = .constant(0)

    /// The welcome, reading the screen, then the question whether to start.
    @State private var sound = RecordedVoice(["intro"])
    /// Coming back from the signals screen doesn't play it again.
    @State private var hasPlayed = false
    /// The recording has ended or was skipped: no skip button any more.
    @State private var voiceIsDone = false
    /// Hears the answer to the question at the end of the recording.
    @StateObject private var listener = SpeechListener()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(RecordedVoice.mutedKey) private var voiceMuted = false

    var body: some View {
        TutorialPage {
            VoiceProgressBar(voice: sound)

            Text("Welcome to Tandem")
                .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.68)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text("There are six vibrations. Each one also has a voice line and a colour, so you can use whatever works for you.")
                .font(.atkinson(18, relativeTo: .body))
                .lineSpacing(1.8)
                .foregroundStyle(Palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            card(icon: "icon-hand",
                 title: "Hold it or pocket it",
                 detail: "Vibrations work in your hand or in your pocket.")
            card(icon: "icon-volume",
                 title: "Hear it",
                 detail: "A voice says the same thing. Turn it off any time.")
            card(icon: "icon-eye",
                 title: "See it",
                 detail: "A big arrow shows the direction, if you want to look.")

            Spacer(minLength: 0)

            // Its room is always kept, so nothing moves when it shows.
            listeningHint
                .opacity(listener.isRunning ? 1 : 0)
                .accessibilityHidden(!listener.isRunning)

            PrimaryButton("Start", action: onStart)
            SecondaryButton("Skip for now", action: onSkip)
        }
        // Listening: the glow round the screen's edge, as when holding the
        // home screen for the voice search, swelling with the voice. Only the
        // glow animates: fading in and out slowly, following the voice fast.
        .onChange(of: listeningGlowWidth) { old, new in
            withAnimation(.easeOut(duration: old == 0 || new == 0 ? 0.3 : 0.1)) {
                glowWidth.wrappedValue = new
            }
        }
        // The mute button where the other screens have it, by their back arrow.
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                VoiceMuteButton()
                if !voiceIsDone {
                    Button(action: skipVoice) {
                        Image(systemName: "forward.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 28)
                    }
                    .accessibilityLabel("Skip the voice")
                    .accessibilityHint("Stops the recording and listens for your answer straight away.")
                }
            }
        }
        .onChange(of: voiceMuted) { sound.isMuted = voiceMuted }
        .task {
            guard !hasPlayed else { return }
            hasPlayed = true
            sound.onFinish = {
                voiceIsDone = true
                listener.start()
            }
            // Once the user stops talking: a yes or a no gets the confirming
            // chime, and only then goes on.
            listener.accepts = { SpokenAnswer($0) != nil }
            listener.onFinish = { answer($0) }
            await sound.play()
        }
        .onDisappear {
            sound.stop()
            listener.stop()
            // Gone with the screen, not left behind on the next one.
            withAnimation(.easeOut(duration: 0.3)) { glowWidth.wrappedValue = 0 }
        }
    }

    /// The glow's width: the home screen's full hold (20 pt), a little wider
    /// as the voice gets loud (not with Reduce Motion), 0 when not listening.
    private var listeningGlowWidth: CGFloat {
        guard listener.isRunning else { return 0 }
        return reduceMotion ? 20 : 16 + 8 * listener.level
    }

    /// Shown while the microphone listens for the answer.
    private var listeningHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text("Listening. Say “yes” to start or “skip”.")
                .font(.atkinson(15, .bold, relativeTo: .subheadline))
                .foregroundStyle(Palette.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The skip button: the recording stops, and the microphone listens for
    /// the answer at once.
    private func skipVoice() {
        voiceIsDone = true
        sound.stop()
        listener.start()
    }

    /// Acts on a spoken answer like the button it stands for.
    private func answer(_ words: String) {
        guard let choice = SpokenAnswer(words) else { return }
        listener.stop()
        switch choice {
        case .yes: onStart()
        case .no: onSkip()
        }
    }

    /// One way to get the direction: an icon tile, a title and a line of detail.
    private func card(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(icon)
                .frame(width: 48, height: 48)
                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.atkinson(18, .bold, relativeTo: .headline))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.atkinson(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.secondaryText)
            }
            // Wrap onto more lines instead of cutting the text off with "…".
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

/// A yes or a no in what the user said, if there is one. A no wins, so "I
/// don't want to do the onboarding" skips.
private enum SpokenAnswer {
    case yes, no

    private static let noWords: Set = ["no", "nope", "nah", "skip", "later", "don't", "dont"]
    private static let noPhrases = ["not now", "do not", "skip for now"]
    private static let yesWords: Set = ["yes", "yeah", "yep", "yup", "sure", "ok", "okay",
                                        "continue", "start", "onboarding"]
    private static let yesPhrases = ["on boarding", "let's go", "let's do it"]

    init?(_ said: String) {
        let text = said.lowercased().replacingOccurrences(of: "’", with: "'")
        let words = text.split { !$0.isLetter && $0 != "'" }.map(String.init)
        let joined = " " + words.joined(separator: " ") + " "
        func has(_ wordSet: Set<String>, _ phrases: [String]) -> Bool {
            words.contains(where: wordSet.contains) || phrases.contains { joined.contains(" \($0) ") }
        }
        if has(Self.noWords, Self.noPhrases) {
            self = .no
        } else if has(Self.yesWords, Self.yesPhrases) {
            self = .yes
        } else {
            return nil
        }
    }
}
