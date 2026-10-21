//
//  HapticRemoteApp.swift
//  HapticRemote
//
//  Created by Nejc Prezelj on 13. 10. 2026.
//

import SwiftUI

@main
struct HapticRemoteApp: App {
    init() {
        Typography.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// The tutorial or the home screen. In a view of its own, not the App: there
/// the switch back to Home after replaying the tutorial (Settings) was saved
/// but never redrawn, so "Go to Home" seemed to do nothing.
private struct RootView: View {
    /// Set once the user leaves the onboarding, so it only shows after installing.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            HomeView()
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}
