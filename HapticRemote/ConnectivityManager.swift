//
//  ConnectivityManager.swift
//  HapticRemote (iPhone)
//
//  Talks to the watch through WatchConnectivity (WCSession).
//  The view observes this object to show connection status and send results.
//  It also listens: the watch can send a pattern for the iPhone to play.
//

import Combine
import Foundation
import WatchConnectivity

/// What happened the last time we tried to send something.
/// The String is the name shown in the UI, e.g. "Left" or "Stop".
enum SendResult {
    /// Sent live with `sendMessage`, waiting for the watch to answer.
    case sending(String)
    /// The watch answered. `roundTrip` is the time from tap to answer, in seconds.
    case delivered(String, roundTrip: TimeInterval)
    /// The watch was not reachable, so it was queued with `transferUserInfo`.
    /// It will arrive later, when the watch app next runs.
    case queued(String)
    /// Something went wrong.
    case failed(String)
    /// The other direction: the watch sent this to us.
    case received(String)
}

final class ConnectivityManager: NSObject, ObservableObject {
    // Connection status, shown in the UI.
    @Published var isActivated = false
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false
    @Published var isReachable = false

    @Published var lastResult: SendResult?

    /// Fires when the watch asks the iPhone to play a pattern (nil = stop).
    /// The view listens to this and plays it.
    let received = PassthroughSubject<Pattern?, Never>()

    override init() {
        super.init()
        // WCSession is not supported on every device (e.g. iPad).
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send a pattern to the watch as fast as possible. `interval` sets the
    /// seconds between Go straight taps (nil: the normal speed).
    func send(_ pattern: Pattern, interval: TimeInterval? = nil) {
        send(name: pattern.rawValue, label: pattern.title, interval: interval)
    }

    /// Change how fast the watch's Go straight taps, without restarting it.
    /// Only live: a late speed change would be wrong by the time it arrived.
    func sendInterval(_ interval: TimeInterval) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        sendLive([MessageKey.interval: interval, MessageKey.id: UUID().uuidString,
                  MessageKey.sentAt: Date().timeIntervalSince1970],
                 label: "Speed", sentAt: Date())
    }

    /// Tell the watch to stop whatever it is playing (used to switch a pattern off).
    func sendStop() {
        send(name: MessageKey.stopCommand, label: "Stop")
    }

    private func send(name: String, label: String, interval: TimeInterval? = nil) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            lastResult = .failed("Session not activated yet")
            return
        }

        let sentAt = Date()
        // Only simple types (String, Double…) are allowed in this dictionary.
        var payload: [String: Any] = [
            MessageKey.pattern: name,
            MessageKey.id: UUID().uuidString,
            MessageKey.sentAt: sentAt.timeIntervalSince1970,
        ]
        if let interval { payload[MessageKey.interval] = interval }

        if session.isReachable {
            // Fast path: the watch app is running, deliver immediately.
            lastResult = .sending(label)
            sendLive(payload, label: label, sentAt: sentAt)
        } else {
            // Slow path: queue it. The system delivers it when the watch app next runs.
            session.transferUserInfo(payload)
            lastResult = .queued(label)
        }
    }

    /// Copies the session's current state into our published properties.
    private func refreshStatus() {
        let session = WCSession.default
        isActivated = session.activationState == .activated
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }

    /// `sendMessage` calls its handlers on a background thread. This function is
    /// `nonisolated` so the handlers are allowed to run there; they then hop back
    /// to the main thread before touching anything the UI reads.
    private nonisolated func sendLive(_ payload: [String: Any], label: String, sentAt: Date) {
        WCSession.default.sendMessage(payload) { _ in
            // The watch replied: measure how long the round trip took.
            let roundTrip = Date().timeIntervalSince(sentAt)
            Task { @MainActor in
                self.lastResult = .delivered(label, roundTrip: roundTrip)
            }
        } errorHandler: { error in
            let message = error.localizedDescription
            Task { @MainActor in
                self.lastResult = .failed(message)
            }
        }
    }
}

// MARK: - WCSessionDelegate
// These are called by the system on a background thread, so each one hops to
// the main thread before updating the published properties.

extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in
            self.refreshStatus()
            if let message {
                self.lastResult = .failed(message)
            }
        }
    }

    /// The watch sent us a pattern to play, or "stop".
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        // Answer straight away so the watch knows it arrived.
        replyHandler(["receivedAt": Date().timeIntervalSince1970])

        let patternName = message[MessageKey.pattern] as? String
        Task { @MainActor in
            if patternName == MessageKey.stopCommand {
                self.lastResult = .received("Stop")
                self.received.send(nil)
            } else if let patternName, let pattern = Pattern(rawValue: patternName) {
                self.lastResult = .received(pattern.title)
                self.received.send(pattern)
            } else {
                self.lastResult = .failed("The watch sent an unknown pattern")
            }
        }
    }

    /// Paired / watch app installed changed.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshStatus() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshStatus() }
    }

    /// The user is switching to a different Apple Watch.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.refreshStatus() }
    }

    /// The switch to another watch finished: activate again to connect to the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        Task { @MainActor in self.refreshStatus() }
    }
}
