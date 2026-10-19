//
//  NearestStop.swift
//  HapticRemote (iPhone)
//
//  The public transport stop closest to the user (tram, metro or train), for
//  the home screen's lavender card. Looked up in Transit around where the
//  user is (Apple Maps' points of interest if that can't be reached), and
//  again once they have walked on.
//

import Combine
import MapKit

@MainActor
final class NearestStopFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// Nil until the first lookup is done. Centraal when there is no location
    /// to look from (no permission) or no stop around it.
    @Published private(set) var found: Destination?

    private let manager = CLLocationManager()
    /// Where the current stop was looked up from.
    private var searchedFrom: CLLocation?
    private var isSearching = false
    private var isRunning = false

    /// A new lookup once the user is this far from the last one, in metres.
    private let researchDistance: Double = 100
    /// How far around the user to look, in metres.
    static let radius: Double = 2_000

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
    }

    func start() {
        isRunning = true
        // Before permission is given this does nothing; the delegate starts
        // again once it is.
        manager.startUpdatingLocation()
        fallBackIfDenied()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
    }

    /// The stop closest to `location`, or nil if there is none within the radius
    /// (or no internet).
    static func find(near location: CLLocationCoordinate2D) async -> Destination? {
        // Close by first: a big box of a city centre holds hundreds of stops.
        for radius in [750.0, radius] {
            if let stop = await Transit.nearestStop(near: location, within: radius) {
                return Destination(name: stop.name, subtitle: "", coordinate: stop.coordinate,
                                   isStop: true, isNearestStop: true, transitStopID: stop.id)
            }
        }
        let request = MKLocalPointsOfInterestRequest(center: location, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return nil }
        let here = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let closest = items.min { a, b in
            a.placemark.location.map(here.distance) ?? .infinity
                < b.placemark.location.map(here.distance) ?? .infinity
        }
        guard let closest, let name = closest.name else { return nil }
        return Destination(name: name, subtitle: "", coordinate: closest.placemark.coordinate,
                           isStop: true, isNearestStop: true)
    }

    /// The nearest stop of these kinds (the voice's "nearest tram stop",
    /// "nearest bus stop"…), looking further out when there is none close by:
    /// a train station can be kilometres off. Nil if none, or no internet.
    static func find(near location: CLLocationCoordinate2D, modes: Set<Transit.Mode>) async -> Destination? {
        let radii: [Double] = modes == [.train] ? [1_000, 3_000, 6_000] : [750, 2_000]
        for radius in radii {
            if let stop = await Transit.nearestStop(near: location, within: radius, modes: modes) {
                return Destination(name: stop.name, subtitle: "", coordinate: stop.coordinate,
                                   isStop: true, transitStopID: stop.id,
                                   transitModes: modes == [.bus] ? [.bus] : nil)
            }
        }
        return nil
    }

    private func handle(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }
        guard !isSearching else { return }
        if let searchedFrom, location.distance(from: searchedFrom) < researchDistance { return }

        isSearching = true
        Task {
            let found = await Self.find(near: location.coordinate)
            isSearching = false
            if let found {
                searchedFrom = location
                // The same stop again: keep it, so the card and route don't reset.
                if found.name != self.found?.name { self.found = found }
            } else if self.found == nil {
                // Nothing around (or no internet): Centraal, as before. Tried
                // again on the next fix.
                self.found = .centraalAsNearest
            }
        }
    }

    /// Without location access there is nothing to look around: Centraal.
    private func fallBackIfDenied() {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            if found == nil { found = .centraalAsNearest }
        default:
            break
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.handle(location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.isRunning { self.manager.startUpdatingLocation() }
            self.fallBackIfDenied()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No fix yet (indoors, say): the stop is looked up once there is one.
    }
}
