//
//  HapticRemoteApp.swift
//  HapticRemote Watch App
//
//  Created by Nejc Prezelj on 13. 10. 2026.
//

import SwiftUI

@main
struct HapticRemote_Watch_AppApp: App {
    // These three objects live as long as the app does.
    @StateObject private var player: HapticPlayer
    @StateObject private var connectivity: ConnectivityManager
    @StateObject private var runtime = RuntimeSessionManager()

    init() {
        // The connectivity manager needs the player, so we create them together.
        let player = HapticPlayer()
        _player = StateObject(wrappedValue: player)
        _connectivity = StateObject(wrappedValue: ConnectivityManager(player: player))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(connectivity)
                .environmentObject(runtime)
        }
    }
}
