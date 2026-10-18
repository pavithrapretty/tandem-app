//
//  ContentView.swift
//  HapticRemote Watch App
//
//  Two pages, one above the other (swipe up or turn the Digital Crown):
//  1. The remote: four buttons that make the iPhone vibrate (RemoteView).
//  2. The last direction as a big arrow and title, on a background in the
//     direction's colour that pulses every time a haptic plays (DirectionView).
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var runtime: RuntimeSessionManager

    /// Tells us whether the app is on screen right now.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            RemoteView()
            DirectionView()
        }
        .tabViewStyle(.verticalPage)
        // There is no session button any more, so the session that keeps the app
        // alive with the wrist down starts by itself whenever the app is on screen.
        // (It is only allowed to start while the app is on screen.)
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                runtime.start()
            }
        }
    }
}

/// Page 2: what the iPhone last sent us.
struct DirectionView: View {
    @EnvironmentObject private var connectivity: ConnectivityManager
    @EnvironmentObject private var player: HapticPlayer

    var body: some View {
        VStack(spacing: 8) {
            // The arrow of the last direction we received.
            if let symbol = connectivity.lastPatternSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 56, weight: .bold))
            }

            Text(connectivity.lastPatternName ?? "Waiting…")
                .font(.title2.weight(.bold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The background takes the colour of the direction.
        .background {
            let color = connectivity.lastPatternColor ?? .clear
            ZStack {
                // Steady colour: strong while the pattern plays, dim afterwards.
                color.opacity(player.playing == nil ? 0.3 : 0.6)

                // Pulse: full colour pops in and fades out with every haptic.
                color.phaseAnimator([false, true], trigger: player.flashCount) { pulse, isLit in
                    pulse.opacity(isLit ? 1 : 0)
                } animation: { isLit in
                    isLit ? .linear(duration: 0.05) : .easeOut(duration: 0.3)
                }
            }
            .ignoresSafeArea()
            // Fade smoothly when the colour or the playing state changes.
            .animation(.easeInOut(duration: 0.4), value: player.playing)
            .animation(.easeInOut(duration: 0.4), value: connectivity.lastPatternName)
        }
    }
}

// MARK: - Previews
// One preview per screen the watch can show. The state is filled in by hand,
// so nothing has to be sent from the iPhone and no haptics play.

/// Builds the view in a fixed state for a preview.
@MainActor
private func previewScreen(name: String? = nil,
                           symbol: String? = nil,
                           color: Color? = nil,
                           playing: Pattern? = nil,
                           remote: Pattern? = nil,
                           showRemote: Bool = false) -> some View {
    let player = HapticPlayer()
    player.playing = playing

    let connectivity = ConnectivityManager(player: player)
    connectivity.lastPatternName = name
    connectivity.lastPatternSymbol = symbol
    connectivity.lastPatternColor = color
    connectivity.remotePattern = remote

    // Each page is shown on its own, so every preview opens on the right one.
    return Group {
        if showRemote {
            RemoteView()
        } else {
            DirectionView()
        }
    }
    .environmentObject(player)
    .environmentObject(connectivity)
    .environmentObject(RuntimeSessionManager())
}

/// A direction that is playing right now (strong background).
@MainActor
private func previewScreen(playing pattern: Pattern) -> some View {
    previewScreen(name: pattern.title, symbol: pattern.symbol, color: pattern.color, playing: pattern)
}

#Preview("Waiting") {
    previewScreen()
}

#Preview("Forward") {
    previewScreen(playing: .forward)
}

#Preview("Left") {
    previewScreen(playing: .left)
}

#Preview("Right") {
    previewScreen(playing: .right)
}

#Preview("Turn around") {
    previewScreen(playing: .turnAround)
}

#Preview("Stopped") {
    previewScreen(name: "Stopped", symbol: "stop.fill")
}

#Preview("Unknown pattern") {
    previewScreen(name: "Unknown pattern", symbol: "questionmark")
}

#Preview("Remote") {
    previewScreen(showRemote: true)
}

#Preview("Remote, Left on") {
    previewScreen(remote: .left, showRemote: true)
}
