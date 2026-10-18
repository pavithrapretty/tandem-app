//
//  RouteNavigator.swift
//  HapticRemote (iPhone)
//
//  Real walking navigation: asks MapKit for a walking route to the
//  destination, follows the user's GPS position along it, and works out which
//  signal fits right now (go straight, turn left or right, turn around,
//  almost there, arrived, signal lost). GuidanceView shows and plays it.
//
//  The direction signals come from the compass: the way the phone points,
//  compared with the way the route goes just ahead (the dial's pointer).
//  Facing the route: go straight. The route to the left: turn left, and so
//  on. Without a compass reading, they come from the route's turns instead.
//
//  Between GPS fixes, the step counter (CMPedometer) says how fast the user
//  walks, or that they have stopped: steadier than the GPS's own speed
//  between city buildings. While the GPS is too rough to follow the route
//  by, the steps carry the user on along it for a while (`coast`).
//
//  Works only while the app is on screen (location "when in use"), which the
//  haptics need anyway.
//
//  Simulated walk (`isSimulated`): the route is fetched once from the real
//  position, then the GPS is switched off and `simulateWalk` moves the user
//  along the route by hand, forwards or backwards. Everything else (turns,
//  wrong way, almost there, arrived) works as on a real walk.
//
//  Map simulation (`.drag`): the same, but the user is wherever the map is
//  dragged to (`simulateLocation`), on the route or off it, so going off
//  route and rerouting can be tried too.
//

import Combine
import CoreLocation
import CoreMotion
import MapKit

@MainActor
final class RouteNavigator: NSObject, ObservableObject {
    enum Status: Equatable {
        /// Waiting for the first good GPS fix.
        case locating
        /// Asking MapKit for the route.
        case routing
        case guiding
        case failed(String)
    }

    @Published private(set) var status: Status = .locating
    /// The signal that fits right now. Nil until there is a route.
    @Published private(set) var pattern: Pattern?
    /// Metres to the next turn, or to the destination when there are no more turns.
    @Published private(set) var distanceToNext: Double = 0
    /// Metres left along the route.
    @Published private(set) var remaining: Double = 0
    /// How much of the route is done, 0 to 1.
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastLocation: CLLocation?
    /// The turn being signalled, or else the next one ahead. Nil when no
    /// turns are left before the destination.
    @Published private(set) var nextTurn: Turn?
    /// The direction to the point on the route `lookAhead` metres ahead of the
    /// user, in degrees clockwise from north: the way to walk right now.
    @Published private(set) var bearingAhead: Double?
    /// The route's line, for drawing it on a map.
    @Published private(set) var routeLine: MKPolyline?
    /// Where the way on is, seen from the phone, as an hour on a clock face:
    /// 12 is where the phone points, 9 to the left. Nil without a compass
    /// reading. (Only the hour is published: the exact angle changes with
    /// every compass reading, which would redraw the whole screen.)
    @Published private(set) var clockPosition: Int?
    /// Seconds between Go straight taps: 1 s far from a turn, faster over the
    /// last `rampDistance` before it, down to `fastestInterval` at the turn.
    /// In steps of 0.05 s, so it changes (and is sent to the watch) only now and then.
    @Published private(set) var goStraightInterval: TimeInterval = 1

    /// A turn on the route.
    struct Turn {
        /// Where the turn is.
        let coordinate: CLLocationCoordinate2D
        /// Apple's instruction for it, e.g. "Turn left onto Damrak". Can be empty.
        let instructions: String
        let isLeft: Bool
        /// Metres from the start of the route.
        let along: Double
    }

    /// How the user is moved instead of by the GPS.
    enum Simulation: Identifiable {
        /// Along the route, by `simulateWalk`.
        case walk
        /// Anywhere, by dragging the map (`simulateLocation`).
        case drag

        var id: Self { self }
    }

    let destination: CLLocationCoordinate2D
    /// Nil on a real walk.
    let simulation: Simulation?
    var isSimulated: Bool { simulation != nil }
    /// Simulated walk: metres from the start of the route.
    @Published private(set) var simulatedAlong: Double = 0
    /// Metres from the start of the route to the destination; 0 until there is a route.
    var routeLength: Double { route?.length ?? 0 }

