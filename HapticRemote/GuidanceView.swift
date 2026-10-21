//in the dothe make
//  GuidanceView.swift
//  HapticRemote (iPhone)
//
//  The navigation screens ("09 – 13 Navigating" and "14 Arrived" in Figma),
//  opened from the Nearest stop card on the home screen.
//
//  The screen follows a real walking route to Centraal (RouteNavigator): the
//  user's GPS position picks the direction, which vibrates on the phone and,
//  when it is reachable, on the watch too.
//
//  The watch can still take over, for a test with a participant: the first
//  remote button pressed on the watch switches the screen to that direction
//  (the home screen plays the vibration), and from then on only the watch
//  drives it, with the sample distances below. The departures are sample
//  content too.
//
//  Simulated walk (from Settings): the same screen, but the user is moved
//  along the route with the Back and Forward buttons instead of by walking.
//  The compass is off unless switched on, so the signals come from the route.
//
//  Map simulation (from Settings): the user is the pin in the middle of a
//  bigger map, moved by dragging the map, anywhere, on the route or off it.
//

import AVFoundation
import Combine
import CoreLocation
import MapKit
import SwiftUI

/// What the navigation screen shows for one direction.
private struct GuidanceStep {
    let title: String
    /// The line under the title, e.g. "for 80 m".
    let detail: String
    /// What is left of the route, e.g. "120 m · 2 min
    let remaining: String
    /// Spoken by "Where am I", e.g. "120 metres, about 2 minutes".
    let remainingSpoken: String
    /// How much of the route is done, 0 to 1.
    let progress: Double
    /// Said out loud when the step comes up (if the voice is on).
    let voiceLine: SpokenLine
        
    /// Small extra label under the detail, e.g. "Fastest pulse".
    var chip: String? = nil
    /// When something went wrong: a sentence or two on what happened, under
    /// the detail, so the user knows why there are no directions.
    var explanation: String? = nil

    /// The sample step for a direction picked on the watch.
    static func of(_ pattern: Pattern) -> GuidanceStep {
        switch pattern {
        case .forward:
            GuidanceStep(title: "Go straight", detail: "for 80 m", remaining: "120 m · 2 min",
                         remainingSpoken: "120 metres, about 2 minutes", progress: 5 / 64,
                         voiceLine: "Go straight for 80 metres")
        case .left:
            GuidanceStep(title: "Turn left", detail: "in 20 m", remaining: "60 m · 1 min",
                         remainingSpoken: "60 metres, about 1 minute", progress: 34 / 64,
                         voiceLine: "Turn left in 20 metres")
        case .right:
            GuidanceStep(title: "Turn right", detail: "in 10 m", remaining: "25 m · 1 min",
                         remainingSpoken: "25 metres, about 1 minute", progress: 52 / 64,
                         voiceLine: "Turn right in 10 metres")
        case .turnAround:
            GuidanceStep(title: "Turn around", detail: "Wrong way", remaining: "30 m · 1 min",
                         remainingSpoken: "30 metres, about 1 minute", progress: 49 / 64,
                         voiceLine: "Wrong way. Turn around")
        case .almostThere:
            GuidanceStep(title: "Almost there", detail: "Centraal is 15 m ahead, on your left",
                         remaining: "15 m · under 1 min", remainingSpoken: "15 metres, under a minute",
                         progress: 60 / 64,
                         voiceLine: "Almost there. \(dutch: "Centraal") is 15 metres ahead, on your left",
                         chip: "Fastest pulse")
        case .signalLost:
            // Not in the Figma designs; the tutorial's wording.
            GuidanceStep(title: "Signal lost", detail: "Keep walking straight", remaining: "—",
                         remainingSpoken: "unknown until the signal is back", progress: 49 / 64,
                         voiceLine: "Signal lost. Keep walking straight")
        case .arrived:
            GuidanceStep(title: "You've arrived", detail: "Centraal tram stop", remaining: "0 m",
                         remainingSpoken: "nothing, you are there", progress: 1,
                         voiceLine: "You've arrived at \(dutch: "Centraal") tram stop")
        }
    }

    /// The step for where the user really is on the route.
    static func live(_ navigator: RouteNavigator, to name: String) -> GuidanceStep {
        switch navigator.status {
        case .locating where navigator.notice == .noLocationYet:
            return notice(title: "No GPS signal", detail: "Try moving outside",
                          explanation: "Your phone can't find where you are yet. Indoors or between tall buildings, the GPS can't get through. The route starts as soon as your phone finds you.")
        case .locating:
            return notice(title: "Finding you", detail: "One moment",
                          explanation: "Waiting for the GPS to find you.", remainingSpoken: "not known yet")
        case .routing:
            return notice(title: "Finding your route", detail: "One moment",
                          explanation: "Asking Apple Maps for a walking route to \(name).", remainingSpoken: "not known yet")
        case .failed(let problem):
            return failure(problem, to: name)
        case .guiding:
            break
        }

        let next = Distance(navigator.distanceToNext)
        let left = Distance(navigator.remaining)
        let remaining = "\(left.short) · \(left.minutes)"
        let remainingSpoken = "\(left.spoken), \(left.minutesSpoken)"
        let progress = navigator.progress

        // No signal says more than being off the route: where the user is isn't known.
        if navigator.pattern != .signalLost, navigator.pattern != .arrived {
            switch navigator.notice {
            case .offRoute:
                return notice(title: "Off route", detail: "Finding a new route",
                              explanation: "You're more than \(Int(navigator.rerouteDistance)) m from the route, so Tandem is getting a new one from here. Until it comes, the last direction keeps playing.",
                              remaining: remaining, remainingSpoken: remainingSpoken, progress: progress)
            case .offRouteNoNewRoute(let problem):
                let why = switch problem {
                case .noConnection: "There's no internet connection, so Tandem can't get a new route."
                case .noWalkingRoute: "Apple Maps has no walking route from here."
                default: "Apple Maps isn't answering right now."
                }
                return notice(title: "Off route", detail: "Walk back to the route",
                              explanation: "\(why) Use the map to find your way back to the route, and the directions pick up from there. Tandem keeps trying for a new route every few seconds.",
                              remaining: remaining, remainingSpoken: remainingSpoken, progress: progress)
            case .noLocationYet, nil:
                break
            }
        }

        switch navigator.pattern ?? .forward {
        case .forward:
            return GuidanceStep(title: "Go straight", detail: "for \(next.short)", remaining: remaining,
                                remainingSpoken: remainingSpoken, progress: progress,
                                voiceLine: "Go straight for \(next.spoken)")
        case .left, .right:
            let side = navigator.pattern == .left ? "left" : "right"
            // With the compass: where the way on is, as a clock position.
            if let clock = navigator.clockPosition {
                return GuidanceStep(title: "Turn \(side)", detail: "The way on is at \(clock) o'clock",
                                    remaining: remaining, remainingSpoken: remainingSpoken, progress: progress,
                                    voiceLine: "Turn \(side). The way on is at \(clock) o'clock")
            }
            let when = navigator.distanceToNext < 5 ? "now" : "in \(next.short)"
            let whenSpoken = navigator.distanceToNext < 5 ? "now" : "in \(next.spoken)"
            return GuidanceStep(title: "Turn \(side)", detail: when, remaining: remaining,
                                remainingSpoken: remainingSpoken, progress: progress,
                                voiceLine: "Turn \(side) \(whenSpoken)")
        case .turnAround:
            let detail = navigator.clockPosition == nil ? "Wrong way" : "The way on is behind you"
            return GuidanceStep(title: "Turn around", detail: detail, remaining: remaining,
                                remainingSpoken: remainingSpoken, progress: progress,
                                voiceLine: "Turn around. \(detail)")
        case .almostThere:
            return GuidanceStep(title: "Almost there", detail: "\(name) is \(left.short) ahead",
                                remaining: remaining, remainingSpoken: remainingSpoken, progress: progress,
                                voiceLine: "Almost there. \(dutch: name) is \(left.spoken) ahead",
                                chip: "Fastest pulse")
        case .signalLost:
            return GuidanceStep(title: "Signal lost", detail: "Keep walking straight", remaining: "—",
                                remainingSpoken: "unknown until the signal is back", progress: progress,
                                voiceLine: "Signal lost. Keep walking straight",
                                explanation: "Your phone hasn't had GPS for 15 seconds. Tandem follows your steps along the route for now, and the directions come back with the signal.")
        case .arrived:
            return GuidanceStep(title: "You've arrived", detail: name, remaining: "0 m",
                                remainingSpoken: "nothing, you are there", progress: 1,
                                voiceLine: "You've arrived at \(dutch: name)")
        }
    }

    /// A screen with no direction on it: the title and detail are said, the
    /// explanation is shown (and read by VoiceOver with the rest).
    private static func notice(title: String, detail: String, explanation: String,
                               remaining: String = "—", remainingSpoken: String = "not known",
                               progress: Double = 0) -> GuidanceStep {
        GuidanceStep(title: title, detail: detail, remaining: remaining, remainingSpoken: remainingSpoken,
                     progress: progress, voiceLine: "\(title). \(detail)", explanation: explanation)
    }

    /// Why there is no route, and what to do about it.
    private static func failure(_ problem: RouteNavigator.Problem, to name: String) -> GuidanceStep {
        switch problem {
        case .locationOff:
            notice(title: "Location is off", detail: "Turn it on in Settings",
                   explanation: "Tandem needs your location to guide you. In Settings, go to Privacy & Security, Location Services, Tandem, and choose While Using the App.")
        case .preciseLocationOff:
            notice(title: "Precise Location is off", detail: "Turn it on in Settings",
                   explanation: "An approximate location can be hundreds of metres off, too far to find a turn. In Settings, go to Privacy & Security, Location Services, Tandem, and turn on Precise Location.")
        case .noConnection:
            notice(title: "No internet connection", detail: "Can't get a route",
                   explanation: "The walking route comes from Apple Maps, which needs the internet. Check Wi-Fi or mobile data, then try again.")
        case .noWalkingRoute:
            notice(title: "No walking route", detail: "Can't walk to \(name) from here",
                   explanation: "Apple Maps found no way to walk there from where you are. Try again, or choose another stop.")
        case .mapsUnavailable:
            notice(title: "Can't find a route", detail: "Apple Maps isn't answering",
                   explanation: "Apple Maps didn't send a route. Try again in a moment.")
        }
    }
}

/// A distance as shown and as spoken: 1 m steps under 20 m, 5 m steps up to
/// 50 m, 10 m steps further away, kilometres from 1 km.
private struct Distance {
    let short: String
    let spoken: String
    let minutes: String
    let minutesSpoken: String

    init(_ metres: Double) {
        if metres >= 1000 {
            let km = (metres / 100).rounded() / 10
            short = "\(km.formatted()) km"
            spoken = "\(km.formatted()) kilometres"
        } else {
            let step: Double = metres < 20 ? 1 : metres < 50 ? 5 : 10
            let rounded = Int(max(step, (metres / step).rounded() * step))
            short = "\(rounded) m"
            spoken = "\(rounded) metres"
        }
        // At walking speed, about 1.3 metres a second.
        let wholeMinutes = Int((metres / 1.3 / 60).rounded())
        if wholeMinutes < 1 {
            minutes = "under 1 min"
            minutesSpoken = "under a minute"
        } else {
            minutes = "\(wholeMinutes) min"
            minutesSpoken = wholeMinutes == 1 ? "about 1 minute" : "about \(wholeMinutes) minutes"
        }
    }
}

