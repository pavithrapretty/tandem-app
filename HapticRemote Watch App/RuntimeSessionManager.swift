//
//  RuntimeSessionManager.swift
//  HapticRemote Watch App
//
//  Keeps the watch app running while the wrist is down, using a
//  WKExtendedRuntimeSession. Without it, watchOS suspends the app a few
//  seconds after the screen turns off and the iPhone can no longer reach it.
//
//  The session type is NOT chosen in code. It comes from the WKBackgroundModes
//  value in the watch target's Info.plist ("mindfulness", max 1 hour).
//

import Combine
import Foundation
import WatchKit

final class RuntimeSessionManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var statusText = "Off"

    private var session: WKExtendedRuntimeSession?

    /// Start a session. Must be called while the app is on screen.
    func start() {
        guard session == nil else { return }
        // A session object can only be used once, so we make a new one each time.
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        newSession.start()
        session = newSession
        statusText = "Starting…"
    }

    func stop() {
        session?.invalidate()
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension RuntimeSessionManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.isRunning = true
            self.statusText = "Running"
        }
    }

    /// The time limit (1 hour) is almost reached.
    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.statusText = "Expiring soon"
        }
    }

    /// The session ended: we stopped it, it timed out, the user left the app, or it failed.
    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        let text: String
        switch reason {
        case .none: text = "Off"
        case .expired: text = "Expired, start again"
        case .resignedFrontmost: text = "Ended, you left the app"
        case .sessionInProgress: text = "Another session is running"
        case .suppressedBySystem: text = "Blocked by system"
        case .error: text = "Error: \(error?.localizedDescription ?? "unknown")"
        @unknown default: text = "Ended"
        }

        Task { @MainActor in
            self.session = nil
            self.isRunning = false
            self.statusText = text
        }
    }
}