    // Tuning, in metres unless said otherwise.
    /// A turn is signalled from this far before it.
    private let turnWarning: Double = 20
    private let almostThereDistance: Double = 30
    private let arrivedDistance: Double = 10
    /// A rough fix still needs to be this far off the route (or
    /// `rerouteDistance`, if that is further) before a new route is fetched.
    /// See `offRouteLimit`.
    private let offRouteMaximum: Double = 35
    /// Fixes in a row off the route before a new route is fetched, so one
    /// stray fix can't do it.
    private let offRouteFixes = 2
    /// Seconds between two new routes at most.
    private let rerouteInterval: TimeInterval = 6
    /// Fixes less accurate than this aren't used to follow the route.
    private let worstAccuracy: Double = 40
    /// Fixes up to this inaccurate still count as having a signal. Between
    /// streets in a city, 40–80 m is common for a while; that isn't lost.
    private let signalAccuracy: Double = 100
    /// Seconds without any fix within `signalAccuracy` before "Signal lost".
    private let signalTimeout: TimeInterval = 15
    /// Walking speed for the time left, in metres per second.
    private let walkingSpeed: Double = 1.3
    /// How far ahead on the route the dial's pointer aims, in metres. Set in
    /// the settings (`setLookAhead`). With the compass, it also
    /// picks the direction signals, so a longer one signals turns earlier.
    private(set) var lookAhead: Double = RouteNavigator.defaultLookAhead
    static let defaultLookAhead: Double = 4
    static let lookAheadRange: ClosedRange<Double> = 2...30
    /// Further than this from the route counts as off route: a new route is
    /// fetched. Set in the settings (`setRerouteDistance`). With a rough GPS
    /// fix it is raised, see `offRouteLimit`.
    private(set) var rerouteDistance: Double = RouteNavigator.defaultRerouteDistance
    static let defaultRerouteDistance: Double = 20
    static let rerouteDistanceRange: ClosedRange<Double> = 10...50
    /// The user's spot on the route at the last fix, in metres from its start.
    /// Smoothed: see `smoothAlong`.
    private var lastAlong: Double?
    /// How unsure `lastAlong` is: its variance, in square metres.
    private var alongVariance: Double = 0
    /// When the fix behind `lastAlong` was taken.
    private var lastFixTime: Date?
    /// Fixes in a row far from where the user was expected to be.
    private var surpriseCount = 0
    /// How many metres a walker's spot can drift per second that the GPS
    /// speed doesn't explain (stopping, starting, a change of pace).
    private let walkingNoise: Double = 1.5
    /// The same with the step counter's speed: it knows when the user stops
    /// or slows down, so much less is left unexplained.
    private let stepNoise: Double = 0.6
    /// Standing still by the step counter: hardly any drift at all.
    private let standingNoise: Double = 0.2

    private let pedometer = CMPedometer()
    /// Walking speed by the step counter, in metres per second, and when it was
    /// measured; 0 once it says the user stopped. Nil when it isn't known
    /// (no permission, or no steps yet).
    private var stepSpeed: (value: Double, at: Date)?
    /// The step counter's distance so far, for a speed when it gives no pace.
    private var lastSteps: (distance: Double, at: Date)?
    /// The step counter's speed counts for this many seconds after it came in.
    private let stepFreshness: TimeInterval = 5
    /// Seconds the steps may carry the user on without a usable fix.
    private let coastLimit: TimeInterval = 30
    /// Degrees: within this of the way on counts as facing it (Go straight).
    /// Once facing it, the user can turn a bit further before it changes, so a
    /// wobbling compass can't flip the signal back and forth.
    let straightAngle: Double = 30
    /// Degrees: further than this from the way on is Turn around.
    private let backAngle: Double = 135
    /// Each side's extra room before a signal changes back.
    private let hysteresis: Double = 6
    /// Go straight speeds up over this many metres before a turn.
    private let rampDistance: Double = 200
    /// Seconds between Go straight taps far from a turn, and right at it.
    private let slowestInterval: TimeInterval = 1
    private let fastestInterval: TimeInterval = 0.4
    /// A new direction must hold this long before it vibrates.
    private let settleTime: Duration = .milliseconds(500)
    /// Simulated walk: further than this from the destination (e.g. the Xcode
    /// simulator in Cupertino), the walk starts on Damrak instead.
    private let simulationRange: Double = 20_000
    private static let simulationFallbackStart = CLLocationCoordinate2D(latitude: 52.3745, longitude: 4.8960)