struct GuidanceView: View {
    /// Where the route goes. The watch's sample route always goes to Centraal.
    let destination: Destination
    @ObservedObject var connectivity: ConnectivityManager
    /// Plays the vibration (the home screen starts it); the dial flashes along.
    @ObservedObject var phoneHaptics: PhoneHapticPlayer

    /// A simulated walk: Back and Forward buttons move the user along the
    /// route, or dragging the map does. Nil on a real walk.
    let simulation: RouteNavigator.Simulation?
    private var isSimulated: Bool { simulation != nil }
    /// A recorded walk played back in place of the GPS, the steps and the
    /// compass (Settings, Recorded walks). Nil on a real walk.
    let replay: TripReplay?
    /// A simulated walk only: starts this far along the route, 0 to 1, once
    /// the route is in (the "Mid-route" preview).
    let startsPartWay: Double?
    /// Going to a stop, what can be caught there has been said (once a walk).
    @State private var saidDepartures = false
    /// The departures are being said: a new direction (or distance) waits
    /// until they are done, so they're heard to the end even while the user
    /// is still turning to face the right way.
    @State private var readingDepartures = false
    /// What VoiceOver was given to say, to know when it's done with it.
    @State private var departuresAnnouncement: String?
    /// A direction was held back meanwhile: it is said after them.
    @State private var missedDirection = false
    /// What can be caught at the stop, shown in the next step card's place
    /// while it is being said.
    @State private var catchable: Catchable?
    struct Catchable {
        let minutesAway: Int
        /// Each with the minutes to wait once there.
        let departures: [(departure: Transit.Departure, wait: Int)]
    }

    init(destination: Destination = .centraal, simulation: RouteNavigator.Simulation? = nil,
         replay: TripReplay? = nil, startsPartWay: Double? = nil,
         connectivity: ConnectivityManager, phoneHaptics: PhoneHapticPlayer) {
        self.destination = destination
        self.simulation = simulation
        self.replay = replay
        self.startsPartWay = startsPartWay
        self.connectivity = connectivity
        self.phoneHaptics = phoneHaptics
        _navigator = StateObject(wrappedValue: RouteNavigator(destination: destination.coordinate,
                                                              simulation: simulation, replay: replay))
    }

    #if DEBUG
    /// For Xcode previews: the screen for a navigator frozen in one state.
    init(previewing navigator: RouteNavigator) {
        self.destination = .centraal
        self.simulation = nil
        self.replay = nil
        self.startsPartWay = nil
        self.connectivity = ConnectivityManager()
        self.phoneHaptics = PhoneHapticPlayer()
        _navigator = StateObject(wrappedValue: navigator)
    }
    #endif

    /// A real walk on the real sensors: recorded, if that is on in Settings.
    private var isRealWalk: Bool { !isSimulated && replay == nil }
    @AppStorage(TripRecorder.settingKey) private var recordsWalks = true
    @State private var recorder: TripRecorder?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Follows the user's position along the real route.
    @StateObject private var navigator: RouteNavigator
    /// Set once the watch has taken over: the direction it picked last.
    @State private var remotePattern: Pattern?
    /// Off at the start: the vibration leads, the voice is opt-in.
    /// Kept between walks; also in Settings. Off at first: the vibration leads.
    @AppStorage(GuidanceSettings.voiceKey) private var voiceOn = false
    /// The iPhone's own vibration (Settings). Off, the dial still flashes along.
    @AppStorage(GuidanceSettings.vibrationKey) private var vibrationOn = true
    /// The dial is being held: the voice speaks meanwhile, the setting left as it is.
    @State private var voiceHeld = false
    /// Going to a stop, say what can be caught there (Settings).
    @AppStorage(GuidanceSettings.departuresKey) private var announcesDepartures = true
    /// The voice speaks: switched on, or the dial held.
    private var speaksAloud: Bool { voiceOn || voiceHeld }
    @State private var voice = GuidanceVoice()
    /// The chime for turning back into the Go straight arc.
    @State private var backOnCourse = BackOnCourseSound()
    /// True while a finger holds the dial down (past `dialHoldDuration`).
    @GestureState private var holdingDial = false
    /// The next step card's height, for where the map's compass goes under it.
    @State private var cardHeight: CGFloat = 70
    /// Set when a hold on the dial starts: the tap that comes with lifting the
    /// finger mustn't say the direction again. Set at the start, because the
    /// tap arrives before the hold's end is noticed.
    @State private var dialWasHeld = false
    /// Which way the phone points, for the pointer round the dial. In @State,
    /// so only the pointer (which observes it) redraws on a new reading.
    @State private var heading = HeadingTracker()
    /// Passes compass readings on to the navigator.
    @State private var headingFeed: AnyCancellable?
    /// Simulated walk: whether the real compass picks the direction signals.
    /// Off at the start, for trying it out sitting down.
    @State private var simulationUsesCompass = false
    /// Metres ahead on the route the dial's pointer aims; set in Settings.
    @AppStorage("dialLookAhead") private var lookAhead = RouteNavigator.defaultLookAhead
    /// Metres off the route before a new one is fetched; set in Settings.
    @AppStorage("rerouteDistance") private var rerouteDistance = RouteNavigator.defaultRerouteDistance
    /// The compass calibration that is running, if any.
    @State private var calibration: Task<Void, Never>?
    /// Shown on the Calibrate button. Kept here because this view doesn't
    /// observe `heading` (see above).
    @State private var isCalibrating = false
    /// "End guidance?" is up, in place of the toolbar.
    @State private var confirmingEnd = false
    /// "End guidance" was picked in the sheet: navigation ends once the
    /// sheet has gone, so the screen isn't closed underneath it.
    @State private var endsAfterSheet = false
    /// Set when End was held down: it ends straight away, so the tap that
    /// follows when the finger lifts mustn't open the question as well.
    @State private var endedByHold = false
    /// True while a finger is down on End.
    @GestureState private var holdingEnd = false
    /// How full End's red countdown is, 0 to 1: it fills while End is held,
    /// and empties again if the finger lifts too early.
    @State private var endHoldProgress: CGFloat = 0
    /// The turn being counted down to (by where it is along the route), the
    /// last distance said for it, and the direction said last.
    @State private var countdown: (turn: Double, mark: Double, pattern: Pattern?)?

    /// A new route came in under a second ago: its announcement says the direction.
    private var justRerouted: Bool {
        navigator.reroutedAt.map { Date.now.timeIntervalSince($0) < 0.7 } ?? false
    }

    /// The direction on screen; nil while the route is still being found.
    private var pattern: Pattern? { remotePattern ?? navigator.pattern }

    private var step: GuidanceStep {
        if let remotePattern { .of(remotePattern) } else { .live(navigator, to: destination.name) }
    }

