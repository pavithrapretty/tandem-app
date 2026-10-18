//
//  HapticRemoteApp.swift
//  HapticRemote
//
//  Created by Nejc Prezelj on 13. 10. 2026.
//

import SwiftUI

@main
struct HapticRemoteApp: App {
    /// Set once the user leaves the onboarding, so it only shows after installing.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        Typography.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                HomeView()
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}