    private let locationManager = CLLocationManager()
    private var route: Route?
    /// The turn that is being signalled; it stays until the user is past it,
    /// so GPS jitter around the 20 m mark can't make it flicker.
    private var announcedTurn: Int?
    /// Fixes in a row in which the user walked the wrong way.
    private var wrongWayCount = 0
    /// Fixes in a row off the route.
    private var offRouteCount = 0
    private var isRerouting = false
    private var lastReroute: Date = .distantPast
    private var lastGoodFix: Date = .now
    /// When the last fix good enough to follow the route by came in.
    private var lastUsableFix: Date = .now
    private var signalTimer: Timer?
    /// What the route alone says (turns, wrong way, almost there, arrived).
    private var routePattern: Pattern?
    private var signalIsLost = false
    /// Which way the phone points, degrees clockwise from north.
    private var heading: Double?
    /// A direction waiting to settle before it becomes `pattern`.
    private var pendingPattern: Pattern?
    private var pendingTask: Task<Void, Never>?

    init(destination: CLLocationCoordinate2D, simulation: Simulation? = nil) {
        self.destination = destination
        self.simulation = simulation
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .otherNavigation
        // Every fix, also when standing still (about once a second). With a
        // distance filter, standing still to turn on the spot sends nothing,
        // which looked like a lost signal.
        locationManager.distanceFilter = kCLDistanceFilterNone
    }