    var body: some View {
        ZStack {
            if pattern == .arrived {
                ArrivedView(destination: remotePattern == nil ? destination : .centraal, onDone: end)
                    .transition(.opacity)
            } else {
                navigating
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: pattern == .arrived)
        .background(Palette.background)
        .preferredColorScheme(.dark)
        // While the departures are said: a double tap anywhere skips them.
        // Alongside the buttons' own taps, and only then.
        .simultaneousGesture(TapGesture(count: 2).onEnded { skipDepartures() },
                             including: readingDepartures ? .all : .subviews)
        // With VoiceOver, a double tap presses what it's on: the two-finger
        // double tap (Magic Tap) skips them instead.
        .accessibilityAction(.magicTap) { skipDepartures() }
        // The watch switched the direction: from now on, the watch drives.
        .onReceive(connectivity.received) { received in
            guard let received, received != remotePattern else { return }
            navigator.stop()
            // The watch's sample route: Go straight at its normal speed.
            phoneHaptics.forwardInterval = nil
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                remotePattern = received
            }
            announce(GuidanceStep.of(received).voiceLine)
        }
        // The route picked a new direction: say it and play it, here and on the watch.
        .onChange(of: navigator.pattern) { old, new in
            guard remotePattern == nil, let new else { return }
            // Just rerouted: "New route" says it in a moment.
            if !justRerouted { announce(GuidanceStep.live(navigator, to: destination.name).voiceLine) }
            // Facing away, the blue dot came back into the green arc: a chime
            // to say it's the right way now. (Only with the compass: without
            // it there is no dot.)
            if let old, [.left, .right, .turnAround].contains(old), [.forward, .almostThere].contains(new),
               heading.degrees != nil {
                backOnCourse.play()
            }
            // Guidance has started: going to a stop, say what can be caught there.
            if old == nil, new != .arrived, destination.isStop, announcesDepartures, !saidDepartures {
                saidDepartures = true
                Task { await announceDepartures() }
            }
            // That line said the distance, so the countdown doesn't say it again.
            countDown(speaks: false)
            phoneHaptics.forwardInterval = navigator.goStraightInterval
            phoneHaptics.play(new, vibrate: vibrationOn, once: new == .arrived)
            if connectivity.isReachable { connectivity.send(new, interval: navigator.goStraightInterval) }
        }
        .onChange(of: navigator.distanceToNext) { countDown(speaks: true) }
        // Off route, a new route failing, no GPS at the start: say so, as the
        // direction on screen is gone or may be stale.
        .onChange(of: navigator.notice) { old, notice in
            guard remotePattern == nil else { return }
            let step = GuidanceStep.live(navigator, to: destination.name)
            if notice == .noLocationYet {
                announce("\(step.voiceLine). \(step.explanation ?? "")")
            } else if notice != nil {
                announce(step.voiceLine)
            } else if old != .noLocationYet, !justRerouted, navigator.status == .guiding,
                      navigator.pattern != .signalLost {
                // Walked back onto the route.
                announce("Back on the route. \(step.voiceLine)")
            }
        }
        // A new route: said once its first direction has settled, with it.
        .onChange(of: navigator.reroutedAt) { _, at in
            guard remotePattern == nil, at != nil else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard navigator.status == .guiding, navigator.pattern != .arrived else { return }
                announce("New route. \(GuidanceStep.live(navigator, to: destination.name).voiceLine)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.announcementDidFinishNotification)) { note in
            let said = note.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
            if readingDepartures, said != nil, said == departuresAnnouncement { doneReadingDepartures() }
        }
        // A turn is getting closer: Go straight taps faster, here and on the watch.
        .onChange(of: navigator.goStraightInterval) { _, interval in
            guard remotePattern == nil else { return }
            phoneHaptics.forwardInterval = interval
            if pattern == .forward { connectivity.sendInterval(interval) }
        }
        .onChange(of: navigator.status) { _, status in
            // No route: what happened too, as there is nothing else to go on.
            if case .failed = status {
                let step = GuidanceStep.live(navigator, to: destination.name)
                announce("\(step.voiceLine). \(step.explanation ?? "")")
            }
            if status == .guiding, let startsPartWay, navigator.simulatedAlong == 0 {
                navigator.simulateWalk(to: navigator.routeLength * startsPartWay)
            }
        }
        // "End guidance?": the system sheet, over the whole screen, so nothing
        // underneath moves. Swiping it down or tapping outside is Keep going.
        .sheet(isPresented: $confirmingEnd, onDismiss: {
            if endsAfterSheet { end() }
        }) {
            EndGuidanceSheet(destination: remotePattern == nil ? destination.name : "Centraal",
                             distance: remotePattern != nil ? Distance(60)
                                 : navigator.status == .guiding ? Distance(navigator.remaining) : nil,
                             onKeepGoing: { confirmingEnd = false },
                             onEnd: {
                                 endsAfterSheet = true
                                 confirmingEnd = false
                             })
        }
        // The direction of travel keeps the compass's north right.
        .onChange(of: navigator.lastLocation) { _, location in
            if let location, isRealWalk { heading.walked(location) }
        }
        .onChange(of: simulationUsesCompass) { _, on in
            if on { heading.start() } else { heading.stopAndForget() }
        }
        .onAppear {
            voice.voiceSession()
            backOnCourse.start()
            navigator.setLookAhead(lookAhead)
            navigator.setRerouteDistance(rerouteDistance)
            if isRealWalk, recordsWalks, recorder == nil,
               let recorder = TripRecorder(destination: destination, lookAhead: lookAhead,
                                           rerouteDistance: rerouteDistance) {
                self.recorder = recorder
                navigator.recorder = recorder
                heading.recorder = recorder
            }
            // Replaying: the walk's compass, not this phone's.
            replay?.onHeading = { [heading] in heading.play($0) }
            navigator.start()
            if isRealWalk || (isSimulated && simulationUsesCompass) { heading.start() }
            // The compass picks the direction signals; not while it is being
            // calibrated, when the phone is waved about.
            headingFeed = heading.$degrees.combineLatest(heading.$isCalibrating)
                .sink { [navigator] degrees, calibrating in
                    navigator.setHeading(calibrating ? nil : degrees)
                }
            // The screen stays on: iOS pauses the location and the haptics when it locks.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            calibration?.cancel()
            navigator.stop()
            heading.stop()
            recorder?.finish(navigator.pattern == .arrived ? "arrived" : "closed")
            recorder = nil
            backOnCourse.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Navigating

    private var navigating: some View {
        // Never scrolls: the map and the dial shrink to fit, so the toolbar
        // (End above all) is always on screen. The map runs up under the
        // status bar, edge to edge, with the next step card on it; the toolbar
        // ends 16 pt above the bottom of the screen, past the home indicator.
        // Measured inside the safe area (ignoring it would make the insets 0),
        // then laid out over the whole screen.
        // The simulated walk: the same screen at full size, the Forward and
        // Back controls added above the toolbar, scrolling to them.
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            let bottom = proxy.safeAreaInsets.bottom
            if simulation == .walk {
                ScrollView {
                    VStack(spacing: 14) {
                        if showsMap {
                            mapWithCard(top: top, height: top + cardGap + cardHeight + 150)
                        } else {
                            topCard
                                .padding(.top, top + cardGap)
                                .padding(.horizontal, 16)
                        }

                        Group {
                            navigatingBody
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .ignoresSafeArea(edges: .top)
            } else {
                VStack(spacing: 14) {
                    if showsMap {
                        // After the dial, before the spacers; dragging the map to
                        // move, the map is the control, so it comes first.
                        mapWithCard(top: top)
                            .layoutPriority(simulation == .drag ? 2 : 0.5)
                    } else {
                        topCard
                            .padding(.top, top + cardGap)
                            .padding(.horizontal, 16)
                    }

                    Group {
                        navigatingBody
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
                .frame(width: proxy.size.width, height: proxy.size.height + top + bottom)
                .offset(y: -top)
            }
        }
        // The background washed in the signal's colour, like the tutorial's signal screens.
        .background { TutorialBackground(tint: dialSignal.color) }
        // The wash fades to the next signal's colour along with the dial.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: pattern)
    }

    /// Everything under the map: the dial and the direction, the simulation
    /// controls and the toolbar. Laid out in the screen's stack, so the dial's
    /// priority counts against the map's.
    @ViewBuilder
    private var navigatingBody: some View {
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                // Always `dialSize`: the map gives way to it.
                // A tap says the direction again, even with the voice off.
                // Holding it turns the voice on until the finger lifts.
                GeometryReader { proxy in
                    let size = min(dialSize, proxy.size.width, proxy.size.height)
                    Button {
                        if dialWasHeld {
                            dialWasHeld = false
                            return
                        }
                        say(step.voiceLine, force: true)
                    } label: {
                        dial(size: size)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        // Held past the duration, then until the finger lifts (the drag).
                        LongPressGesture(minimumDuration: Self.dialHoldDuration)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .updating($holdingDial) { value, state, _ in
                                if case .second(true, _) = value { state = true }
                            }
                    )
                    .accessibilityLabel("Say the direction")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: dialSize)
                .onChange(of: holdingDial) { _, holding in
                    if holding { startHeldVoice() } else { endHeldVoice() }
                }

                // A new id per direction, so the text cross-fades.
                VStack(spacing: 14) {
                    // The title and its subtitle closer together, as one.
                    VStack(spacing: 2) {
                        Text(step.title)
                            .font(.atkinson(44, .extraBold, relativeTo: .largeTitle))
                            .tracking(-0.88)
                            .foregroundStyle(Palette.text)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text(step.detail)
                            .font(.atkinson(22, relativeTo: .title2))
                            .foregroundStyle(Palette.instruction)
                            .multilineTextAlignment(.center)
                    }

                    if let explanation = step.explanation {
                        Text(explanation)
                            .font(.atkinson(17, relativeTo: .body))
                            .foregroundStyle(Palette.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    }

                    if let chip = step.chip {
                        Text(chip)
                            .font(.atkinson(15, .bold, relativeTo: .subheadline))
                            .foregroundStyle(Palette.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Palette.text.opacity(0.16), in: Capsule())
                    }
                }
                .id(screenKey)
                .transition(.opacity)
                .accessibilityElement(children: .combine)

                // No route: what can be done about it, besides End.
                if remotePattern == nil, case .failed(let problem) = navigator.status {
                    if problem.needsSettings {
                        PrimaryButton("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else if problem.canRetry {
                        PrimaryButton("Try again", action: navigator.retry)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: screenKey)
            // The dial gets its room before the map and the spacers.
            .layoutPriority(1)

            Spacer(minLength: 0)

            if let replay, remotePattern == nil {
                ReplayBar(replay: replay)
            }

            if showsSimulationControls {
                if simulation == .drag {
                    DragControls(usesCompass: $simulationUsesCompass)
                } else {
                    SimulationControls(navigator: navigator, usesCompass: $simulationUsesCompass)
                }
            }

            toolbar
    }

    /// Changes with each direction and each screen without one (finding the
    /// route, no route, off route), so the text cross-fades between them.
    private var screenKey: String { "\(pattern.map { "\($0)" } ?? "none") \(step.title)" }

    /// The small map, only on the real route once it is in (the watch's
    /// sample route isn't a real one).
    private var showsMap: Bool { remotePattern == nil && navigator.routeLine != nil }

    private var showsSimulationControls: Bool {
        isSimulated && remotePattern == nil && navigator.status == .guiding
    }

    /// The dial's size: the same with the map as without; smaller only beside
    /// the map simulation's controls (the simulated walk scrolls instead).
    /// Smaller too with an explanation under the text, to leave it room.
    private var dialSize: CGFloat {
        showsSimulationControls && simulation == .drag ? 170 : step.explanation != nil ? 200 : 280
    }

    /// The same dial throughout, so the pointer keeps turning smoothly when
    /// the signal changes; its colour and arrow change in place.
    private func dial(size: CGFloat) -> some View {
        DirectionDial(signal: dialSignal, isLit: phoneHaptics.isLit,
                      ringSwell: phoneHaptics.ringSwell, size: size)
            .overlay {
                // Only on the real route: the watch's sample route has no place to point at.
                if remotePattern == nil, navigator.status == .guiding, pattern != .arrived,
                   let bearing = navigator.bearingAhead {
                    let isFacing = pattern == .forward || pattern == .almostThere
                    StraightZone(halfAngle: navigator.straightAngle, size: size,
                                 isFacing: isFacing)
                    TurnPointer(heading: heading, bearing: bearing, size: size,
                                straightAngle: navigator.straightAngle, isFacing: isFacing)
                }
            }
            .accessibilityHidden(true)
    }

    /// The map from the top of the screen, edge to edge, with the next step
    /// card on it under the status bar. Below the card, up to 150 pt of map
    /// (250 to drag), smaller where the screen is short; with less than
    /// `minMapHeight`, only the card, as without a map.
    /// `height`: just this tall (in the simulated walk's scroll view, where
    /// there is no screen to fit).
    private func mapWithCard(top: CGFloat, height: CGFloat? = nil) -> some View {
        let cardBottom = top + cardGap + cardHeight
        return GeometryReader { proxy in
            ZStack(alignment: .top) {
                // Calibrate leaves the toolbar for the map once it shows: its
                // row's room counts as the map's, or with little to spare (a
                // simulated walk) the map would never show to make it.
                let room = proxy.size.height - cardBottom + (mapIsVisible ? 0 : calibrateRowHeight)
                let mapFits = room >= minMapHeight
                if mapFits {
                    routeMap(controlsTop: cardBottom + 8)
                        .overlay(alignment: .bottomLeading) {
                            calibrateButton
                                .padding(10)
                        }
                }
                Color.clear
                    .onChange(of: mapFits, initial: true) { _, fits in mapIsVisible = fits }
                topCard
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                    // Lifted off the map a little.
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    .padding(.top, top + cardGap)
                    .padding(.horizontal, 16)
            }
        }
        .frame(minHeight: height ?? cardBottom, maxHeight: height ?? cardBottom + (simulation == .drag ? 250 : 150))
    }

    /// The route close up around the user, turned to the way they face; or,
    /// dragging the map to move, a bigger one to drag. `controlsTop`: where
    /// the map's own buttons may start, under the card.
    private func routeMap(controlsTop: CGFloat) -> some View {
        Group {
            if simulation == .drag {
                DragMap(navigator: navigator, heading: heading, destination: destination,
                        controlsTop: controlsTop)
            } else {
                FollowMap(navigator: navigator, heading: heading, destination: destination,
                          controlsTop: controlsTop)
            }
        }
        .background(Palette.mapPanel)
        .overlay(alignment: .bottom) { mapProgress }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map of your route to \(destination.name)")
    }

    /// How much of the route is done: lilac along the map's bottom edge,
    /// its ends rounded off by the map's corners.
    private var mapProgress: some View {
        Rectangle()
            .fill(Palette.track)
            .frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Palette.accent)
                        .frame(width: proxy.size.width * step.progress)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: step.progress)
            .accessibilityHidden(true)
    }

    private let minMapHeight: CGFloat = 90
    /// From the bottom of the safe area's top (just under the Dynamic Island
    /// or the notch) to the next step card: a little above it, close under
    /// the island, clear of the status bar beside it.
    private let cardGap: CGFloat = -4

    /// Whether there is room for the map under the card. Calibrate is on the
    /// map then, and in the toolbar otherwise.
    @State private var mapIsVisible = false
    /// The toolbar's Calibrate row with the gap above it, while it is there.
    @State private var calibrateRowHeight: CGFloat = 0

    /// The compass and the GPS afresh. On the map's lower left corner.
    private var calibrateButton: some View {
        Button(action: recalibrate) {
            HStack(spacing: 6) {
                Image(systemName: "location.north.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .accessibilityHidden(true)
                Text(isCalibrating ? "Calibrating" : "Calibrate")
                    .font(.atkinson(14, .bold, relativeTo: .footnote))
                    .foregroundStyle(Palette.toolbarLabel)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .glassButtonBackground(tint: nil, fallback: Palette.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isCalibrating || remotePattern != nil || replay != nil)
        .accessibilityLabel(isCalibrating ? "Calibrating" : "Calibrate compass and location")
        .accessibilityHint("Then move the phone in a figure eight")
    }

    /// The dial of the tutorial signal with the same look (Almost there uses
    /// Go straight's arrow; Signal lost's while the route is being found).
    private var dialSignal: TutorialSignal {
        let look: Pattern = switch pattern {
        case .almostThere: .forward
        case nil: .signalLost
        case let pattern?: pattern
        }
        return TutorialSignal.all.first { $0.pattern == look } ?? TutorialSignal.all[2]
    }

    /// Where you're going, what's left, and (without the map) a small progress bar.
    /// The turn the top card shows: the next one on the real route, once it is
    /// in. Nil after the last turn (and on the watch's sample route), when the
    /// card shows the destination instead.
    private var upcomingTurn: RouteNavigator.Turn? {
        guard remotePattern == nil, navigator.status == .guiding, pattern != .arrived else { return nil }
        return navigator.nextTurn
    }

    /// Apple's instruction, e.g. "Turn left onto Damrak", else just the side.
    /// The side comes from the bend in the route line, as for the signals;
    /// Apple's text sometimes says the other side (seen on the simulated walk
    /// to Centraal), and then it isn't shown, so the card never contradicts
    /// the vibration.
    private static func title(for turn: RouteNavigator.Turn) -> String {
        let side = turn.isLeft ? "left" : "right"
        let text = turn.instructions.lowercased()
        let saysOtherSide = text.contains(turn.isLeft ? "right" : "left") && !text.contains(side)
        return turn.instructions.isEmpty || saysOtherSide ? "Turn \(side)" : turn.instructions
    }

    /// The next turn and how far off it is; after the last one, the
    /// destination and how far it is to go. The bar is the whole route.
    /// The next step, or while it is being said, what can be caught at the stop.
    @ViewBuilder
    private var topCard: some View {
        // One over the other while they swap; the card resizes from one's
        // height to the other's (Motion.cardResize, set where it changes).
        ZStack(alignment: .top) {
            if let catchable {
                catchableCard(catchable)
                    .transition(reduceMotion ? .identity : .textSwap)
            } else {
                destinationCard
                    .transition(reduceMotion ? .identity : .textSwap)
            }
        }
    }

    /// "At Nieuwezijds Kolk in 7 min", and a row a departure: its line's
    /// badge, where it goes, and the wait once there. A tap goes back to the
    /// next step. VoiceOver is reading the same out already.
    private func catchableCard(_ catchable: Catchable) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.cardResize) { self.catchable = nil }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("At \(destination.name) in \(catchable.minutesAway) min, you can catch")
                    .font(.atkinson(15, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.secondaryText)
                ForEach(catchable.departures, id: \.departure.id) { item in
                    HStack(spacing: 10) {
                        LineBadge(line: Transit.Line(mode: item.departure.mode, name: item.departure.line,
                                                     color: item.departure.color,
                                                     textColor: item.departure.textColor),
                                  minWidth: 36)
                        Text(item.departure.towards)
                            .font(.atkinson(17, .bold, relativeTo: .headline))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.wait <= 0 ? "on arrival" : "+\(item.wait) min")
                            .font(.atkinson(15, .bold, relativeTo: .subheadline))
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardGlass())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Departures at \(destination.name)")
        .accessibilityHint("Shows the next step again")
    }

    private var destinationCard: some View {
        let destinationName = remotePattern == nil ? destination.name : "Centraal"
        let turn = upcomingTurn
        let toTurn = Distance(navigator.distanceToNext)
        let turnTitle = turn.map(Self.title(for:))

        // What the icon, the title and the line under them show, so a change swaps them.
        let iconKey = turn.map { $0.isLeft ? "left" : "right" }
            ?? (destination.isStop || remotePattern != nil ? "stop" : "pin")
        let title = turnTitle ?? destinationName
        let detail = turn != nil ? "in \(toTurn.short)" : step.remaining

        return HStack(spacing: 12) {
            ZStack {
                Group {
                    if let turn {
                        Image(systemName: turn.isLeft ? "arrow.turn.up.left" : "arrow.turn.up.right")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(turn.isLeft ? Palette.left : Palette.right)
                    } else if destination.isStop || remotePattern != nil {
                        Image("icon-guidance-train")
                    } else {
                        Image(systemName: "mappin")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .id(iconKey)
                .transition(reduceMotion ? .identity : .iconSwap)
            }
                .frame(width: 44, height: 44)
                .background((turn.map { $0.isLeft ? Palette.left : Palette.right } ?? Palette.accent).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 12))
                .animation(reduceMotion ? nil : .easeInOut(duration: Motion.fast), value: iconKey)
                // Three taps: the next trams once there, going to a stop.
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture(count: 3) { sayNextTrams() }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                // A new instruction swaps in (up and out, then up and in).
                ZStack(alignment: .leading) {
                    Text(title)
                        .font(.atkinson(18, .bold, relativeTo: .headline))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .id(title)
                        .transition(reduceMotion ? .identity : .textSwap)
                }
                // The distance changes every second or so: its digits roll instead.
                Text(detail)
                    .font(.atkinson(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.secondaryText)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The swaps run with their own timing; the card resizes with the new height.
            .animation(reduceMotion ? nil : Motion.cardResize, value: title)
            .animation(reduceMotion ? nil : .easeInOut(duration: Motion.quick), value: detail)

            // With the map, the progress is along its bottom edge instead.
            if !mapIsVisible {
                Capsule()
                    .fill(Palette.track)
                    .frame(width: 64, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Palette.accent)
                            .frame(width: max(5, 64 * step.progress), height: 6)
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: step.progress)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(CardGlass())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(turnTitle.map { "Next: \($0), in \(toTurn.spoken). \(step.remainingSpoken) to \(destinationName)" }
                            ?? "Going to \(destinationName), \(step.remainingSpoken) left")
        // With VoiceOver, the three taps on the symbol as an action.
        .accessibilityActions {
            if canSayNextTrams { Button("Next trams", action: sayNextTrams) }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                toolbarButton(icon: Image(voiceOn ? "icon-guidance-volume" : "icon-guidance-volume-off"),
                              title: voiceOn ? "Voice on" : "Voice off", screenCorners: .leading) {
                    voiceOn.toggle()
                    // Set by hand while the dial is held: letting go leaves it so.
                    voiceHeld = false
                    if !voiceOn { voice.stop() }
                }
                .accessibilityLabel("Voice")
                .accessibilityValue(voiceOn ? "On" : "Off")

                toolbarButton(icon: Image("icon-guidance-locate"), title: "Where am I", screenCorners: [],
                              action: whereAmI)

                // A tap asks first; holding it for `endHoldDuration` ends straight away.
                toolbarButton(icon: Image("icon-guidance-end"), title: "End", fill: endHoldProgress,
                              screenCorners: .trailing) {
                    guard !endedByHold else { return }
                    confirmingEnd = true
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: Self.endHoldDuration)
                        .updating($holdingEnd) { pressing, state, _ in state = pressing }
                        .onEnded { _ in
                            endedByHold = true
                            end()
                        }
                )
                .onChange(of: holdingEnd) { _, holding in
                    // Fills from the left, starting only after `endHoldDelay` so a
                    // plain tap shows nothing, and full the moment the hold ends it.
                    let fill = Animation.linear(duration: Self.endHoldDuration - Self.endHoldDelay)
                        .delay(Self.endHoldDelay)
                    withAnimation(holding ? fill : .easeOut(duration: 0.2)) {
                        endHoldProgress = holding ? 1 : 0
                    }
                }
                .accessibilityLabel("End navigation")
                .accessibilityAction(named: "End now", end)
            }

            // Used less often: a lower row, with the icon beside the label.
            // On the map instead while it shows.
            if !(showsMap && mapIsVisible) {
                toolbarButton(icon: Image(systemName: "location.north.circle"),
                              title: isCalibrating ? "Calibrating" : "Calibrate", compact: true,
                              action: recalibrate)
                    .disabled(isCalibrating || remotePattern != nil || replay != nil)
                    .accessibilityLabel(isCalibrating ? "Calibrating" : "Calibrate compass and location")
                    .accessibilityHint("Then move the phone in a figure eight")
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { calibrateRowHeight = $0 + 10 }
            }
        }
    }

    /// `compact`: the icon beside the label instead of above it, for the lower row.
    /// `fill`: how much of the button is covered in red from the left, 0 to 1
    /// (End's hold countdown). `screenCorners`: the bottom corners that follow
    /// the screen's own, the ones beside a screen corner; the others stay 20 pt.
    private func toolbarButton(icon: Image, title: String, compact: Bool = false, fill: CGFloat = 0,
                               screenCorners: HorizontalEdge.Set = .all,
                               action: @escaping () -> Void) -> some View {
        let shape = screenConcentricRectangle(20, bottomLeading: screenCorners.contains(.leading),
                                              bottomTrailing: screenCorners.contains(.trailing))
        return Button(action: action) {
            let layout = compact ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 6))
            layout {
                // The SF Symbol sized and coloured like the 26 pt icons from Figma.
                icon
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(height: 26)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.atkinson(14, .bold, relativeTo: .footnote))
                    .foregroundStyle(Palette.toolbarLabel)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 10 : 14)
            // Above the glass, under the icon and label.
            .background(alignment: .leading) {
                GeometryReader { geometry in
                    Palette.danger.opacity(0.5)
                        .frame(width: geometry.size.width * fill)
                }
                .clipShape(shape)
            }
            .glassButtonBackground(tint: nil, fallback: Palette.card, in: shape)
        }
        .buttonStyle(.plain)
    }

    /// Seconds End has to be held to end without asking.
    static let endHoldDuration: TimeInterval = 1
    /// Seconds before the countdown starts to show.
    private static let endHoldDelay: TimeInterval = 0.1

    // MARK: - Speaking

    /// A new direction: VoiceOver reads it out, otherwise the voice says it
    /// (when it's on). Never both at once.
    /// How long the dial is held before the voice comes on.
    private static let dialHoldDuration: Double = 0.4

    /// The dial is held: the voice comes on (if it was off) and says where to go.
    private func startHeldVoice() {
        dialWasHeld = true
        voiceHeld = true
        say(step.voiceLine, force: true)
    }

    /// The dial is let go: the voice goes off again if the hold turned it on.
    /// No `voice.stop()`, so what it is saying (and what is queued) finishes.
    private func endHeldVoice() {
        // If the finger slid off the dial, no tap comes to clear it.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            dialWasHeld = false
        }
        voiceHeld = false
    }

    private func announce(_ line: SpokenLine) {
        guard !readingDepartures else {
            missedDirection = true
            return
        }
        say(line, force: false)
    }

    /// Going to a stop: the trams, metros (or buses) that can be caught once
    /// there, at an ordinary walking pace, said once guidance has started:
    /// "You'll reach Dam in about 12 minutes. You can catch tram 2 to Nieuw
    /// Sloten 1 minute after you arrive, …". Up to four within half an hour
    /// of getting there: every line once before any line's other way.
    /// `nextTrams` (asked for, three taps on the card's symbol): just the
    /// next three trams after getting there, whichever lines (the next three
    /// of anything at a stop without trams), said even with the voice off.
    private func announceDepartures(nextTrams: Bool = false) async {
        let walk = navigator.walkingTimeLeft
        let arrival = Date.now.addingTimeInterval(walk)
        guard let departures = await Transit.departures(at: destination, after: arrival) else {
            if nextTrams { say("The departures can't be found right now.", force: true) }
            return
        }
        let catchable: [Transit.Departure]
        if nextTrams {
            let after = departures.filter { $0.time >= arrival && $0.time <= arrival.addingTimeInterval(30 * 60) }
            let trams = after.filter { $0.mode == .tram }
            catchable = Array((trams.isEmpty ? after : trams).prefix(3))
        } else {
            // Each way of each line once, soonest first.
            var seen = Set<String>()
            let ways = departures.filter {
                $0.time >= arrival && $0.time <= arrival.addingTimeInterval(30 * 60)
                    && seen.insert("\($0.mode)-\($0.line)-\($0.towards)").inserted
            }
            // Every line before a line's other way, then back in time order.
            var lines = Set<String>()
            let firstOfEach = ways.filter { lines.insert("\($0.mode)-\($0.line)").inserted }
            catchable = (firstOfEach + ways.filter { way in !firstOfEach.contains { $0.id == way.id } })
                .prefix(4)
                .sorted { $0.time < $1.time }
        }

        let minutes = max(1, Int((walk / 60).rounded()))
        let reach: SpokenLine = "You'll reach \(dutch: destination.name) in about \(minutes) minute\(minutes == 1 ? "" : "s")."
        guard !catchable.isEmpty else {
            queue("\(reach) Nothing leaves there in the half hour after you arrive.", force: nextTrams)
            return
        }
        let parts = catchable.map { departure -> SpokenLine in
            let wait = Int(departure.time.timeIntervalSince(arrival) / 60)
            let when = wait <= 0 ? "as you arrive" : wait == 1 ? "1 minute after you arrive"
                : "\(wait) minutes after you arrive"
            // A train's "line" is its kind ("IC"): just "train to …".
            let line = departure.mode == .train ? "train" : "\(departure.mode.name.lowercased()) \(departure.line)"
            return "\(line) to \(dutch: departure.towards), \(when)"
        }
        let line: SpokenLine = "\(reach) You can catch \(SpokenLine.list(parts))."
        queue(line, force: nextTrams)
        // Shown in the next step card's place while it's said: about 14
        // characters a second, after the direction said before it.
        let shown = Catchable(minutesAway: minutes, departures: catchable.map {
            ($0, Int($0.time.timeIntervalSince(arrival) / 60))
        })
        withAnimation(reduceMotion ? nil : Motion.cardResize) { self.catchable = shown }
        try? await Task.sleep(for: .seconds(max(10, Double(line.plain.count) / 14 + 4)))
        // Unless it was tapped away (or a later one took its place) meanwhile.
        guard self.catchable?.departures.first?.departure.id == shown.departures.first?.departure.id else { return }
        withAnimation(reduceMotion ? nil : Motion.cardResize) { self.catchable = nil }
    }

    /// The departures: after whatever is being said, not over it, and to the
    /// end. Directions that come up meanwhile wait (`announce`). `force`:
    /// asked for, so said with the voice off too.
    private func queue(_ line: SpokenLine, force: Bool = false) {
        if UIAccessibility.isVoiceOverRunning {
            readingDepartures = true
            departuresAnnouncement = line.plain
            UIAccessibility.post(notification: .announcement, argument: line.announcement(queued: true))
        } else if speaksAloud || force {
            readingDepartures = true
            voice.speak(line, after: true) { doneReadingDepartures() }
        } else {
            return
        }
        // In case the end is never heard of: about 14 characters a second,
        // after the direction said before it, and then some.
        Task {
            try? await Task.sleep(for: .seconds(Double(line.plain.count) / 14 + 10))
            doneReadingDepartures()
        }
    }

    /// Going to a stop, on the real route: the next trams can be asked for.
    private var canSayNextTrams: Bool {
        destination.isStop && remotePattern == nil && navigator.status == .guiding && pattern != .arrived
    }

    /// The next three trams once at the stop (three taps on the card's
    /// symbol), after whatever is being said; not again while they are.
    private func sayNextTrams() {
        guard canSayNextTrams, !readingDepartures else { return }
        Task { await announceDepartures(nextTrams: true) }
    }

    /// Skips the departures: quiet, and their card gone. The direction is
    /// said if it changed meanwhile.
    private func skipDepartures() {
        guard readingDepartures else { return }
        let missed = missedDirection
        readingDepartures = false
        missedDirection = false
        departuresAnnouncement = nil
        withAnimation(reduceMotion ? nil : Motion.cardResize) { catchable = nil }
        if missed {
            say(step.voiceLine, force: true)
        } else if UIAccessibility.isVoiceOverRunning {
            // A new announcement is what stops VoiceOver's.
            UIAccessibility.post(notification: .announcement, argument: "Departures skipped")
        } else {
            voice.stop()
        }
    }

    /// The departures have been said: now the direction, if it changed meanwhile.
    private func doneReadingDepartures() {
        guard readingDepartures else { return }
        readingDepartures = false
        departuresAnnouncement = nil
        if missedDirection {
            missedDirection = false
            say(step.voiceLine, force: false)
        }
    }

    private func say(_ line: SpokenLine, force: Bool) {
        // Asked for (a tap, Where am I): said now, over the departures.
        if force {
            readingDepartures = false
            missedDirection = false
        }
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: line.announcement())
        } else if speaksAloud || force {
            voice.speak(line)
        }
    }

    /// The distances said on the way to a turn: every 100 m from 500 m, every
    /// 50 m below 200 m and every 10 m below 50 m, then a warning at 5 m.
    private static let countdownMarks: [Double] = [500, 400, 300, 200, 150, 100, 50, 40, 30, 20, 10, 5]

    /// Says the next distance to the turn once it has been passed, e.g.
    /// "150 metres". Each is said once per turn, and only the nearest one when
    /// the GPS jumps past several. Starting on a new turn, or with `speaks`
    /// off, it only notes where the countdown is.
    private func countDown(speaks: Bool) {
        guard remotePattern == nil, navigator.status == .guiding,
              let turn = navigator.nextTurn else { return }
        // A turn around or almost there says its own thing.
        guard [.forward, .left, .right].contains(navigator.pattern) else { return }
        // The nearest one not passed yet; none further out than 500 m.
        let mark = Self.countdownMarks.last { $0 >= navigator.distanceToNext } ?? .infinity
        guard speaks, let last = countdown, last.turn == turn.along else {
            countdown = (turn.along, mark, navigator.pattern)
            return
        }
        // A new direction is about to be said, with its own distance.
        guard last.pattern == navigator.pattern, mark < last.mark else { return }
        countdown = (turn.along, mark, navigator.pattern)
        announce(mark == 5 ? "In 5 metres the \(turn.isLeft ? "left" : "right") turn is coming up"
                           : "\(Int(mark)) metres")
    }

    /// The street the user is on and what's left. Asked for, so it is said
    /// even with the voice off.
    private func whereAmI() {
        let away: SpokenLine = "\(dutch: remotePattern == nil ? destination.name : "Centraal") is \(step.remainingSpoken) away."
        guard remotePattern == nil else {
            say("You're on \(dutch: "Damrak"). \(away)", force: true)
            return
        }
        guard let location = navigator.lastLocation else {
            say("Still finding where you are.", force: true)
            return
        }
        Task {
            let street = try? await CLGeocoder().reverseGeocodeLocation(location).first?.thoroughfare
            say(street.map { street -> SpokenLine in "You're on \(dutch: street). \(away)" } ?? away, force: true)
        }
    }

    /// The direction feels off: start the GPS afresh, and talk the user
    /// through calibrating the compass. Said even with the voice off.
    private func recalibrate() {
        navigator.recalibrate()
        guard !isSimulated || simulationUsesCompass else {
            say("Location restarted.", force: true)
            return
        }
        say("Calibrating. Hold the phone in front of you and draw a figure eight in the air with it, a few times.",
            force: true)
        isCalibrating = true
        calibration = Task {
            let ok = await heading.recalibrate()
            isCalibrating = false
            guard !Task.isCancelled else { return }
            say(ok ? "Compass calibrated. Hold the phone flat in front of you again."
                   : "The compass is still unsure. Step away from metal, cars or magnets, and try again.",
                force: true)
        }
    }

    private func end() {
        calibration?.cancel()
        navigator.stop()
        phoneHaptics.forwardInterval = nil
        heading.stop()
        readingDepartures = false
        voice.stop()
        phoneHaptics.stop()
        if remotePattern == nil, connectivity.isReachable { connectivity.sendStop() }
        dismiss()
    }
}

// MARK: - End guidance

/// "17 End guidance?": asked when End is tapped, in a system sheet just as
/// tall as its content. Keep going is the main action, so a stray tap never
/// ends the walk. The system gives it the handle, the dimming, swipe down
/// and VoiceOver's escape gesture (both Keep going).
private struct EndGuidanceSheet: View {
    let destination: String
    /// Nil while there is no route yet.
    fileprivate let distance: Distance?
    let onKeepGoing: () -> Void
    let onEnd: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool
    /// The content's height, for the sheet's one detent. Grows with larger text.
    @State private var height: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("End guidance?")
                .font(.atkinson(30, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.6)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)

            Text(distance.map { "You're \($0.short) from \(destination)." } ?? "Still finding the way to \(destination).")
                .font(.atkinson(18, relativeTo: .body))
                .foregroundStyle(Palette.secondaryText)
                .accessibilityLabel(distance.map { "You're \($0.spoken) from \(destination)." }
                                    ?? "Still finding the way to \(destination).")

            PrimaryButton("Keep going", action: onKeepGoing)

            SecondaryButton("End guidance", destructive: true, action: onEnd)

            Text("Tip: hold End for \(Int(GuidanceView.endHoldDuration)) \(GuidanceView.endHoldDuration == 1 ? "second" : "seconds") to skip this")
                .font(.atkinson(14, relativeTo: .footnote))
                .foregroundStyle(Palette.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        // Room at the top for the system's handle.
        .padding(.top, 32)
        .padding(.bottom, 20)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        // Liquid Glass, darkened with the screens' colour at 80%: the plain
        // system glass let the colourful navigation screen show through too
        // much, which made the text hard to read.
        .presentationBackground { GlassSheetBackground(tint: Palette.background.opacity(0.8)) }
        .preferredColorScheme(.dark)
        .onAppear { titleFocused = true }
    }
}

// MARK: - Simulated walk

/// Simulated walk: where the user is on the route, and buttons to move
/// them along it.
private struct SimulationControls: View {
    @ObservedObject var navigator: RouteNavigator
    @Binding var usesCompass: Bool

    /// Holding Forward or Back walks at walking speed times this.
    @State private var speed: Double = 1

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Eyebrow("SIMULATED WALK")
                Spacer()
                Text("\(Int(navigator.simulatedAlong)) of \(Int(navigator.routeLength)) m")
                    .font(.atkinson(15, .bold, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                WalkButton(title: "Back", systemImage: "arrow.down", direction: -1,
                           speed: speed, navigator: navigator)
                WalkButton(title: "Forward", systemImage: "arrow.up", direction: 1,
                           speed: speed, navigator: navigator)
            }

            HStack(spacing: 14) {
                Picker("Walking speed", selection: $speed) {
                    Text("1×").tag(1.0)
                    Text("3×").tag(3.0)
                    Text("10×").tag(10.0)
                }
                .pickerStyle(.segmented)

                Toggle("Compass", isOn: $usesCompass)
                    .font(.atkinson(15, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.text)
                    .tint(Palette.accent)
                    .fixedSize()
                    .accessibilityHint("On: turn the phone to pick the direction. Off: the route picks it.")
            }
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

/// Moves the simulated user along the route: a tap is one step of
/// `stepLength`, holding keeps walking until let go.
private struct WalkButton: View {
    let title: String
    let systemImage: String
    /// 1 is forwards, -1 backwards.
    let direction: Double
    let speed: Double
    let navigator: RouteNavigator

    @State private var isPressed = false
    @State private var walking: Task<Void, Never>?
    /// Set once the press has turned into walking, so letting go doesn't add a step.
    @State private var didWalk = false

    private let stepLength: Double = 5
    /// Metres a second, as in RouteNavigator.
    private let walkingSpeed: Double = 1.3
    /// A press held longer than this walks.
    private let holdDelay: Duration = .milliseconds(350)
    private let tick: Double = 0.25

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.atkinson(18, .bold, relativeTo: .headline))
            .foregroundStyle(isPressed ? Palette.onAccent : Palette.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isPressed ? Palette.accent : Palette.card2, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 60, perform: {},
                                onPressingChanged: pressingChanged)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title == "Back" ? "Walk back" : "Walk forward")
            .accessibilityHint("Moves you \(Int(stepLength)) metres. Hold to keep walking.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { step() }
    }

    private func pressingChanged(_ pressing: Bool) {
        isPressed = pressing
        walking?.cancel()
        if pressing {
            didWalk = false
            walking = Task { @MainActor in
                try? await Task.sleep(for: holdDelay)
                while !Task.isCancelled {
                    didWalk = true
                    navigator.simulateWalk(by: direction * walkingSpeed * speed * tick)
                    try? await Task.sleep(for: .seconds(tick))
                }
            }
        } else if !didWalk {
            step()
        }
    }

    private func step() {
        navigator.simulateWalk(by: direction * stepLength)
    }
}

/// Replaying a recorded walk: how far it has got, and a pause button.
private struct ReplayBar: View {
    @ObservedObject var replay: TripReplay

    var body: some View {
        HStack(spacing: 12) {
            Button {
                replay.togglePause()
            } label: {
                Image(systemName: replay.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(width: 44, height: 44)
                    .glassButtonBackground(tint: nil, fallback: Palette.card, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(replay.isFinished)
            .accessibilityLabel(replay.isPaused ? "Play" : "Pause")

            VStack(alignment: .leading, spacing: 6) {
                Text(replay.isFinished ? "Replay finished" : "Replaying recorded walk")
                    .font(.atkinson(14, .bold, relativeTo: .footnote))
                    .foregroundStyle(Palette.text)
                ProgressView(value: min(replay.elapsed, replay.duration), total: max(replay.duration, 1))
                    .tint(Palette.accent)
            }

            Text("\(Self.time(replay.elapsed)) / \(Self.time(replay.duration))")
                .font(.atkinson(14, .bold, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryText)
        }
        .accessibilityElement(children: .contain)
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Map simulation: what to do, and the compass switch.
private struct DragControls: View {
    @Binding var usesCompass: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("SIMULATED WALK")
                Text("Drag the map to move")
                    .font(.atkinson(15, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Toggle("Compass", isOn: $usesCompass)
                .font(.atkinson(15, .bold, relativeTo: .subheadline))
                .foregroundStyle(Palette.text)
                .tint(Palette.accent)
                .fixedSize()
                .accessibilityHint("On: turn the phone to pick the direction. Off: the route picks it.")
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Map

/// The navigation maps in 3D (tilted, with buildings standing up, like
/// Apple Maps when walking) or seen from straight above. The choice is kept
/// for the next route.
private enum MapTilt {
    static let storageKey = "mapIs3D"

    static func pitch(is3D: Bool) -> Double { is3D ? 55 : 0 }

    static func style(is3D: Bool) -> MapStyle {
        .standard(elevation: is3D ? .realistic : .flat, pointsOfInterest: .excludingAll)
    }
}

/// The 2D/3D switch in the map's bottom right corner. It shows what a tap changes to,
/// like Apple Maps.
private struct MapTiltToggle: View {
    @Binding var is3D: Bool

    var body: some View {
        Button {
            is3D.toggle()
        } label: {
            Text(is3D ? "2D" : "3D")
                .font(.atkinson(16, .bold, relativeTo: .callout))
                .foregroundStyle(Palette.text)
                .frame(width: 44, height: 44)
                // Clear Liquid Glass, like the screen's other buttons.
                .glassButtonBackground(tint: nil, fallback: Palette.card,
                                       in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("3D map")
        .accessibilityValue(is3D ? "On" : "Off, seen from above")
        .accessibilityHint(is3D ? "Shows the map from straight above." : "Tilts the map, with buildings in 3D.")
    }
}

/// Map simulation: the user is the pin in the middle, and dragging the map
/// moves them there, facing the way they were moved. It starts where the
/// route starts, north up. With the compass on, it turns so the way the
/// phone points is up, as on a real walk; otherwise only the user moves it.
private struct DragMap: View {
    @ObservedObject var navigator: RouteNavigator
    @ObservedObject var heading: HeadingTracker
    let destination: Destination
    /// Where the compass goes: under the card that lies over the top of the map.
    let controlsTop: CGFloat

    @Namespace private var mapScope

    @State private var position: MapCameraPosition = .automatic
    @State private var isPlaced = false
    /// Where the map is now, so turning it keeps the user's spot and zoom.
    @State private var camera: MapCamera?
    @AppStorage(MapTilt.storageKey) private var is3D = true

    var body: some View {
        Map(position: $position, scope: mapScope) {
            if let line = navigator.routeLine {
                MapPolyline(line)
                    .stroke(Palette.success, style: StrokeStyle(lineWidth: 5, lineCap: .round,
                                                               lineJoin: .round))
                    // Over the 3D buildings and the labels: in a narrow street,
                    // the buildings beside it hid the line on the ground.
                    .mapOverlayLevel(level: .aboveLabels)
            }
            Marker(destination.name, systemImage: destination.symbol,
                   coordinate: destination.coordinate)
                .tint(Palette.accent)
        }
        .mapStyle(MapTilt.style(is3D: is3D))
        // The compass (shown while the map is turned: north is that way) by
        // hand, under the card, instead of in the corner the card covers.
        .mapControls {}
        .overlay(alignment: .topTrailing) {
            MapCompass(scope: mapScope)
                .padding(.top, controlsTop)
                .padding(.trailing, 8)
        }
        .mapScope(mapScope)
        .onMapCameraChange(frequency: .continuous) { context in
            camera = context.camera
            heading.setMapHeading(context.camera.heading)
            // Only the user's dragging moves the user, not the map placing or turning itself.
            if position.positionedByUser {
                navigator.simulateLocation(context.camera.centerCoordinate)
            }
        }
        .overlay {
            // The map moves under this pin, so it can't be the system's
            // location dot (that only shows the real GPS).
            LocationDot(heading: heading, tilt: camera?.pitch ?? 0)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            MapTiltToggle(is3D: $is3D)
                .padding(8)
        }
        .onChange(of: navigator.lastLocation, initial: true) { _, location in
            guard !isPlaced, let location else { return }
            isPlaced = true
            position = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 400,
                                         heading: heading.steadyDegrees ?? 0, pitch: MapTilt.pitch(is3D: is3D)))
        }
        // Tilting keeps the user's spot, zoom and heading.
        .onChange(of: is3D) { _, on in
            guard isPlaced, var camera else { return }
            camera.pitch = MapTilt.pitch(is3D: on)
            withAnimation(.easeInOut(duration: 0.4)) { position = .camera(camera) }
        }
        // Turning the user turns the map; not the hand's sway.
        .onChange(of: heading.steadyDegrees) { _, degrees in
            guard isPlaced, let degrees, var camera,
                  abs(HeadingTracker.unwrap(degrees, after: camera.heading) - camera.heading) >= 0.1 else { return }
            camera.heading = degrees
            position = .camera(camera)
        }
    }
}

/// The next step card's background: Liquid Glass over the map, tinted dark
/// (the screen's background at 70%) so the text stays easy to read over busy streets.
/// Not interactive: the card isn't a button. A flat card before iOS 26.
private struct CardGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(Palette.background.opacity(0.7)),
                                in: RoundedRectangle(cornerRadius: 22))
        } else {
            content.background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
        }
    }
}

/// Bumped each time the navigation map's camera moves.
private final class MapFrame: ObservableObject {
    @Published var version = 0
}

/// The route line and the user's dot, drawn over the navigation map at the
/// points the map shows those places at now, again each time it moves. In
/// 3D, places past the horizon have no point; the line stops there.
private struct RouteOverlay: View {
    let proxy: MapProxy
    @ObservedObject var frame: MapFrame
    @ObservedObject var heading: HeadingTracker
    let line: MKPolyline?
    let user: () -> CLLocationCoordinate2D?
    let tilt: Double

    var body: some View {
        // Read, so a camera move redraws this.
        let _ = frame.version
        ZStack {
            if let line {
                Path { path in
                    var isDrawing = false
                    for coordinate in line.coordinates {
                        guard let point = proxy.convert(coordinate, to: .local) else {
                            isDrawing = false
                            continue
                        }
                        if isDrawing { path.addLine(to: point) } else { path.move(to: point) }
                        isDrawing = true
                    }
                }
                .stroke(Palette.success, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let coordinate = user(), let point = proxy.convert(coordinate, to: .local) {
                LocationDot(heading: heading, tilt: tilt)
                    .position(point)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

/// The user's spot on the navigation map, gliding from one GPS fix to the
/// next over `duration`, about the time between fixes, so the map moves on
/// steadily while walking.
private final class LocationGlide {
    private var from: CLLocationCoordinate2D?
    private var to: CLLocationCoordinate2D?
    private var start: TimeInterval = 0
    private let duration: TimeInterval = 1

    private var progress: Double {
        min(1, (ProcessInfo.processInfo.systemUptime - start) / duration)
    }

    var isMoving: Bool { to != nil && progress < 1 }

    var coordinate: CLLocationCoordinate2D? {
        guard let to else { return nil }
        guard let from else { return to }
        let t = progress
        return CLLocationCoordinate2D(latitude: from.latitude + (to.latitude - from.latitude) * t,
                                      longitude: from.longitude + (to.longitude - from.longitude) * t)
    }

    /// On from wherever the glide has got to; a first fix (or a jump of
    /// more than 50 m, a reroute or a far-off fix) straight there.
    func move(to target: CLLocationCoordinate2D) {
        let here = coordinate
        let far = here.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) > 50
        } ?? true
        from = far ? target : here
        to = target
        start = ProcessInfo.processInfo.systemUptime
    }
}

/// The small map on the navigation screen, like Apple Maps when walking:
/// close up, about 50 m ahead of the user, and turned so the way the phone
/// points is up. Pinching or dragging stops the following; the button in
/// the corner starts it again.
private struct FollowMap: View {
    @ObservedObject var navigator: RouteNavigator
    @ObservedObject var heading: HeadingTracker
    let destination: Destination
    /// Where the compass goes: under the card that lies over the top of the map.
    let controlsTop: CGFloat

    @Namespace private var mapScope

    @State private var position: MapCameraPosition = .automatic
    @State private var isFollowing = true
    @State private var size: CGSize = .zero
    @AppStorage(MapTilt.storageKey) private var is3D = true
    /// The map's tilt now, for the location dot.
    @State private var pitch: Double = 0
    /// Where the camera puts the user: gliding from fix to fix, a step every
    /// frame (see `follow`). The GPS fixes come about once a second.
    @State private var glide = LocationGlide()
    @State private var frames = FrameLoop()
    /// Bumped as the camera moves, so the route and the dot drawn over the
    /// map move with it (see `RouteOverlay`).
    @State private var mapFrame = MapFrame()

    /// Metres of map in view ahead of the user, in the part under the card.
    private let metresAhead: Double = 30
    /// The user sits this far up from the bottom edge, as a part of the
    /// height of the map that shows (under the card).
    private let userHeight: Double = 0.55

    /// How much of the map's height shows below the next step card, which
    /// lies over its top: 0 to 1.
    private var visiblePart: Double {
        guard size.height > 0 else { return 1 }
        return min(1, max(0.1, (size.height - (controlsTop - 8)) / size.height))
    }
    /// Where the user sits, up from the bottom edge, as a part of the whole
    /// map's height (card and all).
    private var userPart: Double { userHeight * visiblePart }

    var body: some View {
        MapReader { proxy in
            Map(position: $position, scope: mapScope) {
                // The route and the user's dot are drawn over the map instead
                // (RouteOverlay): MapKit's own line, drawn in tiles behind the
                // scenes, went missing ahead of the user on real walks while the
                // camera moved every frame (it showed only where it had been
                // drawn already, behind them); and an annotation with the dot in
                // it stayed a flat circle without its cone, as if never updated.
                Marker(destination.name, systemImage: destination.symbol,
                       coordinate: destination.coordinate)
                    .tint(Palette.accent)
            }
            .mapStyle(MapTilt.style(is3D: is3D))
            .overlay {
                RouteOverlay(proxy: proxy, frame: mapFrame, heading: heading, line: navigator.routeLine,
                             user: { glide.coordinate ?? navigator.shownCoordinate ?? navigator.lastLocation?.coordinate }, tilt: pitch)
            }
            // The compass (shown while the map is turned: north is that way) by
            // hand, under the card, instead of in the corner the card covers.
            .mapControls {}
            .overlay(alignment: .topTrailing) {
                MapCompass(scope: mapScope)
                    .padding(.top, controlsTop)
                    .padding(.trailing, 8)
            }
            .mapScope(mapScope)
            .onMapCameraChange(frequency: .continuous) { context in
                heading.setMapHeading(context.camera.heading)
                if abs(context.camera.pitch - pitch) > 0.5 { pitch = context.camera.pitch }
                mapFrame.version &+= 1
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            // Turning: the map turns along, but not with the hand's sway. The
            // steady way glides there itself, a step a frame.
            .onChange(of: heading.steadyDegrees) { follow(animated: false) }
            // Walking: a glide to the new spot over the second until the next one,
            // a step a frame, so it neither jumps nor cuts the turning short.
            .onChange(of: navigator.lastLocation, initial: true) { _, location in
                guard let location else { return }
                // On the route's line while on the route, like Apple Maps.
                glide.move(to: navigator.shownCoordinate ?? location.coordinate)
                frames.run { _ in
                    follow(animated: false)
                    return glide.isMoving
                }
            }
            .onDisappear { frames.stop() }
            .onChange(of: size) { follow(animated: false) }
            // Following or not, the tilt changes; following puts the user back in place.
            .onChange(of: is3D) { _, on in
                if isFollowing {
                    follow(animated: true)
                } else if let camera = position.camera {
                    var tilted = camera
                    tilted.pitch = MapTilt.pitch(is3D: on)
                    withAnimation(.easeInOut(duration: 0.4)) { position = .camera(tilted) }
                }
            }
            // A pinch or drag by the user stops the following.
            .onChange(of: position.positionedByUser) { _, byUser in
                if byUser { isFollowing = false }
            }
            // Bottom right, under the compass: the 2D/3D switch, and above it (so
            // the switch doesn't move) the follow button when it is needed.
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 8) {
                    if !isFollowing {
                        Button {
                            isFollowing = true
                            follow(animated: true)
                        } label: {
                            Image(systemName: "location.north.line.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Palette.text)
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Follow my location")
                    }
                    MapTiltToggle(is3D: $is3D)
                }
                .padding(8)
            }
        }
    }

    /// Puts the camera behind the user, looking the way the phone points.
    private func follow(animated: Bool) {
        guard isFollowing, size.width > 0, size.height > 0,
              let location = navigator.lastLocation else { return }
        // Animated (a tilt, following again): straight to the fix. Otherwise
        // where the glide between fixes has got to.
        let shown = navigator.shownCoordinate ?? location.coordinate
        let user = animated ? shown : glide.coordinate ?? shown
        // The way the user faces; without a compass, the way they walk.
        let facing = heading.steadyDegrees ?? (location.course >= 0 ? location.course : 0)
        let northUp = (facing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)

        // `metresAhead` fills the part of the map that shows above the user,
        // between them and the card (seen from straight above; tilted, more
        // lies ahead, getting smaller). The map runs on under the card.
        let visibleHeight = metresAhead / ((1 - userHeight) * visiblePart)
        // Measured: a map shows about 1.23 × the camera distance across its width.
        let distance = visibleHeight * size.width / (1.23 * size.height)
        // The centre of the map lies ahead of the user, so the user sits low.
        let pitch = MapTilt.pitch(is3D: is3D)
        let center = coordinate(user, movedBy: groundAhead(distance: distance, pitch: pitch),
                                towards: northUp)
        let camera = MapCamera(centerCoordinate: center, distance: distance, heading: northUp, pitch: pitch)

        if animated {
            withAnimation(.easeOut(duration: 0.4)) { position = .camera(camera) }
        } else {
            position = .camera(camera)
        }
    }

    /// Metres on the ground from the user to the centre of the map, so the
    /// user shows `userPart` up from the bottom edge. Tilted, the ground
    /// near the bottom is closer to the camera, so it takes fewer metres.
    private func groundAhead(distance: Double, pitch: Double) -> Double {
        // Half the camera's view, up and down, from the measured 1.23 across.
        let halfView = atan(0.615 * size.height / size.width)
        // How far below the middle of the view the user is, as an angle.
        let belowMiddle = atan(2 * (0.5 - userPart) * tan(halfView))
        let tilt = pitch * .pi / 180
        // Camera height × how far out the user is seen, taken from how far out the centre is.
        return distance * sin(tilt) - distance * cos(tilt) * tan(tilt - belowMiddle)
    }

    private func coordinate(_ start: CLLocationCoordinate2D, movedBy metres: Double,
                            towards bearing: Double) -> CLLocationCoordinate2D {
        let radians = bearing * .pi / 180
        let metresPerDegree = 111_320.0
        return CLLocationCoordinate2D(
            latitude: start.latitude + metres * cos(radians) / metresPerDegree,
            longitude: start.longitude + metres * sin(radians)
                / (metresPerDegree * cos(start.latitude * .pi / 180)))
    }
}

/// The Go straight zone: an arc on the edge of the dial's coloured circle
/// (176 of its 250 points across), centred on the top
/// (where the phone points). With the pointer inside it, the signal is Go
/// straight; outside it, a turn. While the user faces away it grows thicker
/// and its width pulses, to draw them back to it.
private struct StraightZone: View {
    /// Degrees each side of the top.
    let halfAngle: Double
    let size: CGFloat
    let isFacing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PhaseAnimator([false, true]) { wide in
            arc(Arc(halfAngle: halfAngle, lineWidth: lineWidth(wide: wide)))
        } animation: { _ in .easeInOut(duration: 0.35) }
            .frame(width: size * 176 / 250, height: size * 176 / 250)
            .frame(width: size, height: size)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFacing)
    }

    /// Liquid Glass tinted 80% green; a flat 80% green before iOS 26.
    @ViewBuilder
    private func arc(_ shape: Arc) -> some View {
        let green = Palette.success.opacity(0.8)
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular.tint(green), in: shape)
        } else {
            shape.fill(green)
        }
    }

    /// 8 pt while facing the right way; facing away, between 10 and 16 pt
    /// (a steady 13 pt with Reduce Motion).
    private func lineWidth(wide: Bool) -> CGFloat {
        if isFacing { return 8 }
        if reduceMotion { return 13 }
        return wide ? 16 : 10
    }

    /// The arc already stroked, so its width animates along.
    private struct Arc: Shape {
        let halfAngle: Double
        var lineWidth: CGFloat

        var animatableData: CGFloat {
            get { lineWidth }
            set { lineWidth = newValue }
        }

        func path(in rect: CGRect) -> Path {
            var path = Path()
            // 0° is to the right, and angles grow clockwise on screen: -90° is the top.
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                        startAngle: .degrees(-90 - halfAngle), endAngle: .degrees(-90 + halfAngle),
                        clockwise: false)
            return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

/// A dot on the edge of the dial's coloured circle, on the Go straight arc's
/// line, with a cone fading outwards, like the
/// location dot on the home map, pointing the way the route goes a few metres
/// ahead (the look-ahead in the navigation settings, 4 m at first):
/// straight up when that is straight ahead of the phone. It turns along as
/// the user turns, and swings round as a corner comes up. The dot and cone
/// look like the user's on the maps, in the same blue; red while outside the
/// Go straight zone, with white arrows round the circle from the dot to the
/// zone's nearer end.
private struct TurnPointer: View {
    @ObservedObject var heading: HeadingTracker
    /// The way the route goes just ahead, in degrees clockwise from north.
    let bearing: Double
    let size: CGFloat
    /// The Go straight zone's degrees each side of the top.
    let straightAngle: Double
    let isFacing: Bool

    /// The maps' blue while facing the way on; red while facing away from it.
    private var color: Color { isFacing ? Palette.left : Palette.turnAround }

    /// The angle on screen, unwrapped so it always turns the short way round.
    @State private var angle: Double?

    /// Clockwise from the top of the phone; nil without a compass reading.
    private var target: Double? { heading.degrees.map { bearing - $0 } }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the arrows have moved towards the zone, at 20 pt a second,
    /// within one arrow's spacing.
    private func arrowShift(at date: Date) -> CGFloat {
        CGFloat((date.timeIntervalSinceReferenceDate * 20).truncatingRemainder(dividingBy: ZoneGap.spacing))
    }

    var body: some View {
        // The edge of the coloured circle, where the Go straight arc is.
        let ringRadius = size * 88 / 250
        // From the dot out to the dial's outermost ring (244 of its 250 points across).
        let coneLength = size * 122 / 250 - ringRadius
        ZStack {
            // Not rotated with the dot: it runs from the fixed zone to it.
            // Its arrows run from the dot towards the zone, the way to turn
            // (standing still with Reduce Motion).
            if !isFacing, let angle {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    ZoneGap(angle: angle, halfAngle: straightAngle, radius: ringRadius,
                            shift: arrowShift(at: timeline.date))
                        .stroke(Palette.text.opacity(0.8),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                .transition(.opacity)
            }
            pointer(ringRadius: ringRadius, coneLength: coneLength)
        }
        .frame(width: size, height: size)
        .opacity(angle == nil ? 0 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: angle)
        .animation(.easeOut(duration: 0.2), value: isFacing)
        .onChange(of: target, initial: true) { _, target in
            angle = target.map { new in angle.map { HeadingTracker.unwrap(new, after: $0) } ?? new }
        }
    }

    private func pointer(ringRadius: CGFloat, coneLength: CGFloat) -> some View {
        ZStack {
            Cone()
                .fill(LinearGradient(colors: [color.opacity(0.75), color.opacity(0)],
                                     startPoint: .bottom, endPoint: .top))
                .frame(width: coneLength * 1.2, height: coneLength)
                .offset(y: -ringRadius - coneLength / 2)
            // The same dot as the user's on the maps (LocationDot), red when facing away.
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white, lineWidth: 3.5))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .offset(y: -ringRadius)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle ?? 0))
    }

    /// Arrowheads along the circle between the Go straight zone's nearer end
    /// and the dot, a little short of both, pointing at the zone; none while
    /// the dot is inside the zone. The angle animates, so the arrows keep up
    /// with the dot as it springs round.
    private struct ZoneGap: Shape {
        /// From one arrow to the next, in points along the circle.
        static let spacing: CGFloat = 12

        /// The dot's angle clockwise from the top, unwrapped.
        var angle: Double
        let halfAngle: Double
        let radius: CGFloat
        /// How far the arrows have moved towards the zone, 0..<spacing.
        let shift: CGFloat

        var animatableData: Double {
            get { angle }
            set { angle = newValue }
        }

        func path(in rect: CGRect) -> Path {
            var path = Path()
            // -180...180, so the line goes the short way round, the way to turn.
            let dot = remainder(angle, 360)
            // Clear of the zone's round end and of the dot with its ring.
            let gap = 14 / Double(radius) * 180 / .pi
            let side: Double = dot < 0 ? -1 : 1
            let start = side * (halfAngle + gap)
            let end = dot - side * gap
            guard (end - start) * side > 0 else { return path }
            let length = CGFloat((end - start) * side * .pi / 180) * radius
            let center = CGPoint(x: rect.midX, y: rect.midY)
            // Each arrow's tip, measured along the circle from the zone's end.
            var distance = Self.spacing - shift
            while distance <= length {
                // 0° is to the right, and angles grow clockwise on screen: -90° is the top.
                let screen = (-90 + start + side * Double(distance / radius) * 180 / .pi) * .pi / 180
                let outward = CGVector(dx: cos(screen), dy: sin(screen))
                // Along the circle, towards the zone.
                let back = CGVector(dx: outward.dy * side, dy: -outward.dx * side)
                let tip = CGPoint(x: center.x + outward.dx * radius + back.dx * 2.5,
                                  y: center.y + outward.dy * radius + back.dy * 2.5)
                // The arrowhead's two arms, 5 pt back and 4 pt either side.
                for arm in [CGFloat(-1), 1] {
                    path.move(to: CGPoint(x: tip.x - back.dx * 5 + outward.dx * 4 * arm,
                                          y: tip.y - back.dy * 5 + outward.dy * 4 * arm))
                    path.addLine(to: tip)
                }
                distance += Self.spacing
            }
            return path
        }
    }

}

extension AVSpeechUtterance {
    /// A line in the best English voice on this phone: a Premium voice if one
    /// is downloaded (Settings, Accessibility, Spoken Content, Voices), else
    /// an Enhanced one. Only the basic voice there: the user's own Spoken
    /// Content voice and speed. `dutch`: a name, in the best Dutch voice
    /// (in English if there is none).
    static func tandem(_ line: String, dutch: Bool = false) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: line)
        if dutch, let voice = TandemVoice.dutch {
            utterance.voice = voice
        } else if let voice = TandemVoice.best {
            utterance.voice = voice
        } else {
            utterance.prefersAssistiveTechnologySettings = true
        }
        return utterance
    }
}

enum TandemVoice {
    /// Picked once. Premium before Enhanced; among equals, the English the
    /// phone is set to (British, American...) first.
    static let best: AVSpeechSynthesisVoice? = {
        let voice = pick("en", preferring: AVSpeechSynthesisVoice.currentLanguageCode(), basic: false)
        print("Voice: \(voice.map(describe) ?? "none downloaded, using Spoken Content")")
        return voice
    }()

    /// For the names of streets, stops and places: the one picked in the
    /// app's Settings ("Dutch names"), else `automaticDutch`. (The voice
    /// picked in the iPhone's own Settings can't be read by apps.)
    static var dutch: AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: GuidanceSettings.dutchVoiceKey),
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice
        }
        return automaticDutch
    }

    /// The best Dutch voice there is. The basic voice will do: every iPhone
    /// has one for Dutch.
    static let automaticDutch: AVSpeechSynthesisVoice? = {
        let voice = pick("nl", preferring: "nl-NL", basic: true)
        print("Dutch voice: \(voice.map(describe) ?? "none, names in English")")
        return voice
    }()

    /// Every Dutch voice on this phone, best first.
    static var dutchVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("nl") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($1.quality.rawValue, $0.name) < ($0.quality.rawValue, $1.name) }
    }

    /// "Netherlands, Enhanced".
    static func detail(of voice: AVSpeechSynthesisVoice) -> String {
        let region = voice.language.split(separator: "-").last.map(String.init) ?? ""
        let country = Locale(identifier: "en").localizedString(forRegionCode: region) ?? voice.language
        return "\(country), \(quality(of: voice))"
    }

    nonisolated private static func pick(_ language: String, preferring preferred: String,
                                         basic: Bool) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) && (basic || $0.quality != .default)
                && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { a, b in
                (a.quality.rawValue, a.language == preferred ? 1 : 0)
                    < (b.quality.rawValue, b.language == preferred ? 1 : 0)
            }
    }

    nonisolated private static func describe(_ voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) (\(voice.language), \(quality(of: voice)))"
    }

    nonisolated private static func quality(of voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "basic"
        }
    }
}

/// The voice of the navigation, on its own audio session so the vibration
/// can't cut it off.
@MainActor
private final class GuidanceVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    /// The last utterance of a line someone waits for, and what to call then.
    private var waiting: [ObjectIdentifier: () -> Void] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func voiceSession() {
        synthesizer.usesApplicationAudioSession = false
    }

