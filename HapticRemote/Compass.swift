//
//  Compass.swift
//  HapticRemote (iPhone)
//
//  Which way the phone points (HeadingTracker), and the fading cone that
//  shows it: on the location dot (LocationDot) on the maps, and around the dial on
//  the navigation screen, where it points the way the route goes just ahead.
//
//  Turns come from the gyroscope (Core Motion): quick, the right size, and
//  right however far the phone is tilted. Where north is comes from the
//  compass (CLHeading), slowly and only when it can be trusted, and from the
//  GPS's direction of travel while walking. The plain compass is the
//  fallback on a phone without a gyroscope.
//

import Combine
import CoreLocation
import CoreMotion
import SwiftUI

/// A wedge pointing up from the middle of its bottom edge, with a rounded far end.
struct Cone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.12))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.12))
        path.closeSubpath()
        return path
    }
}

/// The compass: which way the top of the phone points.
///
/// Turning is measured by the gyroscope alone, so a quarter turn always shows
/// as a quarter turn. The magnetic compass only says where north is, and is
/// easily bent in a city (trams and their overhead wires, steel bridges,
/// parked cars): left to steer the reading, it showed turns too small and
/// then drifted. So it only nudges the gyroscope's north, slowly, and not
/// while the user turns or when the magnetic field is plainly disturbed. While
/// walking (`walked`), the GPS's direction of travel nudges it too: that isn't
/// magnetic at all.
@MainActor
final class HeadingTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// Degrees clockwise from north, nil while unknown. Never wraps from 359
    /// back to 0, so the cone turns the short way instead of spinning round.
    @Published private(set) var degrees: Double?
    /// `degrees` without the hand's sway while walking: the way the user
    /// faces, for turning the maps. Swinging the phone back and forth leaves
    /// it be; turning on purpose, and staying turned, moves it straight away.
    /// It glides there on a spring, a step every frame of the display, so a
    /// map turned with it turns smoothly. Unwrapped like `degrees`.
    @Published private(set) var steadyDegrees: Double?
    /// Which way the map is turned (0 = north up), unwrapped the same way, so
    /// the cone stays right when the user rotates the map.
    @Published private(set) var mapHeading: Double = 0

    /// True while `recalibrate()` runs: the user is waving the phone about,
    /// so the readings mean nothing for the way to go.
    @Published private(set) var isCalibrating = false
    /// How far off the last compass reading may be, in degrees; negative when unknown.
    private var accuracy: Double = -1

    /// Where the cone points on screen: degrees clockwise from the top of the map.
    var facing: Double? { degrees.map { $0 - mapHeading } }

    /// Writes down a real walk's compass, if it is being recorded.
    var recorder: TripRecorder?

    private let manager = CLLocationManager()
    private let motion = CMMotionManager()
    /// False when Core Motion can't give a heading on this phone, or failed:
    /// then the plain compass readings are used.
    private var usesMotion = CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical)
    /// The way the phone points by the gyroscope, as a smoothed unit vector in
    /// its own frame (which starts out facing an arbitrary way).
    private var smoothed: (x: Double, y: Double)?
    /// The gyroscope's way, degrees clockwise from its own arbitrary start.
    private var gyroYaw: Double?
    /// Recent gyroscope ways, unwrapped, to tell if the user is turning.
    private var recentYaw: [(time: TimeInterval, yaw: Double)] = []
    /// Degrees from the gyroscope's way to the true one: where its north is.
    /// Nil until the first compass reading.
    private var north: Double?
    /// When `north` was first set. For a while after, it is still rough, so
    /// it follows the compass quickly and believes even big differences.
    private var northSince: TimeInterval = 0
    /// When the compass last nudged `north`.
    private var lastCompassNudge: TimeInterval?

    /// Where `steadyDegrees` is gliding to: the way the user faces, decided
    /// from the readings. Unwrapped.
    private var steadyTarget: Double?
    /// How fast `steadyDegrees` turns now, degrees a second (the spring's speed).
    private var steadySpeed: Double = 0
    /// Steps `steadyDegrees` each frame while it glides.
    private let steadyLoop = FrameLoop()
    /// `degrees` averaged over the last second or so, which the sway evens out in.
    private var averaged: Double?
    /// Since when the phone has been pointing well away from `steadyTarget`.
    private var awaySince: TimeInterval?
    private var lastSteadyUpdate: TimeInterval?

    // Tuning.
    /// Seconds the average takes to follow most of a change.
    private let swayAverage: TimeInterval = 1.2
    /// Degrees the average may drift from the steady way before it moves:
    /// a street bending, or turning slowly.
    private let steadyDeadband: Double = 10
    /// Degrees further than this, held for `turnHold` seconds: a turn on
    /// purpose, followed at once. A swing of the hand comes back sooner.
    private let deliberateTurn: Double = 35
    private let turnHold: TimeInterval = 0.5
    /// The glide's spring: about this many seconds to settle, without overshooting.
    private let glideTime: Double = 0.7
    /// It never turns faster than this, degrees a second, nor speeds up
    /// faster than this, degrees a second per second: it eases into a turn.
    private let glideTopSpeed: Double = 180
    private let glideAcceleration: Double = 600
    /// Degrees the user may turn within `turnWindow` that still count as
    /// holding steady; turning more, the compass lags behind and is ignored.
    private let steadyTurn: Double = 15
    private let turnWindow: TimeInterval = 1.5
    /// Seconds for the compass to move north most of the way to its reading:
    /// at first, and once settled with a good reading.
    private let roughSettle: TimeInterval = 1.5
    private let steadySettle: TimeInterval = 10
    /// Seconds after `north` is first set that it counts as rough.
    private let roughPeriod: TimeInterval = 8
    /// Once settled, a reading this many degrees off counts for half; much
    /// further off, hardly at all, unless it stays that way.
    private let disagreement: Double = 30
    /// Compass readings less sure than this are left out, once north is known.
    private let worstAccuracy: Double = 45
    /// The Earth's magnetic field is about 49 µT in the Netherlands; well
    /// outside this, something nearby bends it.
    private let plausibleField: ClosedRange<Double> = 25...75

    override init() {
        super.init()
        manager.delegate = self
        // Every degree, so the cone keeps up while the user turns.
        manager.headingFilter = 1
    }

    func start() {
        isForgotten = false
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
        startMotion()
    }

    func stop() {
        manager.stopUpdatingHeading()
        motion.stopDeviceMotionUpdates()
        resetGyro()
    }

    /// The gyroscope's frame starts afresh with each start, so its north goes too.
    private func resetGyro() {
        smoothed = nil
        gyroYaw = nil
        recentYaw = []
        north = nil
        lastCompassNudge = nil
        resetSteady()
    }

    private func resetSteady() {
        steadyLoop.stop()
        steadyTarget = nil
        steadySpeed = 0
        averaged = nil
        awaySince = nil
        lastSteadyUpdate = nil
    }

    private func startMotion() {
        guard usesMotion, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data {
                    self.handle(data)
                } else if error != nil {
                    // Back to the plain compass.
                    self.usesMotion = false
                    self.motion.stopDeviceMotionUpdates()
                    self.resetGyro()
                }
            }
        }
    }

    /// A Core Motion reading. Its rows are the phone's axes in a frame where z
    /// points up and x and y lie flat (facing an arbitrary way). The phone's
    /// top edge plus the direction out of its back is "forward" both held flat
    /// and held up (and anywhere between), so tilting the phone doesn't turn
    /// the reading.
    private func handle(_ data: CMDeviceMotion) {
        guard !isForgotten else { return }
        let r = data.attitude.rotationMatrix
        let x = r.m21 - r.m31
        let y = r.m22 - r.m32
        let length = (x * x + y * y).squareRoot()
        guard length > 0.1 else { return }

        // A little smoothing (about a sixth of a second) against hand shake.
        let previous = smoothed ?? (x / length, y / length)
        let blend = 0.3
        let next = (x: previous.x + (x / length - previous.x) * blend,
                    y: previous.y + (y / length - previous.y) * blend)
        smoothed = next

        let yaw = (atan2(-next.y, next.x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let unwrapped = recentYaw.last.map { Self.unwrap(yaw, after: $0.yaw) } ?? yaw
        recentYaw.append((data.timestamp, unwrapped))
        recentYaw.removeAll { data.timestamp - $0.time > 3 }
        gyroYaw = yaw
        publish()
    }

    /// The gyroscope's way, turned to true north.
    private func publish() {
        guard let gyroYaw, let north else { return }
        let value = (gyroYaw + north + 720).truncatingRemainder(dividingBy: 360)
        guard let degrees else {
            self.degrees = value
            updateSteady(value)
            return
        }
        // Every degree, so the cone keeps up, but not every tiny tremble.
        let unwrapped = Self.unwrap(value, after: degrees)
        if abs(unwrapped - degrees) >= 1 { self.degrees = unwrapped }
        updateSteady(unwrapped)
        recorder?.heading(live: unwrapped, steady: steadyDegrees, north: north)
    }

    /// Replaying a recorded walk: the way the phone pointed then, in place of
    /// the sensors (which stay off). The steady way is worked out afresh.
    func play(_ value: Double) {
        isForgotten = false
        let unwrapped = degrees.map { Self.unwrap(value, after: $0) } ?? value
        degrees = unwrapped
        updateSteady(unwrapped)
    }

    /// A new reading for `steadyTarget`: the average creeps after it, and a
    /// big turn that holds is taken at once. `steadyDegrees` then glides there.
    private func updateSteady(_ value: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastSteadyUpdate = now }
        guard let steady = steadyTarget, let averaged else {
            steadyTarget = value
            steadyDegrees = value
            steadySpeed = 0
            averaged = value
            return
        }
        let seconds = min(1, now - (lastSteadyUpdate ?? now))
        let current = Self.unwrap(value, after: averaged)
        let average = averaged + (current - averaged) * min(1, seconds / swayAverage)
        self.averaged = average

        let away = Self.unwrap(value, after: steady) - steady
        if abs(away) > deliberateTurn {
            let since = awaySince ?? now
            awaySince = since
            if now - since >= turnHold {
                // Turned on purpose: there now, and the average with it.
                retargetSteady(steady + away)
                self.averaged = steady + away
                awaySince = nil
                return
            }
        } else {
            awaySince = nil
        }
        let drift = Self.unwrap(average, after: steady) - steady
        if abs(drift) > steadyDeadband {
            // Only the part past the deadband, so it moves on smoothly.
            retargetSteady(steady + drift - (drift > 0 ? steadyDeadband : -steadyDeadband))
        }
    }

    private func retargetSteady(_ target: Double) {
        steadyTarget = target
        steadyLoop.run { [weak self] seconds in self?.glideSteady(seconds) ?? false }
    }

    /// One frame of the glide: a critically damped spring towards
    /// `steadyTarget`, so it starts gently and comes to rest without a bump.
    /// False once there.
    private func glideSteady(_ seconds: Double) -> Bool {
        guard let target = steadyTarget, let steady = steadyDegrees else { return false }
        let dt = min(seconds, 0.05)
        // ω for settling (to about 2%) in `glideTime`.
        let omega = 5.8 / glideTime
        let offset = target - steady
        let acceleration = omega * omega * offset - 2 * omega * steadySpeed
        steadySpeed += min(max(acceleration, -glideAcceleration), glideAcceleration) * dt
        steadySpeed = min(max(steadySpeed, -glideTopSpeed), glideTopSpeed)
        let next = steady + steadySpeed * dt
        if abs(target - next) < 0.05, abs(steadySpeed) < 0.5 {
            steadyDegrees = target
            steadySpeed = 0
            return false
        }
        steadyDegrees = next
        return true
    }

    /// Degrees the phone has turned through in the last `seconds`.
    private func turned(within seconds: TimeInterval) -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        let window = recentYaw.filter { now - $0.time <= seconds }.map(\.yaw)
        guard let low = window.min(), let high = window.max() else { return 0 }
        return high - low
    }

    /// Moves the gyroscope's north towards one where the phone points to
    /// `heading` (true degrees), by `gain` (0 to 1) of the difference.
    private func nudgeNorth(towards heading: Double, gain: Double) {
        guard let gyroYaw else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let wanted = heading - gyroYaw
        guard let north else {
            self.north = wanted
            northSince = now
            publish()
            return
        }
        var difference = (wanted - north).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        // Settled: a reading far off is most likely bent, so it counts for little.
        let isRough = now - northSince < roughPeriod
        let trust = isRough ? 1 : 1 / (1 + pow(difference / disagreement, 2))
        self.north = north + difference * min(1, gain * trust)
        publish()
    }

    /// A GPS fix while walking: the direction of travel, when it is sure of it.
    /// Used only while the user walks steadily one way with the phone pointing
    /// roughly that way too, as it does following the dial.
    func walked(_ location: CLLocation) {
        guard usesMotion, !isCalibrating, let degrees, location.course >= 0, location.speed >= 0.9,
              (0...20).contains(location.courseAccuracy),
              turned(within: 3) <= steadyTurn else { return }
        var difference = (location.course - degrees).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        guard abs(difference) <= 40 else { return }
        // About once a second: most of the way there in some 7 seconds.
        nudgeNorth(towards: location.course, gain: 0.15)
    }

    /// Stops, and forgets the last reading: the cones and the dial's pointer hide.
    func stopAndForget() {
        stop()
        isForgotten = true
        degrees = nil
        resetSteady()
        steadyDegrees = nil
    }

    /// Set by `stopAndForget`, so a reading still on its way doesn't bring it back.
    private var isForgotten = false

    /// Starts the compass afresh and waits while the user moves the phone in
    /// a figure eight, which is how iOS calibrates it. True once the readings
    /// have been accurate for a moment; false after `timeout` without that.
    /// North is then taken from the calibrated compass afresh.
    func recalibrate() async -> Bool {
        guard CLLocationManager.headingAvailable() else { return false }
        isCalibrating = true
        defer { isCalibrating = false }
        manager.stopUpdatingHeading()
        isForgotten = false
        degrees = nil
        steadyDegrees = nil
        resetSteady()
        north = nil
        lastCompassNudge = nil
        accuracy = -1
        manager.startUpdatingHeading()
        startMotion()

        // Never done in less than `minimum`, so the user has time to move the
        // phone; done once within `goodAccuracy` degrees for `holdFor`.
        let minimum: Duration = .seconds(4)
        let holdFor: Duration = .seconds(2)
        let timeout: Duration = .seconds(20)
        let goodAccuracy = 0.0...20.0
        let clock = ContinuousClock()
        let start = clock.now
        var goodSince: ContinuousClock.Instant?
        while clock.now - start < timeout {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return false }
            goodSince = goodAccuracy.contains(accuracy) ? goodSince ?? clock.now : nil
            if clock.now - start >= minimum, let goodSince, clock.now - goodSince >= holdFor {
                // The waving is over: north from the next steady reading, quickly.
                north = nil
                return true
            }
        }
        return false
    }

    func setMapHeading(_ value: Double) {
        let next = Self.unwrap(value, after: mapHeading)
        // Panning the map reports the same heading over and over.
        if abs(next - mapHeading) > 0.5 { mapHeading = next }
    }

    /// `value` (0 to 360), moved by whole turns to lie within 180 degrees of `previous`.
    nonisolated static func unwrap(_ value: Double, after previous: Double) -> Double {
        var change = (value - previous).truncatingRemainder(dividingBy: 360)
        if change > 180 { change -= 360 }
        if change < -180 { change += 360 }
        return previous + change
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // True north needs a location; magnetic north is close enough without one.
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        let valid = accuracy >= 0
        let field = (newHeading.x * newHeading.x + newHeading.y * newHeading.y
                     + newHeading.z * newHeading.z).squareRoot()
        Task { @MainActor in
            guard !self.isForgotten else { return }
            self.accuracy = accuracy
            self.recorder?.compass(heading: value, accuracy: accuracy, field: field)
            guard self.usesMotion else {
                guard valid else { self.degrees = nil; return }
                let degrees = self.degrees.map { Self.unwrap(value, after: $0) } ?? value
                self.degrees = degrees
                self.updateSteady(degrees)
                return
            }
            self.compassReading(value, accuracy: accuracy, field: field)
        }
    }

    /// With the gyroscope: the compass only nudges its north, and only when
    /// it can be trusted. The first reading sets it, so the pointer shows.
    private func compassReading(_ heading: Double, accuracy: Double, field: Double) {
        guard accuracy >= 0, !isCalibrating else { return }
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastCompassNudge = now }
        guard north != nil else {
            nudgeNorth(towards: heading, gain: 1)
            return
        }
        // Turning: the compass lags behind the turn. Bent field or a rough reading: wrong.
        guard turned(within: turnWindow) <= steadyTurn,
              accuracy <= worstAccuracy, plausibleField.contains(field) else { return }
        // By time, not per reading: the compass sends more readings while turning.
        let seconds = min(1, now - (lastCompassNudge ?? now))
        let settle = now - northSince < roughPeriod
            ? roughSettle
            : steadySettle * max(1, accuracy / 15)
        nudgeNorth(towards: heading, gain: seconds / settle)
    }

    /// Keep the system's figure-eight calibration screen out of the way.
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}

