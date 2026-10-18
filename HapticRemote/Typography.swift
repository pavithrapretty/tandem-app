//
//  Typography.swift
//  HapticRemote (iPhone)
//
//  Atkinson Hyperlegible Next, the typeface from the design. It is made for
//  low-vision readers. The font file is in Fonts/ (OFL licence next to it).
//
//  Every size grows with the user's Dynamic Type setting: `relativeTo` says
//  which text style it scales like.
//

import CoreText
import SwiftUI

enum Typography {
    /// Makes the bundled font available to the app. Call once at launch.
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "AtkinsonHyperlegibleNext", withExtension: "ttf") else {
            assertionFailure("AtkinsonHyperlegibleNext.ttf is missing from the app bundle")
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    /// The weights of Atkinson Hyperlegible Next we use.
    enum AtkinsonWeight: String {
        case regular = "AtkinsonHyperlegibleNext-Regular"
        case medium = "AtkinsonHyperlegibleNext-Regular_Medium"
        case bold = "AtkinsonHyperlegibleNext-Regular_Bold"
        case extraBold = "AtkinsonHyperlegibleNext-Regular_ExtraBold"
    }

    /// Atkinson Hyperlegible Next at `size` points, scaled like `style`.
    static func atkinson(_ size: CGFloat, _ weight: AtkinsonWeight = .regular,
                         relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }
}