    /// `after`: once what is being said is done, instead of cutting it off.
    /// One utterance per language: the names in the Dutch voice, queued
    /// right after the English around them. `done`: once it has been said,
    /// or stopped.
    func speak(_ line: SpokenLine, after: Bool = false, done: (() -> Void)? = nil) {
        if !after { stop() }
        var last: AVSpeechUtterance?
        for part in line.parts where !part.text.allSatisfy(\.isWhitespace) {
            let utterance = AVSpeechUtterance.tandem(part.text, dutch: part.isDutch)
            synthesizer.speak(utterance)
            last = utterance
        }
        guard let done else { return }
        guard let last else { return done() }
        waiting[ObjectIdentifier(last)] = done
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        let calls = waiting.values
        waiting = [:]
        calls.forEach { $0() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utterance = ObjectIdentifier(utterance)
        Task { @MainActor in self.waiting.removeValue(forKey: utterance)?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utterance = ObjectIdentifier(utterance)
        Task { @MainActor in self.waiting.removeValue(forKey: utterance)?() }
    }
}

// MARK: - Arrived

/// "14 Arrived": the end of the route, with the next trams, metros and
/// trains if it is a stop (from Transit).
private struct ArrivedView: View {
    var destination: Destination = .centraal
    var onDone: () -> Void

    /// Nil until they are in, or without internet: the card is left out.
    @State private var departures: [Transit.Departure]?

    var body: some View {
        TutorialPage(toBottomEdge: true) {
            Spacer(minLength: 0)

            Image("arrived-success")
                .accessibilityHidden(true)

            Text("You've arrived")
                .font(.atkinson(36, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.72)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(destination.subtitle.isEmpty ? destination.name : destination.subtitle)
                .font(.atkinson(20, relativeTo: .title3))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)

            if let departures, !departures.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow("NEXT DEPARTURES")
                        .accessibilityAddTraits(.isHeader)
                    // Recounted every minute between the fetches.
                    TimelineView(.everyMinute) { timeline in
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(departures.filter { $0.time > timeline.date.addingTimeInterval(-30) }
                                .prefix(3)) { departure in
                                row(departure, now: timeline.date)
                            }
                        }
                    }
                }
                .padding(18)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
            }

            Spacer(minLength: 0)

            PrimaryButton("Done", action: onDone)
        }
        // Fetched again every half minute, for live times.
        .task {
            while !Task.isCancelled {
                if let fresh = await Transit.departures(at: destination) { departures = fresh }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func row(_ departure: Transit.Departure, now: Date) -> some View {
        let minutes = max(0, Int(departure.time.timeIntervalSince(now) / 60))
        let time = minutes == 0 ? "Now" : "\(minutes) min"
        return HStack(spacing: 12) {
            // In the line's own colours if it has them (GVB's metro lines).
            Text(departure.line)
                .font(.atkinson(18, .extraBold, relativeTo: .headline))
                .foregroundStyle(departure.textColor.map { Color(hex: $0) } ?? Palette.background)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: 46, height: 34)
                .background(departure.color.map { Color(hex: $0) } ?? Palette.left,
                            in: RoundedRectangle(cornerRadius: 10))
            Text(departure.towards)
                .font(.atkinson(19, .bold, relativeTo: .headline))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(time)
                .font(.atkinson(18, .bold, relativeTo: .headline))
                .foregroundStyle(Palette.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(departure.mode.name) \(departure.line) to \(departure.towards), "
            + (minutes == 0 ? "now" : minutes == 1 ? "in 1 minute" : "in \(minutes) minutes"))
    }
}

#Preview("Navigating") {
    Typography.registerFonts()
    return GuidanceView(connectivity: ConnectivityManager(), phoneHaptics: PhoneHapticPlayer())
}

#Preview("Simulated walk") {
    Typography.registerFonts()
    return GuidanceView(simulation: .walk, connectivity: ConnectivityManager(), phoneHaptics: PhoneHapticPlayer())
}

