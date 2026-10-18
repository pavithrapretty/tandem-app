//
//  IntroView.swift
//  HapticRemote (iPhone)
//
//  "04.1 Tutorial · Intro": the three ways a direction reaches you.
//

import SwiftUI

struct IntroView: View {
    var onStart: () -> Void
    var onSkip: () -> Void

    var body: some View {
        TutorialPage {
            Eyebrow("FEEL THE SIGNALS")

            Text("Your phone guides you by touch")
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

            HStack(spacing: 8) {
                Image("icon-clock")
                    .accessibilityHidden(true)
                Text("Takes about 1 minute")
                    .font(.atkinson(15, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            PrimaryButton("Start", action: onStart)
            SecondaryButton("Skip for now", action: onSkip)
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