// MARK: - Frame loop

/// Calls `tick` once a frame of the display, with the seconds since the
/// last frame, until it returns false (or `stop`). For gliding the maps:
/// smoother than animating to each new value, which a newer value cuts short.
@MainActor
final class FrameLoop: NSObject {
    private var link: CADisplayLink?
    private var tick: ((Double) -> Bool)?
    private var lastFrame: CFTimeInterval?

    /// Starts the loop, or gives a running one this `tick` from the next frame.
    func run(_ tick: @escaping (Double) -> Bool) {
        self.tick = tick
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastFrame = nil
    }

    func stop() {
        link?.invalidate()
        link = nil
        tick = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let seconds = lastFrame.map { link.timestamp - $0 } ?? link.duration
        lastFrame = link.timestamp
        if tick?(seconds) != true { stop() }
    }
}

// MARK: - Location dot

/// The user's location like in Apple Maps, in the palette's blue: a dot with a white ring,
/// and a cone fading out in the direction the phone points.
struct LocationDot: View {
    @ObservedObject var heading: HeadingTracker
    /// The map's tilt in degrees: the dot and cone lie down on the ground with
    /// it, like the system's own location dot on a 3D map.
    var tilt: Double = 0

    /// Degrees clockwise from the top of the map; nil hides the cone.
    private var facing: Double? { heading.facing }

    private let coneLength: CGFloat = 46

    var body: some View {
        ZStack {
            if let facing {
                Cone()
                    .fill(LinearGradient(colors: [Palette.left.opacity(0.75), Palette.left.opacity(0)],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(width: coneLength * 0.9, height: coneLength)
                    // From the centre of the dot outwards.
                    .offset(y: -coneLength / 2)
                    .rotationEffect(.degrees(facing))
                    // A spring follows each new reading from where the cone is now,
                    // so turning on the spot looks like one smooth spin.
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: facing)
            }
            Circle()
                .fill(Palette.left)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white, lineWidth: 3.5))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        }
        .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        // Centred on the dot, so the map pins the dot (not the cone) to the location.
        .frame(width: coneLength * 2, height: coneLength * 2)
        .accessibilityHidden(true)
    }
}
