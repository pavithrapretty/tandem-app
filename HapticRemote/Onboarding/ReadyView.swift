//
//  ReadyView.swift
//  HapticRemote (iPhone)
//
//  "04.10 Tutorial · Ready": the end of the tutorial, with all six signals
//  in one list. Tapping a row plays that signal again.
//

import SwiftUI

struct ReadyView: View {
    @ObservedObject var coach: TutorialCoach
    var onFinish: () -> Void

    private let owner = "ready"

    var body: some View {
        TutorialPage {
            Spacer(minLength: 0)

            Image("dial-ready")
                .accessibilityHidden(true)

            Text("You're ready")
                .font(.atkinson(36, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.72)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Here are all six signals. You can replay them any time in Settings.")
                .font(.atkinson(18, relativeTo: .body))
                .lineSpacing(1.8)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                ForEach(TutorialSignal.all) { signal in
                    if signal.pattern != TutorialSignal.all.first?.pattern {
                        Rectangle()
                            .fill(Palette.track)
                            .frame(height: 1)
                    }
                    row(signal)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))

            Spacer(minLength: 0)

            PrimaryButton("Go to Home", action: onFinish)
        }
        .onDisappear { coach.stop(owner: owner) }
    }

    private func row(_ signal: TutorialSignal) -> some View {
        Button {
            coach.playOnce(signal, owner: owner)
        } label: {
            HStack(spacing: 12) {
                Image(signal.summaryIcon)
                    .frame(width: 34, height: 34)
                    .background(signal.color, in: Circle())
                Text(signal.title)
                    .font(.atkinson(16, .bold, relativeTo: .callout))
                    .foregroundStyle(Palette.text)
                    .frame(width: 110, alignment: .leading)
                Text(signal.feel)
                    .font(.atkinson(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(signal.title): \(signal.feel)")
        .accessibilityHint("Plays the vibration")
        .accessibilityAddTraits(.isButton)
    }
}
