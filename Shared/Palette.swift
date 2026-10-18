//
//  Palette.swift
//  Shared between the iPhone app and the Watch app
//
//  Tandem's base colour palette ("01 · Colour · base palette").
//  Dark by default: off-black background, warm off-white text.
//  Contrast ratios are measured against `background`.
//
//  Rules:
//  - `accent` (lavender) is for the main action on each screen only.
//    Put `onAccent` text on it.
//  - `success` is for "Arrived" and On states.
//  - No grey on grey: text is at least 6 : 1, icons at least 3 : 1.
//

import SwiftUI

enum Palette {
    /// #0B0C0F · Screen background.
    static let background = Color(hex: 0x0B0C0F)
    /// #16181D · Cards, rows, sheets.
    static let card = Color(hex: 0x16181D)
    /// #24272E · Secondary buttons, icon tiles.
    static let card2 = Color(hex: 0x24272E)
    /// #14161A · Behind the map while it loads.
    static let mapPanel = Color(hex: 0x14161A)
    /// #2A2D34 · Empty segments of the tutorial progress bar.
    static let track = Color(hex: 0x2A2D34)

    /// #F4F1EA · Titles and main text. 17.3 : 1 · AAA.
    static let text = Color(hex: 0xF4F1EA)
    /// #A9ADB6 · Supporting text. 8.7 : 1 · AAA.
    static let secondaryText = Color(hex: 0xA9ADB6)
    /// #D6D8DD · The line under a direction while navigating ("for 80 m").
    static let instruction = Color(hex: 0xD6D8DD)
    /// #C9CCD3 · Labels under the navigation toolbar icons.
    static let toolbarLabel = Color(hex: 0xC9CCD3)
    /// #8A8F99 · Labels, small caps. 6.0 : 1 · AA.
    static let caption = Color(hex: 0x8A8F99)

    /// #C4B5FD · Lavender. Main action only. 10.6 : 1 · AAA.
    static let accent = Color(hex: 0xC4B5FD)
    /// #14120B · Text and icons on `accent` buttons (dark on lavender, 10.1 : 1 · AAA).
    static let onAccent = Color(hex: 0x14120B)
    /// #3B2F73 · Small labels on `accent` cards, e.g. "NEAREST STOP".
    static let onAccentMuted = Color(hex: 0x3B2F73)
    /// #FF8A80 · Destructive actions, e.g. "End guidance".
    static let danger = Color(hex: 0xFF8A80)
    /// #4ADE80 · Arrived, On states. 11.2 : 1 · AAA.
    static let success = Color(hex: 0x4ADE80)

    // Direction colours, from the tutorial screens. Each direction also has
    // its own arrow and vibration, so colour is never the only cue.
    /// #3D8BFF · Turn left.
    static let left = Color(hex: 0x3D8BFF)
    /// #FF9F1C · Turn right.
    static let right = Color(hex: 0xFF9F1C)
    /// #FF4D6D · Turn around.
    static let turnAround = Color(hex: 0xFF4D6D)
    // Go straight uses `text`, Arrived `success`, Signal lost `secondaryText`.
}

extension Color {
    /// A colour from a 24-bit sRGB hex value, e.g. `Color(hex: 0xC4B5FD)`.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