    func start() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .failed("Location is off for Tandem. Turn it on in Settings, Privacy, Location Services.")
            return
        default:
            guard !needsPreciseLocation else {
                status = .failed(Self.preciseLocationMessage)
                return
            }
        }
        locationManager.startUpdatingLocation()
        if !isSimulated { startStepCounter() }
        lastGoodFix = .now
        lastUsableFix = .now
        signalTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkSignal()
                self?.coast()
            }
        }
    }

    /// The step counter's speed and stops. Asks for Motion & Fitness the first
    /// time; without it, the GPS speed is used as before.
    private func startStepCounter() {
        guard CMPedometer.isDistanceAvailable() else { return }
        pedometer.startUpdates(from: .now) { [weak self] data, _ in
            guard let data else { return }
            let distance = data.distance?.doubleValue
            // Seconds per metre, over the last few seconds.
            let pace = data.currentPace?.doubleValue
            let at = data.endDate
            Task { @MainActor in self?.handleSteps(distance: distance, pace: pace, at: at) }
        }
        if CMPedometer.isPedometerEventTrackingAvailable() {
            // Stopping and starting come in straight away, before the next update.
            pedometer.startEventUpdates { [weak self] event, _ in
                guard let event else { return }
                let paused = event.type == .pause
                Task { @MainActor in
                    guard let self else { return }
                    if paused {
                        self.stepSpeed = (0, .now)
                    } else if let speed = self.stepSpeed, speed.value == 0 {
                        // Walking again: about the usual pace until the counter says.
                        self.stepSpeed = (self.walkingSpeed, .now)
                    }
                }
            }
        }
    }

    private func handleSteps(distance: Double?, pace: Double?, at: Date) {
        var speed: Double?
        if let pace, pace > 0 {
            speed = 1 / pace
        } else if let distance, let last = lastSteps, at.timeIntervalSince(last.at) > 0.5 {
            speed = (distance - last.distance) / at.timeIntervalSince(last.at)
        }
        if let distance { lastSteps = (distance, at) }
        // Walking speeds only: a stray number is left out.
        guard let speed, (0...3).contains(speed) else { return }
        stepSpeed = (speed, .now)
    }

    /// The step counter's speed, if it is recent.
    private var currentStepSpeed: Double? {
        guard let stepSpeed, Date.now.timeIntervalSince(stepSpeed.at) <= stepFreshness else { return nil }
        return stepSpeed.value
    }

    /// With Approximate Location the position can be off by hundreds of
    /// metres, far too rough to find a turn by. (A simulated walk only needs
    /// the start, so it does without.)
    private var needsPreciseLocation: Bool {
        !isSimulated && locationManager.accuracyAuthorization == .reducedAccuracy
    }
    private static let preciseLocationMessage =
        "Precise Location is off for Tandem. Turn it on in Settings, Privacy, Location Services, Tandem."

    func stop() {
        locationManager.stopUpdatingLocation()
        pedometer.stopUpdates()
        pedometer.stopEventUpdates()
        signalTimer?.invalidate()
        signalTimer = nil
        pendingTask?.cancel()
    }

    /// Starts the GPS afresh and drops what was worked out from the old fixes
    /// (walking the wrong way, the turn being signalled, a direction waiting
    /// to settle), so the next fixes decide everything again.
    func recalibrate() {
        guard status == .guiding, pattern != .arrived else { return }
        pendingTask?.cancel()
        pendingPattern = nil
        wrongWayCount = 0
        offRouteCount = 0
        announcedTurn = nil
        // Find the spot on the route afresh, anywhere along it.
        lastAlong = nil
        guard !isSimulated else { return }
        locationManager.stopUpdatingLocation()
        lastGoodFix = .now
        locationManager.startUpdatingLocation()
    }

    /// A new compass reading: which way the phone points, degrees from north.
    func setHeading(_ degrees: Double?) {
        heading = degrees
        refreshPattern()
    }

    // MARK: - Simulated walk

    /// Simulated walk: moves the user this many metres along the route,
    /// backwards when negative.
    func simulateWalk(by metres: Double) {
        simulateWalk(to: simulatedAlong + metres)
    }

    /// Simulated walk: puts the user this many metres from the start of the
    /// route, facing the way they moved.
    func simulateWalk(to along: Double) {
        guard simulation == .walk, let route, status == .guiding, pattern != .arrived else { return }
        let target = min(max(along, 0), route.length)
        let moved = target - simulatedAlong
        guard abs(moved) > 0.01 else { return }
        simulatedAlong = target
        placeSimulatedUser(on: route, backwards: moved < 0, moving: true)
    }

    /// Map simulation: puts the user here, facing the way they were moved.
    /// Moves under a metre are left for the next one.
    func simulateLocation(_ coordinate: CLLocationCoordinate2D) {
        guard simulation == .drag, route != nil, status == .guiding, pattern != .arrived,
              let last = lastLocation else { return }
        guard distance(last.coordinate, coordinate) >= 1 else { return }
        handle(CLLocation(coordinate: coordinate, altitude: 0,
                          horizontalAccuracy: 5, verticalAccuracy: -1,
                          course: initialBearing(last.coordinate, coordinate),
                          courseAccuracy: 10, speed: walkingSpeed,
                          speedAccuracy: 1, timestamp: .now))
    }

    /// A made-up GPS fix on the route at `simulatedAlong`: spot-on, and
    /// heading the way the user walks (against the route when going back).
    private func placeSimulatedUser(on route: Route, backwards: Bool, moving: Bool) {
        let along = route.bearing(at: simulatedAlong)
        let course = backwards ? (along + 180).truncatingRemainder(dividingBy: 360) : along
        handle(CLLocation(coordinate: route.coordinate(at: simulatedAlong), altitude: 0,
                          horizontalAccuracy: 5, verticalAccuracy: -1, course: course,
                          courseAccuracy: 10, speed: moving ? walkingSpeed : 0,
                          speedAccuracy: 1, timestamp: .now))
    }

    // MARK: - Following the route

    /// A fix from the GPS. On a simulated walk, only the first one counts:
    /// it is where the route starts.
    private func handleGPS(_ location: CLLocation) {
        if isSimulated, route != nil || isRerouting { return }
        handle(location)
    }

    /// `isCoasting`: not a fix, but where the steps have carried the user
    /// (see `coast`); it doesn't count as having a signal.
    private func handle(_ location: CLLocation, isCoasting: Bool = false) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= signalAccuracy else { return }
        if !isCoasting {
            lastGoodFix = .now
            if signalIsLost {
                signalIsLost = false
                refreshPattern()
            }
        }
        // Too rough to follow the route by: keep the last signal until a better
        // fix; meanwhile the steps carry the user on (`coast`).
        guard location.horizontalAccuracy <= worstAccuracy else { return }
        if !isCoasting { lastUsableFix = .now }
        lastLocation = location

        guard let route else {
            guard status == .locating else { return }
            if isSimulated, distance(location.coordinate, destination) > simulationRange {
                fetchRoute(from: Self.simulationFallbackStart)
            } else {
                fetchRoute(from: location.coordinate)
            }
            return
        }

        // Near the last spot first, so a stretch of the route that passes close
        // by (round a block, back along the other side of a street) can't
        // catch the user. Anywhere along the route if that is too far off.
        let offRoute = offRouteLimit(location)
        var point = route.project(location.coordinate, within: lastAlong.map { ($0 - 40)...($0 + 80) })
        if point.offset > offRoute { point = route.project(location.coordinate) }
        // Coasting, the spot is already the steps' guess.
        if !isCoasting { point.along = smoothAlong(point.along, location: location, route: route) }

        remaining = max(0, route.length - point.along)
        progress = route.length > 0 ? min(1, point.along / route.length) : 1

        // Straight-line distance too, so a route ending just past the stop still arrives.
        let toDestination = location.distance(from: CLLocation(latitude: destination.latitude,
                                                               longitude: destination.longitude))
        if min(remaining, toDestination) <= arrivedDistance {
            remaining = 0
            progress = 1
            nextTurn = nil
            bearingAhead = nil
            routePattern = .arrived
            refreshPattern()
            stop()
            return
        }

        if point.offset > offRoute {
            offRouteCount += 1
            if offRouteCount >= offRouteFixes { reroute(from: location.coordinate) }
            return
        }
        offRouteCount = 0

        // Wrong way: walking against the route for a few fixes in a row.
        if location.speed > 0.6, location.course >= 0, (0...60).contains(location.courseAccuracy) {
            let difference = angleBetween(location.course, route.bearing(at: point.along))
            if difference > 135 {
                wrongWayCount += 1
            } else if difference < 60 {
                wrongWayCount = 0
            }
        }

        let nextTurn = route.turns.first { $0.along > point.along }
        distanceToNext = (nextTurn?.along ?? route.length) - point.along

        if let announcedTurn, announcedTurn < route.turns.count,
           route.turns[announcedTurn].along + 5 < point.along {
            self.announcedTurn = nil
        }
        if let nextTurn, distanceToNext <= turnWarning,
           let index = route.turns.firstIndex(where: { $0.along == nextTurn.along }) {
            announcedTurn = index
        }
        self.nextTurn = announcedTurn.flatMap { $0 < route.turns.count ? route.turns[$0] : nil } ?? nextTurn
        lastAlong = point.along
        updateBearingAhead(on: route, from: point.along)

        // Closer to the turn (or the destination, after the last turn): faster.
        let closeness = 1 - min(1, max(0, distanceToNext / rampDistance))
        let interval = slowestInterval - (slowestInterval - fastestInterval) * closeness
        let stepped = (interval / 0.05).rounded() * 0.05
        if stepped != goStraightInterval { goStraightInterval = stepped }

        if wrongWayCount >= 3 {
            routePattern = .turnAround
        } else if remaining <= almostThereDistance {
            routePattern = .almostThere
        } else if let announcedTurn, announcedTurn < route.turns.count {
            let turn = route.turns[announcedTurn]
            distanceToNext = max(0, turn.along - point.along)
            routePattern = turn.isLeft ? .left : .right
        } else {
            routePattern = .forward
        }
        refreshPattern()
    }

    /// The spot on the route from this fix, blended with where the user was
    /// expected to be by now (the last spot, moved on at the GPS speed). The
    /// blend leans towards whichever is surer: a fix 5 m accurate counts for a
    /// lot, one 35 m accurate for little. A one-dimensional Kalman filter.
    /// So the spot doesn't jump back and forth with the GPS, and turns are
    /// signalled at a steady distance. Several surprising fixes in a row are
    /// believed: then the user really is somewhere else.
    private func smoothAlong(_ measured: Double, location: CLLocation, route: Route) -> Double {
        let measuredVariance = pow(max(location.horizontalAccuracy, 3), 2)
        defer { lastFixTime = location.timestamp }
        guard !isSimulated, let lastAlong, let lastFixTime else {
            alongVariance = measuredVariance
            surpriseCount = 0
            return measured
        }
        let seconds = min(max(location.timestamp.timeIntervalSince(lastFixTime), 0), 10)

        // Walking speed along the route: forwards, backwards or across it.
        // How fast from the step counter if it knows, else from the GPS; which
        // way from the GPS's course if it is sure of it, else forwards.
        let courseIsGood = location.course >= 0 && (0...45).contains(location.courseAccuracy)
        let along = courseIsGood
            ? cos(signedAngle(from: route.bearing(at: lastAlong), to: location.course) * .pi / 180)
            : 1
        let steps = currentStepSpeed
        var velocity = 0.0
        if let steps {
            velocity = steps * along
        } else if location.speed >= 0, courseIsGood {
            velocity = location.speed * along
        }
        let noise = steps.map { $0 == 0 ? standingNoise : stepNoise } ?? walkingNoise
        let predicted = lastAlong + velocity * seconds
        let predictedVariance = alongVariance + pow(noise, 2) * seconds

        if abs(measured - predicted) > 3 * (predictedVariance + measuredVariance).squareRoot() {
            surpriseCount += 1
            if surpriseCount >= 3 {
                surpriseCount = 0
                alongVariance = measuredVariance
                return measured
            }
            // Probably a stray fix: keep to the prediction for now.
            alongVariance = predictedVariance
            return min(max(predicted, 0), route.length)
        }
        surpriseCount = 0
        let gain = predictedVariance / (predictedVariance + measuredVariance)
        alongVariance = (1 - gain) * predictedVariance
        return min(max(predicted + gain * (measured - predicted), 0), route.length)
    }

    /// Measured from the user's spot on the route, not their GPS position: a
    /// few metres ahead, a GPS position a few metres to the side would swing
    /// it right round.
    private func updateBearingAhead(on route: Route, from along: Double) {
        let here = route.coordinate(at: along)
        let ahead = route.coordinate(at: along + lookAhead)
        if distance(here, ahead) > 0.5 {
            bearingAhead = initialBearing(here, ahead)
        }
    }

    /// A new look-ahead from the settings: the pointer (and, with the
    /// compass, the signal) moves to it straight away.
    func setLookAhead(_ metres: Double) {
        let clamped = min(max(metres, Self.lookAheadRange.lowerBound), Self.lookAheadRange.upperBound)
        guard clamped != lookAhead else { return }
        lookAhead = clamped
        guard let route, let lastAlong, status == .guiding, pattern != .arrived else { return }
        updateBearingAhead(on: route, from: lastAlong)
        refreshPattern()
    }

    /// A new reroute distance from the settings, used from the next fix on.
    func setRerouteDistance(_ metres: Double) {
        rerouteDistance = min(max(metres, Self.rerouteDistanceRange.lowerBound),
                              Self.rerouteDistanceRange.upperBound)
    }

    /// Without a usable fix for a moment (between tall buildings, say), the
    /// steps carry the user on along the route, forwards, at the step
    /// counter's speed: the turns still come at about the right spot. Not
    /// for longer than `coastLimit`, nor while the counter says nothing.
    private func coast() {
        guard status == .guiding, pattern != .arrived, !isSimulated, let route, let lastAlong,
              let lastFixTime, let speed = currentStepSpeed, speed > 0 else { return }
        let sinceFix = Date.now.timeIntervalSince(lastUsableFix)
        guard sinceFix > 1.5, sinceFix <= coastLimit else { return }
        let seconds = min(max(Date.now.timeIntervalSince(lastFixTime), 0), 2)
        let along = min(lastAlong + speed * seconds, route.length)
        self.lastFixTime = .now
        alongVariance += pow(stepNoise, 2) * seconds
        // A made-up fix on the route there, about as sure as the guess.
        let coordinate = route.coordinate(at: along)
        handle(CLLocation(coordinate: coordinate, altitude: 0,
                          horizontalAccuracy: min(worstAccuracy, max(5, alongVariance.squareRoot())),
                          verticalAccuracy: -1, course: route.bearing(at: along), courseAccuracy: -1,
                          speed: speed, speedAccuracy: -1, timestamp: .now),
               isCoasting: true)
    }

    private func checkSignal() {
        guard status == .guiding, pattern != .arrived, !isSimulated else { return }
        if Date.now.timeIntervalSince(lastGoodFix) > signalTimeout {
            signalIsLost = true
            refreshPattern()
        }
    }

    // MARK: - Picking the signal

    /// Works out the signal from the route, the GPS signal and the compass.
    private func refreshPattern() {
        guard let routePattern else { return }

        let wanted: Pattern
        if routePattern == .arrived {
            wanted = .arrived
        } else if signalIsLost {
            wanted = .signalLost
        } else if let heading, let bearingAhead {
            let angle = signedAngle(from: heading, to: bearingAhead)
            setClockPosition(angle)
            let facing = facingPattern(angle)
            // Almost there only while facing the right way; otherwise the turn comes first.
            wanted = facing == .forward && routePattern == .almostThere ? .almostThere : facing
        } else {
            if clockPosition != nil { clockPosition = nil }
            wanted = routePattern
        }
        apply(wanted)
    }

    /// -60 degrees is 10 o'clock.
    private func setClockPosition(_ angle: Double) {
        let hour = Int((angle / 30).rounded()) % 12
        let clock = hour <= 0 ? hour + 12 : hour
        if clock != clockPosition { clockPosition = clock }
    }

    /// Go straight, turn left or right, or turn around, for the way on at
    /// `angle` degrees from where the phone points.
    private func facingPattern(_ angle: Double) -> Pattern {
        let size = abs(angle)
        // The signal on now gets a few degrees extra, so it doesn't flicker at the edge.
        let facingNow = pattern == .forward || pattern == .almostThere
        let straight = straightAngle + (facingNow ? hysteresis : -hysteresis)
        let back = backAngle + (pattern == .turnAround ? -hysteresis : hysteresis)
        if size <= straight { return .forward }
        if size >= back { return .turnAround }
        return angle < 0 ? .left : .right
    }

    /// Arrived, Signal lost and the first signal show straight away; a new
    /// direction only once it has held for `settleTime`, so turning past
    /// one on the way to another doesn't make it buzz.
    private func apply(_ wanted: Pattern) {
        guard wanted != pattern else {
            pendingTask?.cancel()
            pendingPattern = nil
            return
        }
        if pattern == nil || wanted == .arrived || wanted == .signalLost || pattern == .signalLost {
            pendingTask?.cancel()
            pendingPattern = nil
            pattern = wanted
            return
        }
        guard wanted != pendingPattern else { return }
        pendingPattern = wanted
        pendingTask?.cancel()
        pendingTask = Task { [weak self, settleTime] in
            try? await Task.sleep(for: settleTime)
            guard !Task.isCancelled, let self, self.pendingPattern == wanted else { return }
            self.pendingPattern = nil
            self.pattern = wanted
        }
    }

    /// How far from the route a fix may be before it counts as off route:
    /// `rerouteDistance`, or for a rough fix its accuracy plus a margin for the
    /// pavement beside the street's middle line (up to `offRouteMaximum`).
    /// At 20 m: 5 m accurate gives 20 m, 25 m accurate or worse 35 m.
    private func offRouteLimit(_ location: CLLocation) -> Double {
        max(rerouteDistance, min(offRouteMaximum, location.horizontalAccuracy + 10))
    }

    private func reroute(from coordinate: CLLocationCoordinate2D) {
        guard !isRerouting, Date.now.timeIntervalSince(lastReroute) > rerouteInterval else { return }
        lastReroute = .now
        fetchRoute(from: coordinate)
    }

    private func fetchRoute(from start: CLLocationCoordinate2D) {
        isRerouting = true
        if route == nil { status = .routing }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        MKDirections(request: request).calculate { [weak self] response, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isRerouting = false
                if let mkRoute = response?.routes.first {
                    let isFirst = self.route == nil
                    self.route = Route(mkRoute)
                    self.lastAlong = nil
                    self.routeLine = mkRoute.polyline
                    self.announcedTurn = nil
                    self.wrongWayCount = 0
                    self.offRouteCount = 0
                    self.status = .guiding
                    if self.isSimulated { self.locationManager.stopUpdatingLocation() }
                    // From here on, only the Forward and Back buttons (or the
                    // map) move the user: from the start. A reroute while
                    // dragging carries on from where the map put them.
                    if let route = self.route, self.simulation == .walk || (self.isSimulated && isFirst) {
                        self.simulatedAlong = 0
                        self.placeSimulatedUser(on: route, backwards: false, moving: false)
                    } else if let lastLocation = self.lastLocation {
                        self.handle(lastLocation)
                    }
                } else if self.route == nil {
                    // A failed reroute keeps the old route; a failed first route ends here.
                    self.status = .failed(error?.localizedDescription
                                          ?? "No walking route found. Check the internet connection.")
                    self.stop()
                }
            }
        }
    }
}

