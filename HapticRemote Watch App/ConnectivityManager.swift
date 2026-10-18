//
//  ConnectivityManager.swift
//  HapticRemote Watch App
//
//  Receives patterns from the iPhone through WatchConnectivity (WCSession)
//  and hands them to the HapticPlayer. It can also do the opposite: send a
//  pattern to the iPhone, so the watch works as the remote.
//

import Combine
import Foundation
import SwiftUI
import WatchConnectivity

final class ConnectivityManager: NSObject, ObservableObject {
    @Published var isActivated = false
    @Published var isReachable = false

    /// Title of the last pattern we received, shown in the UI.
    @Published var lastPatternName: String?

    /// SF Symbol (the arrow) that goes with it.
    @Published var lastPatternSymbol: String?

    /// Background colour that goes with it (none after "stop").
    @Published var lastPatternColor: Color?

    /// The pattern the watch's own buttons switched on at the iPhone (nil = none).
    @Published var remotePattern: Pattern?

    /// Why the last send to the iPhone did not work, shown under the buttons.
    @Published var sendError: String?

    private let player: HapticPlayer

    init(player: HapticPlayer) {
        self.player = player
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func refreshStatus() {
        isActivated = WCSession.default.activationState == .activated
        isReachable = WCSession.default.isReachable
    }

    // MARK: - Sending to the iPhone

    /// A button on the watch was pressed. Every button is a switch: the first
    /// press starts the pattern on the iPhone, the second press stops it.
    func toggleOnPhone(_ pattern: Pattern) {
        if remotePattern == pattern {
            remotePattern = nil
            send(name: MessageKey.stopCommand)
        } else {
            remotePattern = pattern
            send(name: pattern.rawValue)
        }
    }

    private func send(name: String) {
        let session = WCSession.default
        // Only live messages are used here. A direction that arrives minutes
        // late is worse than one that does not arrive at all.
        guard session.activationState == .activated, session.isReachable else {
            remotePattern = nil
            sendError = "iPhone not reachable"
            return
        }
        sendError = nil
        sendLive([
            MessageKey.pattern: name,
            MessageKey.id: UUID().uuidString,
            MessageKey.sentAt: Date().timeIntervalSince1970,
        ])
    }

    /// `sendMessage` calls its handlers on a background thread. This function is
    /// `nonisolated` so the handlers are allowed to run there; the error handler
    /// hops back to the main thread before touching anything the UI reads.
    private nonisolated func sendLive(_ payload: [String: Any]) {
        WCSession.default.sendMessage(payload) { _ in
            // The iPhone answered, nothing more to do.
        } errorHandler: { error in
            let message = error.localizedDescription
            Task { @MainActor in
                self.remotePattern = nil
                self.sendError = message
            }
        }
    }

    // MARK: - Receiving from the iPhone

    /// Called on the main thread for every pattern that arrives, live or queued.
    private func handle(patternName: String?, interval: TimeInterval? = nil) {
        // The speed of Go straight: with a pattern (navigation started), on its
        // own (a turn is getting closer), or neither (back to the normal speed).
        player.forwardInterval = interval
        if patternName == nil, interval != nil { return }

        // The iPhone is in charge again, so none of the watch's buttons is "on".
        remotePattern = nil

        // The iPhone switched the pattern off.
        if patternName == MessageKey.stopCommand {
            lastPatternName = "Stopped"
            lastPatternSymbol = "stop.fill"
            lastPatternColor = nil
            player.stop()
            return
        }
        guard let patternName, let pattern = Pattern(rawValue: patternName) else {
            lastPatternName = "Unknown pattern"
            lastPatternSymbol = "questionmark"
            lastPatternColor = nil
            return
        }
        lastPatternName = pattern.title
        lastPatternSymbol = pattern.symbol
        lastPatternColor = pattern.color
        player.play(pattern)
    }
}

// MARK: - WCSessionDelegate
// These are called by the system on a background thread, so each one hops to
// the main thread before touching the player or the published properties.

extension ConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.refreshStatus() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshStatus() }
    }

    /// Live message (`sendMessage` on the iPhone). This is the fast path.
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        // Answer straight away so the iPhone can measure the round-trip time.
        replyHandler(["receivedAt": Date().timeIntervalSince1970])

        let patternName = message[MessageKey.pattern] as? String
        let interval = message[MessageKey.interval] as? TimeInterval
        Task { @MainActor in self.handle(patternName: patternName, interval: interval) }
    }

    /// Queued message (`transferUserInfo` on the iPhone). Arrives late, when the
    /// watch was not reachable at the moment of sending.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let patternName = userInfo[MessageKey.pattern] as? String
        Task { @MainActor in self.handle(patternName: patternName) }
    }
}
