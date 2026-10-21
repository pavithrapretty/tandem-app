//
//  Transit.swift
//  HapticRemote (iPhone)
//
//  Stops and departures of trams, metros and trains, from Transitous
//  (api.transitous.org): a free, open timetable service with the Dutch
//  OpenOV data in it, live times included. No account or key needed.
//  Trams, metros and trains (`Mode.rail`) unless buses are asked for (the
//  voice's "nearest bus stop"); ferries and coaches are left out.
//

import CoreLocation
import Foundation

enum Transit {
    enum Mode {
        case tram, metro, train, bus

        /// What the app shows unless asked for buses.
        static let rail: Set<Mode> = [.tram, .metro, .train]

        /// From Transitous's mode names; nil for ferries, coaches and the rest.
        init?(_ name: String) {
            switch name {
            case "TRAM": self = .tram
            case "SUBWAY", "METRO": self = .metro
            case "RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "SUBURBAN",
                 "LONG_DISTANCE", "HIGHSPEED_RAIL", "NIGHT_RAIL": self = .train
            case "BUS", "TROLLEYBUS": self = .bus
            default: return nil
            }
        }

        var name: String {
            switch self {
            case .tram: "Tram"
            case .metro: "Metro"
            case .train: "Train"
            case .bus: "Bus"
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
        /// The line's own colours (GVB's metro lines have them), as 0xRRGGBB.
        /// Nil when the timetable gives none (GVB's trams, NS's trains).
        var color: UInt32? = nil
        var textColor: UInt32? = nil
    }

    /// A line that stops somewhere, with its colours if it has them.
    struct Line: Identifiable, Hashable {
        let mode: Mode
        let name: String
        let color: UInt32?
        let textColor: UInt32?
        var id: String { "\(mode)-\(name)" }
    }

    /// The lines that stop somewhere, by mode (trams, then metros, then
    /// trains), for showing as badges, and as text.
    struct Lines {
        /// Trains as one group with no lines: their kinds aren't lines.
        let groups: [(mode: Mode, lines: [Line])]
        /// "Tram 7, 12 · Metro 52"
        let short: String
        /// "Tram 7 and 12. Metro 52", for VoiceOver.
        let spoken: String
    }

    /// The tram, metro or train stop closest to `location`, within `radius`
    /// metres. Nil if there is none, or no internet.
    static func nearestStop(near location: CLLocationCoordinate2D, within radius: Double,
                            modes: Set<Mode> = Mode.rail) async -> Stop? {
        await stops(near: location, within: radius, modes: modes)?.first?.stop
    }

    /// The tram, metro and train stops within `radius` metres of `location`,
    /// nearest first, each once (its platforms are one stop), with how far
    /// off it is in a straight line and what stops there. Nil without internet.
    static func stops(near location: CLLocationCoordinate2D, within radius: Double,
                      modes wanted: Set<Mode> = Mode.rail) async -> [(stop: Stop, distance: Double, modes: Set<Mode>)]? {
        let latitude = radius / 111_000
        let longitude = radius / (111_000 * cos(location.latitude * .pi / 180))
        var components = URLComponents(string: "https://api.transitous.org/api/v1/map/stops")!
        components.queryItems = [
            URLQueryItem(name: "min", value: "\(location.latitude - latitude),\(location.longitude - longitude)"),
            URLQueryItem(name: "max", value: "\(location.latitude + latitude),\(location.longitude + longitude)"),
        ]
        guard let places: [Place] = await fetch(components.url!) else { return nil }
        let here = CLLocation(latitude: location.latitude, longitude: location.longitude)
        var nearest: [String: (stop: Stop, distance: Double, modes: Set<Mode>)] = [:]
        for place in places {
            let modes = Set((place.modes ?? []).compactMap(Mode.init)).intersection(wanted)
            guard !modes.isEmpty else { continue }
            let distance = here.distance(from: CLLocation(latitude: place.lat, longitude: place.lon))
            guard distance <= radius else { continue }
            let name = shortName(place.name)
            // The station as a whole if it has one; its platforms one by one otherwise
            // (Transitous adds the other platforms of the same name itself).
            let stop = Stop(id: place.parentId ?? place.stopId, name: name,
                            coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon))
            if let known = nearest[name] {
                let all = known.modes.union(modes)
                nearest[name] = distance < known.distance ? (stop, distance, all) : (known.stop, known.distance, all)
            } else {
                nearest[name] = (stop, distance, modes)
            }
        }
        return nearest.values.sorted { $0.distance < $1.distance }
    }