extension RouteNavigator: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.handleGPS(location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted {
                self.status = .failed("Location is off for Tandem. Turn it on in Settings, Privacy, Location Services.")
                self.stop()
            } else if self.needsPreciseLocation {
                self.status = .failed(Self.preciseLocationMessage)
                self.stop()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Temporary failures (e.g. indoors) end up as "Signal lost" through the timer.
    }
}

// MARK: - Showing a route on a map

/// The route with its start and the destination, with room around it: extra
/// at the top for the destination pin, which stands up from its point. Never
/// closer than 300 m across, so a short route doesn't fill the map with one street.
func routeFraming(_ polyline: MKPolyline, destination: CLLocationCoordinate2D) -> MKMapRect {
    var rect = polyline.boundingMapRect
        .union(MKMapRect(origin: MKMapPoint(destination), size: MKMapSize(width: 0, height: 0)))
    let minimum = 300 * MKMapPointsPerMeterAtLatitude(destination.latitude)
    if rect.width < minimum { rect = rect.insetBy(dx: -(minimum - rect.width) / 2, dy: 0) }
    if rect.height < minimum { rect = rect.insetBy(dx: 0, dy: -(minimum - rect.height) / 2) }
    let side = rect.width * 0.2
    let vertical = rect.height * 0.2
    return MKMapRect(x: rect.minX - side, y: rect.minY - vertical * 1.75,
                     width: rect.width + side * 2, height: rect.height + vertical * 2.75)
}

