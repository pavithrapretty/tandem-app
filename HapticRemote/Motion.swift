//
//  Motion.swift
//  HapticRemote (iPhone)
//
//  The motion scale from transitions.dev (its "Motion tokens"), for SwiftUI,
//  and the transitions built from it: a card resizing, text swapping in
//  place (the old leaves upwards with a blur, then the new comes up from
//  below), and an icon swapping in its slot. With Reduce Motion, callers
//  pass no animation: everything just switches.
//

import SwiftUI

enum Motion {
    /// Text swap, each half: out, then in.
    static let quick: Double = 0.15
    /// Icon swap.
    static let fast: Double = 0.25
    /// A card resizing.
    static let resize: Double = 0.3

    /// transitions.dev's smooth-out: cubic-bezier(0.22, 1, 0.36, 1).
    static func smoothOut(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    /// A card changes height (the next step ↔ what can be caught at the stop).
    static let cardResize = smoothOut(resize)

    /// How far text moves as it swaps, and how much it blurs.
    static let swapDistance: CGFloat = 4
    static let swapBlur: CGFloat = 2
    /// How small an icon gets as it swaps, and its blur.
    static let iconScale: CGFloat = 0.8
}

extension AnyTransition {
    /// Text states swap: the old leaves upwards, blurring and fading, over
    /// `Motion.quick`; then the new comes up from below, sharpening, over the
    /// same. Each half carries its own timing, whatever animates the change.
    static var textSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: SwapEffect(y: Motion.swapDistance, blur: Motion.swapBlur, opacity: 0),
                                 identity: SwapEffect(y: 0, blur: 0, opacity: 1))
                .animation(.easeInOut(duration: Motion.quick).delay(Motion.quick)),
            removal: .modifier(active: SwapEffect(y: -Motion.swapDistance, blur: Motion.swapBlur, opacity: 0),
                               identity: SwapEffect(y: 0, blur: 0, opacity: 1))
                .animation(.easeInOut(duration: Motion.quick)))
    }

    /// Icon swap: the two cross-fade in the same slot, with a little blur and scale.
    static var iconSwap: AnyTransition {
        .modifier(active: SwapEffect(y: 0, blur: Motion.swapBlur, opacity: 0, scale: Motion.iconScale),
                  identity: SwapEffect(y: 0, blur: 0, opacity: 1))
            .animation(.easeInOut(duration: Motion.fast))
    }
}

private struct SwapEffect: ViewModifier {
    let y: CGFloat
    let blur: CGFloat
    let opacity: Double
    var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
            .offset(y: y)
    }
}