    /// The next trams, metros and trains from the stop, soonest first. Nil
    /// without internet.
    /// `after`: from then on instead of from now (when the user will get there).
    static func departures(from stopID: String, count: Int = 30,
                           modes: Set<Mode> = Mode.rail, after: Date? = nil) async -> [Departure]? {
        var components = URLComponents(string: "https://api.transitous.org/api/v5/stoptimes")!
        components.queryItems = [
            URLQueryItem(name: "stopId", value: stopID),
            URLQueryItem(name: "n", value: "\(count)"),
        ]
        if let after {
            components.queryItems?.append(URLQueryItem(name: "time", value: ISO8601DateFormatter().string(from: after)))
        }
        guard let response: StopTimes = await fetch(components.url!) else { return nil }
        return response.stopTimes.compactMap { time in
            guard let mode = Mode(time.mode), modes.contains(mode), time.cancelled != true,
                  let departure = time.place.departure else { return nil }
            let line = time.routeShortName ?? time.displayName ?? ""
            // The timetable's colours; GVB's trams from its network map, which the timetable lacks.
            var color = time.routeColor.flatMap(hex)
            var textColor = time.routeTextColor.flatMap(hex)
            if color == nil, mode == .tram, time.agencyName == "GVB", let tram = gvbTramColors[line] {
                color = tram
                textColor = readableText(on: tram)
            }
            return Departure(id: (time.tripId ?? UUID().uuidString) + departure.description,
                             mode: mode, line: mode == .train ? trainKind(line) : line,
                             towards: time.headsign ?? "", time: departure,
                             color: color, textColor: textColor)
        }
        .sorted { $0.time < $1.time }
    }

    /// The stop closest to `location` that `line` (of these kinds) stops at,
    /// and what kind it is there: the voice's "tram 1", "metro 52". The stops
    /// don't say which lines they have, so the nearest dozen are asked for
    /// their next departures, then a dozen more further out. Nil if none of
    /// them has it soon (or there is no internet).
    static func nearestStop(serving line: String, modes: Set<Mode>,
                            near location: CLLocationCoordinate2D) async -> (stop: Stop, mode: Mode)? {
        var asked = Set<String>()
        for radius in [1_000.0, 3_000] {
            guard let found = await stops(near: location, within: radius, modes: modes) else { return nil }
            let candidates = Array(found.map(\.stop).filter { !asked.contains($0.id) }.prefix(12))
            asked.formUnion(candidates.map(\.id))
            // All at once; the nearest with the line wins.
            let best = await withTaskGroup(of: (Int, Mode?).self) { group in
                for (index, stop) in candidates.enumerated() {
                    let id = stop.id
                    // On the main actor, like the rest of Transit: it only waits on the network.
                    group.addTask { @MainActor in
                        let departures = await departures(from: id, count: 60, modes: modes) ?? []
                        let match = departures.first { $0.line.caseInsensitiveCompare(line) == .orderedSame }
                        return (index, match?.mode)
                    }
                }
                var best: (index: Int, mode: Mode)?
                for await (index, mode) in group {
                    if let mode, index < best?.index ?? .max { best = (index, mode) }
                }
                return best
            }
            if let best { return (candidates[best.index], best.mode) }
        }
        return nil
    }

