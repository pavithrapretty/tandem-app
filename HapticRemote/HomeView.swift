//
//  HomeView.swift
//  HapticRemote (iPhone)
//
//  "05 Home" in Figma: the screen after the tutorial. Where you are, a search
//  field, the nearest stop, a map, and a shortcut back to where you arrived.
//  The sliders button opens Settings in a navigation stack. A place picked in
//  search takes the lavender card's place (the nearest stop) and the map's
//  route; tapping the card opens the navigation screens (GuidanceView). A
//  stop's lines come from Transit; "back to where you arrived" is sample
//  content for now.
//
//  Out of sight, the screen still listens to the watch: its remote buttons
//  make this iPhone vibrate.
//

import Combine
import MapKit
import SwiftUI

/// Which search the home screen's search sheet opens on.
private enum SearchMode: Identifiable {
    case typing, voice
    var id: Self { self }
}

struct HomeView: View {
    @StateObject private var connectivity = ConnectivityManager()
    @StateObject private var phoneHaptics = PhoneHapticPlayer()

    /// The place picked in search; nil shows the nearest stop.
    @State private var picked: Destination?
    /// The tram, metro or train stop closest to the user.
    @StateObject private var nearestStop = NearestStopFinder()
    /// What the lavender card and the map show: the place picked in search,
    /// or the nearest stop. Nil while the nearest stop is still being found.
    private var selected: Destination? { picked ?? nearestStop.found }
    /// The lines that stop at the selected place, if it is a stop: "Tram 7, 12".
    @State private var lines: Transit.Lines?
    /// Set by tapping the lavender card, which opens the navigation screens.
    @State private var navigatingTo: Destination?
    /// The search sheet, open on the typed search or (the microphone button)
    /// the voice search. One value, not a flag beside it, so the sheet always
    /// opens on the one that was tapped.
    @State private var searching: SearchMode?
    /// Picked in search; it replaces the card once the search screen has closed.
    @State private var searchPick: Destination?

    /// Asks once for permission to show the user's location on the map.
    @State private var locationManager = CLLocationManager()

    /// Which way the phone points, for the cone on the location dot. Kept in
    /// @State, not @StateObject, so a new compass reading redraws only the
    /// dot (which observes it), not this whole screen and its map.
    @State private var heading = HeadingTracker()

    /// The walking route from the user to the selected place, drawn on the map.
    @StateObject private var routePreview = RoutePreview()