// MARK: - Route geometry

/// The route as a line of points, with the turns along it.
private struct Route {
    typealias Turn = RouteNavigator.Turn

    let points: [CLLocationCoordinate2D]
    /// Metres from the start of the route to each point.
    let cumulative: [Double]
    private(set) var turns: [Turn]
    var length: Double { cumulative.last ?? 0 }

    /// Bends sharper than this count as a turn (degrees).
    private static let turnAngle: Double = 35

    init(_ route: MKRoute) {
        let polyline = route.polyline
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                   count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        points = coordinates

        var distances: [Double] = [0]
        for i in 1..<max(1, coordinates.count) {
            distances.append(distances[i - 1] + distance(coordinates[i - 1], coordinates[i]))
        }
        cumulative = distances

        turns = []
        // Each MapKit step after the first starts at a manoeuvre. Its direction
        // comes from the bend in the line there: the bearing just before and after.
        var found: [Turn] = []
        for step in route.steps.dropFirst() where step.polyline.pointCount > 0 {
            let start = Self.start(of: step.polyline)
            let along = project(start).along
            guard along > 1, along < length - 1 else { continue }
            let bend = signedAngle(from: bearing(at: along - 8), to: bearing(at: along + 8))
            if abs(bend) >= Self.turnAngle {
                found.append(Turn(coordinate: start, instructions: step.instructions,
                                  isLeft: bend < 0, along: along))
            }
        }
        turns = found
    }

