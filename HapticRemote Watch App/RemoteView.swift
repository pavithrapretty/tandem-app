//
//  RemoteView.swift
//  HapticRemote Watch App
//
//  The watch as the remote: buttons that make the iPhone vibrate and switch
//  its navigation screen to that direction.
//

import SwiftUI

struct RemoteView: View {
    @EnvironmentObject private var connectivity: ConnectivityManager

    var body: some View {
        // Same layout as on the iPhone: forward on top, left and right side
        // by side, turn around below.
        VStack(spacing: 6) {
            remoteButton(.forward)
            HStack(spacing: 6) {
                remoteButton(.left)
                remoteButton(.right)
            }
            remoteButton(.turnAround)
            HStack(spacing: 6) {
                remoteButton(.almostThere)
                remoteButton(.arrived)
            }

            if let error = connectivity.sendError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One button that switches a pattern on or off at the iPhone.
    private func remoteButton(_ pattern: Pattern) -> some View {
        let isOn = connectivity.remotePattern == pattern

        return Button {
            connectivity.toggleOnPhone(pattern)
        } label: {
            VStack(spacing: 0) {
                Image(systemName: pattern.symbol)
                    .font(.title3.weight(.bold))
                // Say the state in words, not only with colour.
                Text(isOn ? "On" : "Off")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isOn ? pattern.color : .gray)
        // VoiceOver reads "Left, On" instead of the name of the arrow symbol.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pattern.title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
