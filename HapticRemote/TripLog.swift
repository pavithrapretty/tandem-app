//
//  TripLog.swift
//  HapticRemote (iPhone)
//
//  Recording real walks, and playing them back.
//
//  TripRecorder writes everything a walk's guidance is worked out from, and
//  what came of it, to a file in the app's documents (Walks/): every GPS
//  fix as it came in, the step counter, the compass, each route, and the
//  navigator's state after each fix. One JSON object a line, each with `t`,
//  seconds since the walk started, and `type`. Settings, Recorded walks,
//  shares them (AirDrop to a Mac, say) to see afterwards why the guidance
//  did what it did.
//
//  TripReplay plays a recorded walk back through the real navigator, in
//  real time: the same fixes, steps and compass, the same first route. So
//  a change to the guidance can be tried on a walk that went wrong.
//

import Combine
import CoreLocation
import Foundation

// MARK: - Recording

final class TripRecorder {
    /// The switch in Settings, Recorded walks (on at first).
    static let settingKey = "recordsWalks"

    /// Where the walks are kept: Documents/Walks.
    static var directory: URL {
        URL.documentsDirectory.appending(path: "Walks", directoryHint: .isDirectory)
    }

    let url: URL
    private let started = Date()
    /// Written off the main thread, a line at a time.
    private let queue = DispatchQueue(label: "TripRecorder", qos: .utility)
    private var handle: FileHandle?
    /// The compass changes 30 times a second; 10 a second is plenty to see what it did.
    private var lastHeading: TimeInterval = -1

    init?(destination: Destination, lookAhead: Double, rerouteDistance: Double) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let url = Self.directory.appending(path: "\(formatter.string(from: started)).jsonl")
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return nil }
            handle = try FileHandle(forWritingTo: url)
        } catch {
            return nil
        }
        self.url = url
        log("start", [
            "date": ISO8601DateFormatter().string(from: started),
            "destination": destination.name,
            "lat": destination.coordinate.latitude,
            "lon": destination.coordinate.longitude,
            "isStop": destination.isStop,
            "lookAhead": lookAhead,
            "rerouteDistance": rerouteDistance,
            "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        ])
    }

    private var seconds: Double { Date.now.timeIntervalSince(started) }

    private func log(_ type: String, _ fields: [String: Any]) {
        var line = fields
        line["t"] = (seconds * 1000).rounded() / 1000
        line["type"] = type
        queue.async { [weak self] in
            guard let self, let handle = self.handle,
                  var data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
            data.append(0x0A)
            try? handle.write(contentsOf: data)
        }
    }

    // What the walk is worked out from.

    /// A GPS fix as it came in, before any of it is left out.
    func fix(_ location: CLLocation) {
        log("fix", [
            "lat": location.coordinate.latitude, "lon": location.coordinate.longitude,
            "acc": location.horizontalAccuracy,
            "speed": location.speed, "speedAcc": location.speedAccuracy,
            "course": location.course, "courseAcc": location.courseAccuracy,
            "ts": location.timestamp.timeIntervalSince1970,
        ])
    }

    func steps(distance: Double?, pace: Double?) {
        var fields: [String: Any] = [:]
        if let distance { fields["distance"] = distance }
        if let pace { fields["pace"] = pace }
        log("steps", fields)
    }

    func stepEvent(paused: Bool) {
        log("stepEvent", ["paused": paused])
    }

    /// The compass as the app has it: the way the phone points, the way the
    /// user faces (`steady`), and the gyroscope's north (`north`).
    func heading(live: Double, steady: Double?, north: Double?) {
        let now = seconds
        guard now - lastHeading >= 0.1 else { return }
        lastHeading = now
        var fields: [String: Any] = ["live": live]
        if let steady { fields["steady"] = steady }
        if let north { fields["north"] = north }
        log("heading", fields)
    }

    /// A reading of the magnetic compass itself, with how sure it is and the
    /// field's strength (about 49 µT here; far off is something metal).
    func compass(heading: Double, accuracy: Double, field: Double) {
        log("compass", ["heading": heading, "acc": accuracy, "field": field])
    }

    // What came of it.

    func route(_ points: [CLLocationCoordinate2D], turns: [RouteNavigator.Turn],
               steps: [(coordinate: CLLocationCoordinate2D, instructions: String)], reason: String) {
        log("route", [
            "reason": reason,
            // Every MapKit step, turn or not: where it starts and what it says.
            "steps": steps.map {
                ["lat": $0.coordinate.latitude, "lon": $0.coordinate.longitude,
                 "instructions": $0.instructions] as [String: Any]
            },
            "points": points.map { [$0.latitude, $0.longitude] },
            "turns": turns.map {
                ["lat": $0.coordinate.latitude, "lon": $0.coordinate.longitude, "along": $0.along,
                 "isLeft": $0.isLeft, "instructions": $0.instructions] as [String: Any]
            },
        ])
    }

    /// The navigator after a fix: where it has the user and what it signals.
    func state(_ fields: [String: Any]) {
        log("state", fields)
    }

    func pattern(_ pattern: Pattern?) {
        log("pattern", ["pattern": pattern?.rawValue ?? "none"])
    }

    func event(_ name: String) {
        log("event", ["name": name])
    }

    func finish(_ reason: String) {
        log("end", ["reason": reason])
        queue.async { [weak self] in
            try? self?.handle?.close()
            self?.handle = nil
        }
    }
}