    private static func start(of polyline: MKPolyline) -> CLLocationCoordinate2D {
        var first = kCLLocationCoordinate2DInvalid
        polyline.getCoordinates(&first, range: NSRange(location: 0, length: 1))
        return first
    }

    /// The closest point on the route: how far along it is, and how far away.
    /// With `range`, only the part of the route that many metres from its start.
    func project(_ coordinate: CLLocationCoordinate2D,
                 within range: ClosedRange<Double>? = nil) -> (along: Double, offset: Double) {
        guard points.count > 1 else { return (0, distance(coordinate, points.first ?? coordinate)) }
        var best = (along: 0.0, offset: Double.greatestFiniteMagnitude)
        for i in 1..<points.count {
            if let range, cumulative[i] < range.lowerBound || cumulative[i - 1] > range.upperBound { continue }
            let (fraction, offset) = projectOnSegment(coordinate, points[i - 1], points[i])
            if offset < best.offset {
                best = (cumulative[i - 1] + fraction * (cumulative[i] - cumulative[i - 1]), offset)
            }
        }
        return best
    }

    /// The point on the route this many metres from its start.
    func coordinate(at along: Double) -> CLLocationCoordinate2D {
        guard points.count > 1 else { return points.first ?? kCLLocationCoordinate2DInvalid }
        let clamped = min(max(along, 0), length)
        let segment = (1..<points.count).first { cumulative[$0] >= clamped } ?? points.count - 1
        let a = points[segment - 1], b = points[segment]
        let segmentLength = cumulative[segment] - cumulative[segment - 1]
        let t = segmentLength > 0 ? (clamped - cumulative[segment - 1]) / segmentLength : 0
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// The direction of the route at this distance along it, in degrees from north.
    func bearing(at along: Double) -> Double {
        guard points.count > 1 else { return 0 }
        let clamped = min(max(along, 0), cumulative.last!)
        let segment = (1..<points.count).first { cumulative[$0] >= clamped } ?? points.count - 1
        return initialBearing(points[segment - 1], points[segment])
    }
}

// MARK: - Small geometry helpers (flat-earth is fine at walking distances)

private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    CLLocation(latitude: a.latitude, longitude: a.longitude)
        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
}

