//
//  Transit.swift
//  HapticRemote (iPhone)
//
//  Stops and departures of trams, metros and trains, from Transitous
//  (api.transitous.org): a free, open timetable service with the Dutch
//  OpenOV data in it, live times included. No account or key needed.
//  Buses, ferries and coaches are left out.
//

import CoreLocation
import Foundation

enum Transit {
    enum Mode {
        case tram, metro, train

        /// From Transitous's mode names; nil for buses, ferries and the rest.
        init?(_ name: String) {
            switch name {
            case "TRAM": self = .tram
            case "SUBWAY", "METRO": self = .metro
            case "RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "SUBURBAN",
                 "LONG_DISTANCE", "HIGHSPEED_RAIL", "NIGHT_RAIL": self = .train
            default: return nil
            }
        }

        var name: String {
            switch self {
            case .tram: "Tram"
            case .metro: "Metro"
            case .train: "Train"
            }
        }
    }

    struct Stop {
        /// What departures are asked for with.
        let id: String
        /// Without the town in front: "Van Baerlestraat", not "Amsterdam, Van Baerlestraat".
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    struct Departure: Identifiable {
        let id: String
        let mode: Mode
        /// "7", "52", or for a train its kind, shortened: "IC", "SPR".
        let line: String
        let towards: String
        let time: Date
    }

    /// The tram, metro or train stop closest to `location`, within `radius`
    /// metres. Nil if there is none, or no internet.
    static func nearestStop(near location: CLLocationCoordinate2D, within radius: Double) async -> Stop? {
        let latitude = radius / 111_000
        let longitude = radius / (111_000 * cos(location.latitude * .pi / 180))
        var components = URLComponents(string: "https://api.transitous.org/api/v1/map/stops")!
        components.queryItems = [
            URLQueryItem(name: "min", value: "\(location.latitude - latitude),\(location.longitude - longitude)"),
            URLQueryItem(name: "max", value: "\(location.latitude + latitude),\(location.longitude + longitude)"),
        ]
        guard let places: [Place] = await fetch(components.url!) else { return nil }
        let here = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let closest = places
            .filter { ($0.modes ?? []).contains { Mode($0) != nil } }
            .map { ($0, here.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon))) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
        guard let closest else { return nil }
        // The station as a whole if it has one; its platforms one by one otherwise
        // (Transitous adds the other platforms of the same name itself).
        return Stop(id: closest.parentId ?? closest.stopId, name: shortName(closest.name),
                    coordinate: CLLocationCoordinate2D(latitude: closest.lat, longitude: closest.lon))
    }

    /// The next trams, metros and trains from the stop, soonest first. Nil
    /// without internet.
    static func departures(from stopID: String, count: Int = 30) async -> [Departure]? {
        var components = URLComponents(string: "https://api.transitous.org/api/v5/stoptimes")!
        components.queryItems = [
            URLQueryItem(name: "stopId", value: stopID),
            URLQueryItem(name: "n", value: "\(count)"),
        ]
        guard let response: StopTimes = await fetch(components.url!) else { return nil }
        return response.stopTimes.compactMap { time in
            guard let mode = Mode(time.mode), time.cancelled != true,
                  let departure = time.place.departure else { return nil }
            let line = time.routeShortName ?? time.displayName ?? ""
            return Departure(id: (time.tripId ?? UUID().uuidString) + departure.description,
                             mode: mode, line: mode == .train ? trainKind(line) : line,
                             towards: time.headsign ?? "", time: departure)
        }
        .sorted { $0.time < $1.time }
    }

    /// The departures from `destination`, if it is a stop: by its own stop if
    /// it was found here, else by the one at the same spot (a stop picked in
    /// search, which comes from Apple Maps).
    static func departures(at destination: Destination) async -> [Departure]? {
        guard destination.isStop else { return nil }
        if let id = destination.transitStopID { return await departures(from: id) }
        guard let stop = await nearestStop(near: destination.coordinate, within: 150) else { return nil }
        return await departures(from: stop.id)
    }

    /// The lines that stop there, by mode, for the home screen's card:
    /// "Tram 7, 12 · Metro 52" and, for VoiceOver, "Tram 7 and 12. Metro 52".
    /// Nil without any.
    static func lines(of departures: [Departure]) -> (short: String, spoken: String)? {
        var short: [String] = [], spoken: [String] = []
        for mode in [Mode.tram, .metro, .train] {
            var lines: [String] = []
            for departure in departures where departure.mode == mode && !lines.contains(departure.line) {
                lines.append(departure.line)
            }
            guard !lines.isEmpty else { continue }
            if mode == .train {
                short.append("Train")
                spoken.append("Train")
                continue
            }
            // Numbers in order, and only the first few at a big station.
            lines.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            let shown = Array(lines.prefix(5))
            short.append("\(mode.name) \(shown.joined(separator: ", "))")
            spoken.append("\(mode.name) \(ListFormatter.localizedString(byJoining: shown))")
        }
        guard !short.isEmpty else { return nil }
        return (short.joined(separator: " · "), spoken.joined(separator: ". "))
    }

    // MARK: - Under the hood

    private struct Place: Decodable {
        let name: String
        let stopId: String
        let parentId: String?
        let lat: Double
        let lon: Double
        let modes: [String]?
        /// Live if there is a live time, else the timetable's.
        let departure: Date?
    }

    private struct StopTimes: Decodable {
        struct StopTime: Decodable {
            let place: Place
            let mode: String
            let headsign: String?
            let routeShortName: String?
            let displayName: String?
            let tripId: String?
            let cancelled: Bool?
        }
        let stopTimes: [StopTime]
    }

    private static func fetch<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        // Transitous asks apps to say who they are.
        request.setValue("HapticRemote/1.0 (iOS; HvA accessibility project)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    /// "Amsterdam, Van Baerlestraat" → "Van Baerlestraat".
    private static func shortName(_ name: String) -> String {
        guard let comma = name.range(of: ", ") else { return name }
        return String(name[comma.upperBound...])
    }

    /// Short enough for the departure's badge.
    private static func trainKind(_ name: String) -> String {
        switch name.lowercased() {
        case "intercity": "IC"
        case "sprinter": "SPR"
        case "intercity direct": "ICD"
        default: name.count <= 4 ? name : String(name.prefix(3)).uppercased()
        }
    }
}
