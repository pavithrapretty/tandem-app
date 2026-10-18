//
//  PracticeView.swift
//  HapticRemote (iPhone)
//
//  "04.8 Tutorial · Practice" and "04.9 · Practice answer": one of the four
//  directions vibrates (no voice, over and over until answered), and the
//  user picks which one it was.
//

import SwiftUI

struct PracticeView: View {
    @ObservedObject var coach: TutorialCoach
    var onNext: () -> Void

    /// The signal being asked about.
    @State private var target: TutorialSignal
    /// The answer the user picked, nil until they pick one.
    @State private var picked: Pattern?

    /// `target` and `picked` are only passed in by the previews; the app
    /// starts with a random question and no answer.
    init(coach: TutorialCoach,
         target: TutorialSignal = TutorialSignal.practice.randomElement()!,
         picked: Pattern? = nil,
         onNext: @escaping () -> Void) {
        self.coach = coach
        self.onNext = onNext
        _target = State(initialValue: target)
        _picked = State(initialValue: picked)
    }

    private let owner = "practice"

    private var answered: Bool { picked != nil }
    private var isCorrect: Bool { picked == target.pattern }

    var body: some View {
        TutorialPage {
            TutorialProgress(filled: TutorialSignal.all.count)

            Eyebrow("PRACTICE")

            Text("Which one was that?")
                .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.68)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            Text("Feel the vibration, then pick what it means. The voice is off during practice.")
                .font(.atkinson(18, relativeTo: .body))
                .lineSpacing(1.8)
                .foregroundStyle(Palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            playButton

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                let answers = TutorialSignal.practice
                GridRow {
                    answerButton(answers[0])
                    answerButton(answers[1])
                }
                GridRow {
                    answerButton(answers[2])
                    answerButton(answers[3])
                }
            }

            if answered {
                feedback
            }

            Spacer(minLength: 0)

            if answered {
                PrimaryButton("Next", action: onNext)
                if !isCorrect {
                    SecondaryButton("Try another", action: newQuestion)
                }
            }
        }
        .onAppear {
            // Coming back from the Ready screen: the question is already answered.
            if !answered { coach.start(target, speak: false, owner: owner) }
        }
        .onDisappear { coach.stop(owner: owner) }
    }

    private var playButton: some View {
        Button {
            coach.start(target, speak: false, owner: owner)
        } label: {
            VStack(spacing: 8) {
                Image("icon-wave")
                    .frame(width: 112, height: 112)
                    .glassButtonBackground(tint: nil, fallback: Palette.card2, in: Circle())
                Text("Play again")
                    .font(.atkinson(16, .bold, relativeTo: .callout))
                    .foregroundStyle(Palette.text)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Play the vibration again")
        .accessibilityAddTraits(.isButton)
    }

    private func answerButton(_ signal: TutorialSignal) -> some View {
        // After answering, the right answer is outlined in green.
        let highlight = answered && signal.pattern == target.pattern

        return Button {
            pick(signal)
        } label: {
            VStack(spacing: 10) {
                Image(signal.practiceIcon ?? "")
                    .frame(width: 56, height: 56)
                    .background(signal.color, in: Circle())
                Text(signal.title)
                    .font(.atkinson(17, .bold, relativeTo: .headline))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .glassButtonBackground(tint: highlight ? Palette.success.opacity(0.12) : nil,
                                   fallback: highlight ? Palette.success.opacity(0.12) : Palette.card,
                                   in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                if highlight {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Palette.success, lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(answered)
        .accessibilityLabel(signal.title)
        .accessibilityValue(highlight ? "Correct answer" : (picked == signal.pattern ? "Your answer" : ""))
    }

    /// "Correct" (green) or "Not quite", with what the vibration was.
    private var feedback: some View {
        HStack(spacing: 12) {
            Group {
                if isCorrect {
                    Image("icon-check-20")
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Palette.background)
                }
            }
            .frame(width: 36, height: 36)
            .background(isCorrect ? Palette.success : Palette.turnAround, in: Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isCorrect ? "Correct" : "Not quite")
                    .font(.atkinson(18, .extraBold, relativeTo: .headline))
                    .foregroundStyle(Palette.text)
                Text(explanation)
                    .font(.atkinson(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isCorrect ? Palette.success.opacity(0.14) : Palette.card,
                    in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    /// e.g. "Two taps with a gap means turn right."
    private var explanation: String {
        "\(target.feel) means \(target.title.lowercased())."
    }

    private func pick(_ signal: TutorialSignal) {
        picked = signal.pattern
        coach.stop(owner: owner)
        let result = isCorrect ? "Correct." : "Not quite."
        AccessibilityNotification.Announcement("\(result) \(explanation)").post()
    }

    /// Ask again, with a (possibly different) random direction.
    private func newQuestion() {
        picked = nil
        target = TutorialSignal.practice.randomElement()!
        coach.start(target, speak: false, owner: owner)
    }
}
