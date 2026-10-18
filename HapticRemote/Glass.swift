//
//  Glass.swift
//  HapticRemote (iPhone)
//
//  Liquid Glass for buttons and sheets. It needs iOS 26; on older iOS the button keeps
//  a flat fill in the same colour. With Reduce Transparency switched on, iOS
//  makes the glass solid by itself.
//

import SwiftUI

extension View {
    /// A Liquid Glass button background in `shape`, tinted with `tint`.
    /// Pass nil for clear glass. `fallback` is the flat fill before iOS 26.
    @ViewBuilder
    func glassButtonBackground<S: Shape>(tint: Color?, fallback: Color, in shape: S) -> some View {
        if #available(iOS 26, *) {
            // Interactive: the glass reacts to the finger (it bulges and glows).
            self.glassEffect((tint.map { Glass.regular.tint($0) } ?? .regular).interactive(), in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }

    /// A Liquid Glass background in the colour `color`, the same on every iOS version.
    func glassButtonBackground<S: Shape>(_ color: Color, in shape: S) -> some View {
        glassButtonBackground(tint: color, fallback: color, in: shape)
    }
}

/// The background of a sheet (`presentationBackground`): Liquid Glass tinted
/// with `tint`, whose opacity says how much of the screen behind shows
/// through. Before iOS 26: a blur under the same colour. The sheet clips it
/// to its own rounded shape.
struct GlassSheetBackground: View {
    let tint: Color

    var body: some View {
        if #available(iOS 26, *) {
            Color.clear
                .glassEffect(.regular.tint(tint), in: Rectangle())
                .ignoresSafeArea()
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                tint
            }
            .ignoresSafeArea()
        }
    }
}
