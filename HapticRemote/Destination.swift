//
//  Destination.swift
//  HapticRemote (iPhone)
//
//  Where the user is walking to: the nearest stop on the home screen
//  (NearestStopFinder), or a place picked in search.
//

import CoreLocation

/// The places the app knows.
enum Places {
    /// The Centraal tram stop on Stationsplein.
    static let centraal = CLLocationCoordinate2D(latitude: 52.3789, longitude: 4.9003)
}

struct Destination: Identifiable {
    let id = UUID()
    /// Short name, e.g. "Centraal" or "Rijksmuseum".
    let name: String
    /// What it is or where, under the name, e.g. "Centraal tram stop" or
    /// "Museumstraat 1, Amsterdam". Can be empty.
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    /// A stop of public transport: shown with the tram icon instead of a pin,
    /// and with its lines and departures (Transit).
    var isStop = false
    /// The nearest stop on the home screen, rather than a place picked in search.
    var isNearestStop = false
    /// The stop in Transit, when it was found there. Without it, a stop's
    /// departures are those of the Transit stop at the same spot.
    var transitStopID: String?

    static let centraal = Destination(name: "Centraal", subtitle: "Centraal tram stop",
                                      coordinate: Places.centraal, isStop: true)

    /// Centraal standing in for the nearest stop, when there is no location
    /// to look from or no stop around it.
    static let centraalAsNearest = Destination(name: "Centraal", subtitle: "Centraal tram stop",
                                               coordinate: Places.centraal, isStop: true,
                                               isNearestStop: true)
}