#Preview("Mid-route") {
    Typography.registerFonts()
    return GuidanceView(simulation: .walk, startsPartWay: 0.5,
                        connectivity: ConnectivityManager(), phoneHaptics: PhoneHapticPlayer())
}

// The screens without a direction, one per thing that can go wrong.

#Preview("Finding you") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.locating))
}

#Preview("No GPS signal") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.locating, notice: .noLocationYet))
}

#Preview("Finding your route") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.routing))
}

#Preview("No internet connection") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.failed(.noConnection)))
}

#Preview("No walking route") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.failed(.noWalkingRoute)))
}

#Preview("Apple Maps not answering") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.failed(.mapsUnavailable)))
}

#Preview("Location off") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.failed(.locationOff)))
}

#Preview("Precise Location off") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.failed(.preciseLocationOff)))
}

#Preview("Off route") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.guiding, notice: .offRoute))
}

#Preview("Off route, no internet") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.guiding, notice: .offRouteNoNewRoute(.noConnection)))
}

#Preview("Off route, no route from here") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.guiding, notice: .offRouteNoNewRoute(.noWalkingRoute)))
}

#Preview("Signal lost") {
    Typography.registerFonts()
    return GuidanceView(previewing: .preview(.guiding, pattern: .signalLost))
}

#Preview("Arrived") {
    Typography.registerFonts()
    return ArrivedView(onDone: {})
        .background(Palette.background)
        .preferredColorScheme(.dark)
}