// MARK: - Recorded walks

/// A recorded walk, for the list in Settings.
struct RecordedWalk: Identifiable {
    let url: URL
    var id: URL { url }
    let date: Date
    let destination: Destination
    /// Seconds from start to end.
    let duration: Double
    let bytes: Int

    /// The walks on this phone, newest first.
    static func all() -> [RecordedWalk] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: TripRecorder.directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.filter { $0.pathExtension == "jsonl" }
            .compactMap(RecordedWalk.init)
            .sorted { $0.date > $1.date }
    }

    init?(url: URL) {
        guard let events = TripReplay.read(url), let start = events.first, start.type == "start",
              let lat = start["lat"] as? Double, let lon = start["lon"] as? Double else { return nil }
        self.url = url
        date = (start["date"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? .distantPast
        destination = Destination(name: start["destination"] as? String ?? "Destination", subtitle: "",
                                  coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                  isStop: start["isStop"] as? Bool ?? false)
        duration = events.last?.t ?? 0
        bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}

// MARK: - Replay

/// Plays a recorded walk back, in real time, to the navigator (fixes and
/// steps) and the compass (the way the phone pointed). The timing matters:
/// the smoothing in both works by the clock.
@MainActor
final class TripReplay: ObservableObject, Identifiable {
    struct Event {
        let t: Double
        let type: String
        let fields: [String: Any]
        subscript(key: String) -> Any? { fields[key] }
    }

    let walk: RecordedWalk
    private let events: [Event]
    var duration: Double { walk.duration }

    /// Seconds into the walk.
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var isPaused = false
    @Published private(set) var isFinished = false

    // Where it goes.
    var onFix: ((CLLocation) -> Void)?
    var onSteps: ((_ distance: Double?, _ pace: Double?) -> Void)?
    var onStepEvent: ((_ paused: Bool) -> Void)?
    var onHeading: ((Double) -> Void)?

    private var next = 0
    private var timer: Timer?
    private var lastTick: Date?

    init?(_ walk: RecordedWalk) {
        guard let events = Self.read(walk.url) else { return nil }
        self.walk = walk
        self.events = events
    }

    /// The first route the walk got, as it was: so the replay starts on the
    /// same one. (Later routes are fetched afresh, where the navigator wants them.)
    var firstRoute: (points: [CLLocationCoordinate2D], turns: [RouteNavigator.Turn],
                     steps: [(coordinate: CLLocationCoordinate2D, instructions: String)])? {
        guard let route = events.first(where: { $0.type == "route" }),
              let points = route["points"] as? [[Double]] else { return nil }
        let recordedTurns = (route.fields["turns"] as? [[String: Any]]) ?? []
        let turns = recordedTurns.compactMap { turn -> RouteNavigator.Turn? in
            guard let lat = turn["lat"] as? Double, let lon = turn["lon"] as? Double,
                  let along = turn["along"] as? Double, let isLeft = turn["isLeft"] as? Bool else { return nil }
            return RouteNavigator.Turn(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                       instructions: turn["instructions"] as? String ?? "",
                                       isLeft: isLeft, along: along)
        }
        let recordedSteps = (route.fields["steps"] as? [[String: Any]]) ?? []
        let steps = recordedSteps.compactMap { step -> (coordinate: CLLocationCoordinate2D, instructions: String)? in
            guard let lat = step["lat"] as? Double, let lon = step["lon"] as? Double else { return nil }
            return (CLLocationCoordinate2D(latitude: lat, longitude: lon), step["instructions"] as? String ?? "")
        }
        return (points.compactMap { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil },
                turns, steps)
    }

    func start() {
        guard timer == nil, !isFinished else { return }
        lastTick = .now
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func togglePause() {
        isPaused.toggle()
        lastTick = .now
    }

    private func tick() {
        let now = Date.now
        defer { lastTick = now }
        guard !isPaused else { return }
        elapsed += now.timeIntervalSince(lastTick ?? now)
        while next < events.count, events[next].t <= elapsed {
            play(events[next])
            next += 1
        }
        if next >= events.count {
            isFinished = true
            stop()
        }
    }

    private func play(_ event: Event) {
        switch event.type {
        case "fix":
            guard let lat = event["lat"] as? Double, let lon = event["lon"] as? Double,
                  let accuracy = event["acc"] as? Double else { return }
            // Stamped now: the navigator times its smoothing by the fixes' stamps.
            onFix?(CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                              altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1,
                              course: event["course"] as? Double ?? -1,
                              courseAccuracy: event["courseAcc"] as? Double ?? -1,
                              speed: event["speed"] as? Double ?? -1,
                              speedAccuracy: event["speedAcc"] as? Double ?? -1,
                              timestamp: .now))
        case "steps":
            onSteps?(event["distance"] as? Double, event["pace"] as? Double)
        case "stepEvent":
            if let paused = event["paused"] as? Bool { onStepEvent?(paused) }
        case "heading":
            if let live = event["live"] as? Double { onHeading?(live) }
        default:
            break
        }
    }

    /// The events in a walk's file, in order. Nil if it can't be read.
    nonisolated static func read(_ url: URL) -> [Event]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let events = text.split(separator: "\n").compactMap { line -> Event? in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let t = object["t"] as? Double, let type = object["type"] as? String else { return nil }
            return Event(t: t, type: type, fields: object)
        }
        return events.isEmpty ? nil : events
    }
}
