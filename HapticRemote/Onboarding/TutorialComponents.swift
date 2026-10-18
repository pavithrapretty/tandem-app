//
//  TutorialComponents.swift
//  HapticRemote (iPhone)
//
//  Pieces every tutorial screen shares: the page layout, the progress bar,
//  the small caps label and the lavender main button.
//

import SwiftUI

/// The frame of a tutorial screen: dark background, 24 pt side margins, and
/// content that fills the screen but scrolls when the text is very large.
/// `tint` washes the background faintly in a colour (the signal screens use
/// the colour of the signal).
struct TutorialPage<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                // At least as tall as the screen, so spacers can push the
                // button to the bottom.
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { TutorialBackground(tint: tint) }
    }
}

/// The tutorial screens' background, also behind the navigation screen.
struct TutorialBackground: View {
    var tint: Color? = nil

    var body: some View {
        ZStack {
            Palette.background
            if let tint {
                // Strongest at the top, around the dial, fading out
                // towards the button.
                LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

/// Six segments, the first `filled` of them lit.
struct TutorialProgress: View {
    var filled: Int
    var total = TutorialSignal.all.count

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index < filled ? Palette.text : Palette.track)
                    .frame(height: 5)
            }
        }
        // The small caps label under it already says where you are.
        .accessibilityHidden(true)
    }
}

/// Small caps label above a title, e.g. "SIGNAL 1 OF 6".
struct Eyebrow: View {
    var text: String
    var alignment: TextAlignment = .leading

    init(_ text: String, alignment: TextAlignment = .leading) {
        self.text = text
        self.alignment = alignment
    }

    var body: some View {
        Text(text)
            .font(.atkinson(14, .bold, relativeTo: .footnote))
            .tracking(0.84)
            .foregroundStyle(Palette.caption)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity,
                   alignment: alignment == .center ? .center : .leading)
    }
}

/// The lavender main action of a screen.
struct PrimaryButton: View {
    var title: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.atkinson(20, .extraBold, relativeTo: .title3))
                .foregroundStyle(Palette.onAccent)
                .frame(maxWidth: .infinity, minHeight: 64)
                // 80% lavender, so the Liquid Glass shows through. Solid before iOS 26.
                .glassButtonBackground(tint: Palette.accent.opacity(0.8), fallback: Palette.accent,
                                       in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

/// The grey secondary action, e.g. "Skip for now". `destructive`: larger,
/// with red text, for an action that ends something ("End guidance").
struct SecondaryButton: View {
    var title: String
    var destructive = false
    var action: () -> Void

    init(_ title: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.atkinson(destructive ? 20 : 18, .bold, relativeTo: destructive ? .title3 : .headline))
                .foregroundStyle(destructive ? Palette.danger : Palette.text)
                .frame(maxWidth: .infinity, minHeight: destructive ? 64 : 56)
                // Clear glass; a flat grey before iOS 26.
                .glassButtonBackground(tint: nil, fallback: Palette.card2,
                                       in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}