    /// The departures from `destination`, if it is a stop: by its own stop if
    /// it was found here, else by the one at the same spot (a stop picked in
    /// search, which comes from Apple Maps).
    static func departures(at destination: Destination, after: Date? = nil) async -> [Departure]? {
        guard destination.isStop else { return nil }
        let modes = destination.transitModes ?? Mode.rail
        if let id = destination.transitStopID { return await departures(from: id, modes: modes, after: after) }
        guard let stop = await nearestStop(near: destination.coordinate, within: 150, modes: modes) else { return nil }
        return await departures(from: stop.id, modes: modes, after: after)
    }

    /// All the lines that stop there, said after a stop picked by voice:
    /// "tram lines: 1, 2, 5, 7, 13, metro lines: 52" ("trains" for the
    /// trains, whose kinds aren't lines). Nil without any.
    static func spokenLineList(of departures: [Departure]) -> String? {
        var parts: [String] = []
        for mode in [Mode.tram, .metro, .train, .bus] {
            var names: [String] = []
            for departure in departures where departure.mode == mode && !names.contains(departure.line) {
                names.append(departure.line)
            }
            guard !names.isEmpty else { continue }
            if mode == .train {
                parts.append("trains")
                continue
            }
            names.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            let kind = mode.name.lowercased() + (names.count == 1 ? " line" : " lines")
            parts.append("\(kind): \(names.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The lines that stop there, by mode, for the home screen's card:
    /// "Tram 7, 12 · Metro 52" and, for VoiceOver, "Tram 7 and 12. Metro 52".
    /// Nil without any.
    static func lines(of departures: [Departure]) -> Lines? {
        var groups: [(mode: Mode, lines: [Line])] = []
        var short: [String] = [], spoken: [String] = []
        for mode in [Mode.tram, .metro, .train, .bus] {
            var lines: [Line] = []
            for departure in departures where departure.mode == mode
                && !lines.contains(where: { $0.name == departure.line }) {
                lines.append(Line(mode: mode, name: departure.line,
                                  color: departure.color, textColor: departure.textColor))
            }
            guard !lines.isEmpty else { continue }
            if mode == .train {
                groups.append((mode, []))
                short.append("Train")
                spoken.append("Train")
                continue
            }
            // Numbers in order, and only the first few at a big station.
            lines.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let shown = Array(lines.prefix(5))
            groups.append((mode, shown))
            short.append("\(mode.name) \(shown.map(\.name).joined(separator: ", "))")
            spoken.append("\(mode.name) \(ListFormatter.localizedString(byJoining: shown.map(\.name)))")
        }
        guard !short.isEmpty else { return nil }
        return Lines(groups: groups, short: short.joined(separator: " · "), spoken: spoken.joined(separator: ". "))
    }

    /// GVB's tram lines' colours, from its network map (sampled from a
    /// screenshot of its legend, so close rather than exact).
    private static let gvbTramColors: [String: UInt32] = [
        "1": 0xEC5C3D, "2": 0x14B050, "3": 0x9C96C7, "4": 0xED75AB, "5": 0x7871B2,
        "7": 0xF39775, "12": 0x199056, "13": 0xB6D14B, "14": 0xE53792, "17": 0x86C24D,
        "19": 0xEB785B, "24": 0xF0A8C5, "25": 0xE0424A, "26": 0x7975AC, "27": 0x2AAE9F,
    ]

    /// White or near-black, whichever stands out more on `color` (GVB prints
    /// white on all of them, which is hard to read on the light ones).
    private static func readableText(on color: UInt32) -> UInt32 {
        func luminance(_ value: UInt32) -> Double {
            let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { channel -> Double in
                let c = Double(channel) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let dark: UInt32 = 0x111111
        let background = luminance(color)
        let onWhite = 1.05 / (background + 0.05)
        let onDark = (background + 0.05) / (luminance(dark) + 0.05)
        return onWhite >= onDark ? 0xFFFFFF : dark
    }

    /// "00adef" → 0x00ADEF.
    private static func hex(_ text: String) -> UInt32? {
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6 else { return nil }
        return UInt32(digits, radix: 16)
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
            let routeColor: String?
            let routeTextColor: String?
            let agencyName: String?
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