/// Projects `p` on the segment a–b: the fraction along it (0 to 1) and the distance in metres.
private func projectOnSegment(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D,
                              _ b: CLLocationCoordinate2D) -> (Double, Double) {
    let metresPerDegree = 111_320.0
    let scale = cos(a.latitude * .pi / 180)
    let bx = (b.longitude - a.longitude) * metresPerDegree * scale
    let by = (b.latitude - a.latitude) * metresPerDegree
    let px = (p.longitude - a.longitude) * metresPerDegree * scale
    let py = (p.latitude - a.latitude) * metresPerDegree
    let lengthSquared = bx * bx + by * by
    let t = lengthSquared > 0 ? min(1, max(0, (px * bx + py * by) / lengthSquared)) : 0
    let dx = px - t * bx, dy = py - t * by
    return (t, (dx * dx + dy * dy).squareRoot())
}

private func initialBearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}

/// From one bearing to another, -180 to 180 degrees; negative is a left turn.
private func signedAngle(from: Double, to: Double) -> Double {
    var difference = (to - from).truncatingRemainder(dividingBy: 360)
    if difference > 180 { difference -= 360 }
    if difference < -180 { difference += 360 }
    return difference
}

/// The size of the angle between two bearings, 0 to 180 degrees.
private func angleBetween(_ a: Double, _ b: Double) -> Double {
    abs(signedAngle(from: a, to: b))
}