    /// What the map shows: Damrak at first, then the whole route once it is in.
    @State private var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.3765, longitude: 4.8975),
        latitudinalMeters: 900, longitudinalMeters: 900))
    /// The map zooms to a route only the first time it comes in for a place,
    /// so it never jumps away from where the user has moved it themselves.
    @State private var hasFittedRoute = false
    /// True while the map shows the whole route and the user hasn't moved it:
    /// turning, it zooms to keep all of the route in view.
    @State private var isFramingRoute = false
    /// Where the map looks now, and its size, to turn it with the user.
    /// Not @State values: they change every frame of a pan, and redrawing
    /// the whole screen for that isn't needed.
    @State private var mapView = MapViewState()

    var body: some View {
        NavigationStack {
            TutorialPage {
                header
                searchField
                nearestStopCard
                map
                backToArrival
            }
            // The title names this screen in the next screen's back button
            // ("Home"); the bar itself is hidden here.
            .navigationTitle("Home")
            .toolbar(.hidden, for: .navigationBar)
        }
        // The back button in cream, like the design.
        .tint(Palette.text)
        .preferredColorScheme(.dark)
        // A button on the watch was pressed: play it here (nil = stop). While
        // navigating, the navigation screen also switches to that direction.
        .onReceive(connectivity.received) { pattern in
            if let pattern {
                // Arrived is said once; the directions repeat until the next one.
                phoneHaptics.play(pattern, vibrate: true, once: pattern == .arrived)
            } else {
                phoneHaptics.stop()
            }
        }
        .sheet(item: $searching, onDismiss: {
            // Back on the home screen first: the card and the map show the pick.
            // "Nearest stop" said in search: back to the live one, which follows the user.
            if let searchPick { picked = searchPick.isNearestStop ? nil : searchPick }
            searchPick = nil
        }) { mode in
            SearchView(startsListening: mode == .voice) { picked in
                searchPick = picked
                searching = nil
            }
        }
        .onChange(of: selected?.id) {
            routePreview.setDestination(selected?.coordinate)
            hasFittedRoute = false
        }
        .task(id: selected?.id) {
            lines = nil
            guard let selected, let departures = await Transit.departures(at: selected) else { return }
            lines = Transit.lines(of: departures)
        }
        .fullScreenCover(item: $navigatingTo) { destination in
            GuidanceView(destination: destination, connectivity: connectivity, phoneHaptics: phoneHaptics)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Where to?")
                .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.68)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 6)

            Spacer(minLength: 12)

            NavigationLink {
                SettingsView(connectivity: connectivity, phoneHaptics: phoneHaptics)
            } label: {
                Image("icon-sliders")
                    .frame(width: 52, height: 52)
                    .glassButtonBackground(tint: nil, fallback: Palette.card,
                                           in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Search

    /// The same field as on the search screen (SearchBar); here it only opens it.
    private var searchField: some View {
        SearchBar(onMicrophone: { searching = .voice }) {
            Button {
                searching = .typing
            } label: {
                HStack(spacing: 12) {
                    Image("icon-search")
                        .accessibilityHidden(true)
                    Text("Search a place or stop")
                        .font(.atkinson(18, relativeTo: .body))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Nearest stop, or the place picked in search

    /// The lavender card: the nearest stop, or the place picked in search.
    /// Tapping it starts the walking directions.
    @ViewBuilder
    private var nearestStopCard: some View {
        if let selected {
            card(selected)
        } else {
            findingCard
        }
    }

    private func card(_ selected: Destination) -> some View {
        Button {
            navigatingTo = selected
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(selected.isNearestStop ? "NEAREST STOP" : "YOUR DESTINATION")
                        .font(.atkinson(14, .bold, relativeTo: .footnote))
                        .tracking(0.84)
                        .foregroundStyle(Palette.onAccentMuted)
                    Spacer()
                    if selected.isNearestStop {
                        Image("icon-upright")
                            .accessibilityHidden(true)
                    } else {
                        // Room for the clear button, which lies on top (see below).
                        Color.clear.frame(width: 24, height: 24)
                    }
                }

                Text(selected.name)
                    .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                    .tracking(-0.68)
                    .foregroundStyle(Palette.onAccent)
                    .fixedSize(horizontal: false, vertical: true)

                if !selected.isNearestStop, !selected.subtitle.isEmpty {
                    Text(selected.subtitle)
                        .font(.atkinson(16, relativeTo: .callout))
                        .foregroundStyle(Palette.onAccentMuted)
                        .lineLimit(2)
                }

                // Side by side; one above the other when the text is very large.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { chips }
                    VStack(alignment: .leading, spacing: 8) { chips }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 80% lavender, so the Liquid Glass shows through. Solid before iOS 26.
            .glassButtonBackground(tint: Palette.accent.opacity(0.8), fallback: Palette.accent,
                                   in: RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selected.isNearestStop
            ? "Nearest stop: \(selected.name). \(lines.map { "\($0.spoken). " } ?? "")\(walkingTime.spoken)."
            : "Your destination: \(selected.name). \(selected.subtitle). \(lines.map { "\($0.spoken). " } ?? "")\(walkingTime.spoken).")
        .accessibilityHint("Starts walking directions to \(selected.name).")
        .accessibilityAddTraits(.isButton)
        // A searched place can be cleared, back to the nearest stop. On top of
        // the card, not inside it, so it isn't part of the card's button.
        .overlay(alignment: .topTrailing) {
            if !selected.isNearestStop {
                Button {
                    picked = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Palette.onAccent.opacity(0.1), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("Clear destination")
                .accessibilityHint("Shows the nearest stop again.")
            }
        }
    }

    /// The lavender card while the nearest stop is being looked up.
    private var findingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEAREST STOP")
                .font(.atkinson(14, .bold, relativeTo: .footnote))
                .tracking(0.84)
                .foregroundStyle(Palette.onAccentMuted)
            HStack(spacing: 12) {
                Text("Finding…")
                    .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                    .tracking(-0.68)
                    .foregroundStyle(Palette.onAccent)
                ProgressView()
                    .tint(Palette.onAccent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassButtonBackground(tint: Palette.accent.opacity(0.8), fallback: Palette.accent,
                               in: RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finding the nearest stop")
    }

    @ViewBuilder
    private var chips: some View {
        // Only for a stop, once its lines are in.
        if let lines {
            lineChip(lines)
        }
        chip(icon: "icon-walk", text: walkingTime.short)
    }

    /// How long the walk to the selected place takes, from the route on the map. A dash
    /// until the route is in.
    private var walkingTime: (short: String, spoken: String) {
        guard let seconds = routePreview.route?.expectedTravelTime else {
            return ("— min", "walking time not known yet")
        }
        // Rounded up, and never "0 min".
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 {
            return ("\(minutes) min", minutes == 1 ? "1 minute walk" : "\(minutes) minutes walk")
        }
        let spokenHours = hours == 1 ? "1 hour" : "\(hours) hours"
        return (rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min",
                rest == 0 ? "\(spokenHours) walk" : "\(spokenHours) \(rest) minutes walk")
    }

    /// The lines as badges in their own colours, on the lavender card.
    private func lineChip(_ lines: Transit.Lines) -> some View {
        HStack(spacing: 8) {
            Image("icon-train")
            LineBadges(lines: lines, textColor: Palette.onAccent, badgeColor: Palette.onAccent.opacity(0.12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.onAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(icon)
            Text(text)
                .font(.atkinson(16, .medium, relativeTo: .callout))
                .foregroundStyle(Palette.onAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.onAccent.opacity(0.1), in: Capsule())
    }

    // MARK: - Map

    /// Damrak, with the selected place (at first the nearest stop) marked, and the user's own
    /// location as a blue dot with a cone for the way they face, and the green
    /// walking route between them. The map opens on Damrak and zooms out to the
    /// whole route once it is in; the location button in its corner moves it to
    /// where the user is. It is turned the way the user faces, and turns with them.
    private var map: some View {
        // Panning and zooming by hand; the turning comes from the way the user faces.
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            // First, so the stop and the dot are drawn on top of it.
            if let route = routePreview.route {
                MapPolyline(route.polyline)
                    .stroke(Palette.success, style: StrokeStyle(lineWidth: 6, lineCap: .round,
                                                               lineJoin: .round))
            }
            if let selected {
                Marker(selected.name, systemImage: selected.symbol,
                       coordinate: selected.coordinate)
                    .tint(Palette.accent)
            }
            // Drawn by hand: the system dot takes the screen's cream tint and
            // ignores a tint of its own.
            UserAnnotation { _ in
                LocationDot(heading: heading)
            }
        }
        .onChange(of: routePreview.route) { _, route in
            guard let route, let selected, !hasFittedRoute else { return }
            hasFittedRoute = true
            isFramingRoute = true
            let framing = routeFraming(route.polyline, destination: selected.coordinate)
            mapView.zoomingUntil = .now + 0.6
            withAnimation(.easeInOut(duration: 0.6)) {
                mapPosition = .camera(camera(showing: framing, heading: heading.steadyDegrees ?? 0))
            } completion: {
                // Turned meanwhile: catch up.
                if let degrees = heading.steadyDegrees { turnMap(to: degrees) }
            }
        }
        .onChange(of: selected?.id) { isFramingRoute = false }
        .onMapCameraChange(frequency: .continuous) { context in
            mapView.camera = context.camera
            heading.setMapHeading(context.camera.heading)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { mapView.size = $0 }
        // Turned the way the user faces, and turning with them (not with the
        // sway of the hand: see `steadyDegrees`).
        .onReceive(heading.$steadyDegrees) { degrees in
            if let degrees { turnMap(to: degrees) }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            // Where north is, now the map is turned.
            MapCompass()
        }
        .frame(minHeight: 180, maxHeight: .infinity)
        .background(Palette.mapPanel)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selected.map { selected in
            routePreview.route == nil
                ? "Map with \(selected.name) and your location"
                : "Map with your location and the walking route to \(selected.name)"
        } ?? "Map with your location")
        .onAppear {
            // Shows the system question the first time; does nothing after that.
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
            heading.start()
            routePreview.start()
            nearestStop.start()
        }
        .onDisappear {
            heading.stop()
            routePreview.stop()
            nearestStop.stop()
        }
    }

    /// Turns the map to `degrees` (clockwise from north) about where it looks.
    /// Showing the whole route, it zooms in or out to keep it all in view.
    private func turnMap(to degrees: Double) {
        // Not while zooming to the route: setting the camera would cut the zoom short.
        guard var camera = mapView.camera, Date.now >= mapView.zoomingUntil else { return }
        if mapPosition.positionedByUser { isFramingRoute = false }
        let heading = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let change = abs(HeadingTracker.unwrap(heading, after: camera.heading) - camera.heading)
        guard change >= 0.1 else { return }
        if isFramingRoute, let route = routePreview.route, let selected {
            camera = self.camera(showing: routeFraming(route.polyline, destination: selected.coordinate),
                                 heading: heading)
        } else {
            camera.heading = heading
        }
        // The steady way glides by itself, a step a frame: no animation on top.
        mapPosition = .camera(camera)
    }

    /// A camera turned to `heading` that shows all of `rect`, which is laid
    /// out north up: turned, it takes more room across or up and down.
    private func camera(showing rect: MKMapRect, heading: Double) -> MapCamera {
        let center = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        let pointsPerMetre = MKMapPointsPerMeterAtLatitude(center.latitude)
        let width = rect.width / pointsPerMetre, height = rect.height / pointsPerMetre
        let angle = heading * .pi / 180
        let across = width * abs(cos(angle)) + height * abs(sin(angle))
        let upDown = width * abs(sin(angle)) + height * abs(cos(angle))
        // A map shows about 1.23 × the camera distance across its width (as on
        // the navigation screen's map).
        let size = mapView.size
        let aspect = size.width > 0 && size.height > 0 ? size.height / size.width : 1
        let distance = max(across / 1.23, upDown / (1.23 * aspect))
        return MapCamera(centerCoordinate: center, distance: distance, heading: heading, pitch: 0)
    }

    // MARK: - Back to where you arrived

    private var backToArrival: some View {
        Button {
            // TODO: route back to where the user arrived.
        } label: {
            HStack(spacing: 14) {
                Image("icon-history")
                    .frame(width: 48, height: 48)
                    .background(Palette.card2, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Back to where you arrived")
                        .font(.atkinson(18, .bold, relativeTo: .headline))
                        .foregroundStyle(Palette.text)
                    Text("Zandvoort station · 14:02")
                        .font(.atkinson(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("icon-chevron-right")
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassButtonBackground(tint: nil, fallback: Palette.card,
                                   in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The home map's camera and size, kept out of the screen's state (see `mapView`).
private final class MapViewState {
    var camera: MapCamera?
    var size: CGSize = .zero
    /// Until then, the map is zooming to the route.
    var zoomingUntil: Date = .distantPast
}

// MARK: - Route preview

/// Fetches the walking route from where the user is to the destination, and
/// fetches it again once they have moved a bit, so the line starts at the dot.
@MainActor
private final class RoutePreview: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var route: MKRoute?

    /// Nil until there is a place to go: no route is fetched.
    private var destination: CLLocationCoordinate2D?
    private let manager = CLLocationManager()
    /// The last usable fix, to fetch a route straight away when the destination changes.
    private var lastLocation: CLLocation?
    /// Where the current route starts.
    private var routeStart: CLLocation?
    private var isFetching = false
    private var isRunning = false

    /// A new route once the user is this far from where the last one started, in metres.
    private let refetchDistance: Double = 30

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
    }

    func start() {
        isRunning = true
        // Before permission is given this does nothing; the delegate starts
        // again once it is.
        manager.startUpdatingLocation()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
    }

    /// Another place: the old line goes, and the new one comes as soon as it can.
    func setDestination(_ coordinate: CLLocationCoordinate2D?) {
        destination = coordinate
        route = nil
        routeStart = nil
        if let lastLocation { handle(lastLocation) }
    }

    private func handle(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return }
        lastLocation = location
        guard !isFetching, let target = destination else { return }
        if let routeStart, location.distance(from: routeStart) < refetchDistance { return }

        isFetching = true
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target))
        request.transportType = .walking
        MKDirections(request: request).calculate { [weak self] response, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isFetching = false
                // The destination changed while this was on its way: fetch the new one.
                guard target.latitude == self.destination?.latitude,
                      target.longitude == self.destination?.longitude else {
                    if let lastLocation = self.lastLocation { self.handle(lastLocation) }
                    return
                }
                // No route (no internet, say): keep the old line, try again on the next fix.
                if let route = response?.routes.first {
                    self.route = route
                    self.routeStart = location
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.handle(location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.isRunning { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No fix yet (indoors, say): the line appears once there is one.
    }
}

#Preview {
    Typography.registerFonts()
    return HomeView()
}
