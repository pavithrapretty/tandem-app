//
//  HomeView.swift
//  HapticRemote (iPhone)
//
//  "05 Home" in Figma: the screen after the tutorial. Where you are, a search
//  field, the nearest stop, a map, and a shortcut back to where you arrived.
//  A place found by voice is said back, with a stop's lines, and then the
//  app asks (and listens) whether to start directions there.
//
//  Holding anywhere for 2 seconds starts the voice search, like the
//  microphone button, with taps getting heavier on the way there and a
//  lavender glow round the screen's edge growing with each. The same glow
//  shows while the microphone listens for the answer to "Start directions?". The sliders button opens Settings in a navigation stack. A place picked in
//  search takes the lavender card's place (the nearest stop) and the map's
//  route; tapping the card opens the navigation screens (GuidanceView). A
//  stop's lines come from Transit; "back to where you arrived" is sample
//  content for now.
//
//  Out of sight, the screen still listens to the watch: its remote buttons
//  make this iPhone vibrate.
//

import AVFoundation
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
    /// The iPhone's own vibration (Settings).
    @AppStorage(GuidanceSettings.vibrationKey) private var vibrationOn = true

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
    /// "Navigate to the nearest train station" said to Siri.
    @ObservedObject private var siri = SiriRequests.shared
    /// The search sheet, open on the typed search or (the microphone button)
    /// the voice search. One value, not a flag beside it, so the sheet always
    /// opens on the one that was tapped.
    @State private var searching: SearchMode?
    /// Picked in search; it replaces the card once the search screen has closed.
    @State private var searchPick: Destination?
    /// That place was said, not tapped: what was understood is said back.
    @State private var pickedByVoice = false
    /// Says it back without VoiceOver.
    @State private var pickVoice = PickVoice()
    /// Saying it back and asking: cancelled if the user moves on meanwhile.
    @State private var confirmTask: Task<Void, Never>?
    /// Asked whether to start directions here, and listening for the answer.
    @State private var confirming: Destination?
    /// Listens for that yes or no.
    @StateObject private var confirmListener = SpeechListener()
    /// Bumped when holding the screen starts the voice search, for its tap.
    @State private var heldForVoice = 0
    /// A finger is on the screen, maybe holding for the voice search.
    @GestureState private var holdingForVoice = false
    /// The taps while it is held.
    @State private var holdTicks: Task<Void, Never>?
    /// How far the glow round the screen's edge reaches in, in points:
    /// wider with each tap, 0 when not held.
    @State private var holdEdgeWidth: CGFloat = 0
    /// The same glow while the microphone listens for the yes or no to
    /// "Start directions?", as in the tutorial.
    @State private var listeningEdgeWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            TutorialPage(toBottomEdge: true) {
                header
                searchField
                nearestStopCard
                map
                // Hidden for now, until it routes back for real.
                // backToArrival
            }
            // The card grows as the stop, its lines and the walk come in,
            // and the map gives it the room in the same movement.
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.12), value: cardContent)
            // The title names this screen in the next screen's back button
            // ("Home"); the bar itself is hidden here.
            .navigationTitle("Home")
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if let confirming {
                    confirmCard(confirming)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15), value: confirming?.id)
            // Held anywhere for 2 seconds: the voice search, as the microphone
            // button. Beside the buttons' own taps, so they still work.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Self.voiceHoldDuration)
                    .updating($holdingForVoice) { pressing, state, _ in state = pressing }
                    .onEnded { _ in holdForVoice() }
            )
            .onChange(of: holdingForVoice) { _, holding in
                holdTicks?.cancel()
                holdTicks = holding ? Task { await tickWhileHeld() } : nil
                // Let go, or the voice search has started: the glow goes.
                if !holding {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.3)) { holdEdgeWidth = 0 }
                }
            }
            .sensoryFeedback(.start, trigger: heldForVoice)
        }
        .overlay { ScreenEdgeGlow(width: max(holdEdgeWidth, listeningEdgeWidth)) }
        .modifier(ListeningGlow(listener: confirmListener, width: $listeningEdgeWidth))
        // The back button in cream, like the design.
        .tint(Palette.text)
        .preferredColorScheme(.dark)
        // A button on the watch was pressed: play it here (nil = stop). While
        // navigating, the navigation screen also switches to that direction.
        .onReceive(connectivity.received) { pattern in
            if let pattern {
                // Arrived is said once; the directions repeat until the next one.
                phoneHaptics.play(pattern, vibrate: vibrationOn, once: pattern == .arrived)
            } else {
                phoneHaptics.stop()
            }
        }
        .sheet(item: $searching, onDismiss: {
            // Back on the home screen first: the card and the map show the pick.
            // "Nearest stop" said in search: back to the live one, which follows the user.
            if let searchPick {
                picked = searchPick.isNearestStop ? nil : searchPick
                if pickedByVoice { announcePick() }
            }
            searchPick = nil
        }) { mode in
            SearchView(startsListening: mode == .voice) { picked, byVoice in
                searchPick = picked
                pickedByVoice = byVoice
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
        // Moving on (a new search, directions) ends the question.
        // (Not after the answer: the microphone is ending by itself then.)
        .onChange(of: searching != nil) { _, open in if open, confirmTask != nil { endConfirm() } }
        .onChange(of: navigatingTo?.id) { _, id in if id != nil, confirmTask != nil { endConfirm() } }
        // No microphone or speech recognition: the buttons only.
        .onChange(of: confirmListener.failure) { _, failure in if failure != nil { endConfirm() } }
        .fullScreenCover(item: $navigatingTo) { destination in
            GuidanceView(destination: destination, connectivity: connectivity, phoneHaptics: phoneHaptics)
        }
        // Also when Siri asked before this screen was there (the app opening).
        .onChange(of: siri.navigateToNearestTrainStation, initial: true) { _, asked in
            if asked { navigateToNearestTrainStation() }
        }
    }

    // MARK: - Siri

    /// "Navigate to the nearest train station": straight into the
    /// directions, over whatever was open. Said out loud if there is none.
    private func navigateToNearestTrainStation() {
        siri.navigateToNearestTrainStation = false
        searching = nil
        Task {
            guard let here = await currentLocation(),
                  let station = await NearestStopFinder.find(near: here, modes: [.train]) else {
                await say("No train station found near you.")
                return
            }
            navigatingTo = station
        }
    }

    /// Where the user is: the last fix if it is fresh, otherwise the first
    /// good one (up to 10 seconds, as the app may only just have opened),
    /// otherwise the last one known, however old.
    private func currentLocation() async -> CLLocationCoordinate2D? {
        if let last = locationManager.location, last.horizontalAccuracy >= 0,
           last.horizontalAccuracy <= 100, last.timestamp.timeIntervalSinceNow > -60 {
            return last.coordinate
        }
        let fix = await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location, location.horizontalAccuracy >= 0,
                           location.horizontalAccuracy <= 100 {
                            return location.coordinate
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return fix ?? locationManager.location?.coordinate
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

    private static let voiceHoldDuration: Double = 2

    /// Holding for the voice search: from half a second, a tap every quarter
    /// second, each heavier than the last, up to the full hold. The glow
    /// round the screen's edge grows with each, 4 to 20 pt, also with the
    /// vibration off.
    private func tickWhileHeld() async {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        try? await Task.sleep(for: .seconds(0.5))
        let ticks = Int((Self.voiceHoldDuration - 0.5) / 0.25)
        for tick in 0..<ticks {
            guard !Task.isCancelled else { return }
            let progress = Double(tick) / Double(max(1, ticks - 1))
            if vibrationOn { generator.impactOccurred(intensity: 0.5 + 0.5 * progress) }
            // A little past and back with each tap, as if pushed out by it.
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.25, bounce: 0.4)) {
                holdEdgeWidth = 4 + 16 * progress
            }
            try? await Task.sleep(for: .seconds(0.25))
        }
    }

    /// After the voice search: what it put in, and a stop's lines,
    /// "Leidseplein, tram lines: 1, 2, 5, 7, 13, metro lines: 52", then
    /// whether to start directions there, and the microphone for the answer.
    /// By VoiceOver, or without it in the app's own voice.
    private func announcePick() {
        guard let shown = selected else { return }
        confirmTask?.cancel()
        confirmTask = Task {
            var line: SpokenLine = "\(dutch: shown.name)"
            if shown.isStop, let departures = await Transit.departures(at: shown),
               let lines = Transit.spokenLineList(of: departures) {
                line = "\(line), \(lines)"
            }
            line = "\(line). Start directions? Say yes or no."
            await say(line)
            // Still here, with the same place.
            guard !Task.isCancelled, searching == nil, navigatingTo == nil,
                  selected?.id == shown.id else { return }
            confirming = shown
            confirmListener.onFinish = { words in answer(Self.reply(to: words), for: shown, heard: true) }
            confirmListener.start()
        }
    }

    /// Says `line` and returns once it has been said.
    private func say(_ line: SpokenLine) async {
        guard UIAccessibility.isVoiceOverRunning else {
            await pickVoice.say(line)
            return
        }
        // After VoiceOver has moved back onto the home screen and said
        // what it landed on: earlier, it drops this. Again if it was
        // cut off all the same (it says whether it finished).
        try? await Task.sleep(for: .seconds(1))
        for _ in 0..<3 where !Task.isCancelled {
            UIAccessibility.post(notification: .announcement, argument: line.announcement())
            guard await Self.announcementWasCutOff(line.plain) else { return }
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    /// Yes: directions there. Anything else (no, nothing, or not
    /// understood): staying on the home screen.
    /// `heard`: said, so the microphone is done already (and plays its
    /// ending chime); tapped, it is stopped.
    private func answer(_ yes: Bool, for destination: Destination, heard: Bool = false) {
        endConfirm(stopsListening: !heard)
        if yes { navigatingTo = destination }
    }

    /// No more question: the card goes, the microphone stops.
    private func endConfirm(stopsListening: Bool = true) {
        confirmTask?.cancel()
        confirmTask = nil
        confirmListener.onFinish = nil
        if stopsListening { confirmListener.stop() }
        pickVoice.stop()
        confirming = nil
    }

    /// Whether the words say yes. A no in them wins ("no, don't start").
    private static func reply(to words: String) -> Bool {
        let said = Set(words.lowercased().components(separatedBy: CharacterSet.letters.inverted))
        let no: Set = ["no", "nope", "nah", "cancel", "stop", "don", "dont", "not", "nee", "later"]
        let yes: Set = ["yes", "yeah", "yep", "yup", "sure", "ok", "okay", "go", "navigate", "start",
                        "please", "ja", "correct", "directions"]
        return said.isDisjoint(with: no) && !said.isDisjoint(with: yes)
    }

    /// While listening for the answer: the question, and Yes and No to tap
    /// instead (somewhere loud, or rather not saying it).
    private func confirmCard(_ destination: Destination) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start directions to \(destination.name)?")
                        .font(.atkinson(18, .bold, relativeTo: .headline))
                        .foregroundStyle(Palette.text)
                    Text("Say yes or no")
                        .font(.atkinson(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                confirmButton("No", fill: Palette.card2, text: Palette.text) { answer(false, for: destination) }
                confirmButton("Yes", fill: Palette.accent, text: Palette.onAccent) { answer(true, for: destination) }
            }
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func confirmButton(_ title: String, fill: Color, text: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.atkinson(18, .bold, relativeTo: .body))
                .foregroundStyle(text)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(fill, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    /// Waits for VoiceOver to be done with `text`: true if it didn't get
    /// through it. False too if nothing is heard of it in 15 seconds.
    private static func announcementWasCutOff(_ text: String) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await note in NotificationCenter.default.notifications(named: UIAccessibility.announcementDidFinishNotification) {
                    guard note.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String == text else { continue }
                    return !(note.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? Bool ?? true)
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return false
            }
            let cutOff = await group.next() ?? false
            group.cancelAll()
            return cutOff
        }
    }

    /// The voice search, from holding the screen; not over another screen.
    private func holdForVoice() {
        guard searching == nil, navigatingTo == nil else { return }
        heldForVoice += 1
        searching = .voice
    }

    /// The same field as on the search screen (SearchBar); here it only opens it.
    private var searchField: some View {
        SearchBar(onMicrophone: { searching = .voice }) {
            Button {
                // Let go after holding it for the voice search: that one stays.
                guard searching == nil else { return }
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

    /// What the card shows, for its growing: which place, its lines, and
    /// whether the walk is in.
    private var cardContent: String {
        "\(selected?.id.uuidString ?? "finding") \(lines?.short ?? "") \(routePreview.route == nil)"
    }

    /// The lavender card: the nearest stop, or the place picked in search.
    /// Tapping it starts the walking directions. While the nearest stop is
    /// being looked up, "Finding…" on the same card, which then grows.
    private var nearestStopCard: some View {
        card(selected)
    }

    private func card(_ selected: Destination?) -> some View {
        Button {
            guard let selected, searching == nil else { return }
            navigatingTo = selected
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(selected.map { $0.isNearestStop ? nearestStopLabel.uppercased() : "YOUR DESTINATION" }
                         ?? "NEAREST STOP")
                        .font(.atkinson(14, .bold, relativeTo: .footnote))
                        .tracking(0.84)
                        .foregroundStyle(Palette.onAccentMuted)
                        .contentTransition(.opacity)
                    Spacer()
                    if let selected, !selected.isNearestStop {
                        // Room for the clear button, which lies on top (see below).
                        Color.clear.frame(width: 24, height: 24)
                    }
                }

                HStack(spacing: 12) {
                    Text(selected?.name ?? "Finding…")
                        .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                        .tracking(-0.68)
                        .foregroundStyle(Palette.onAccent)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                    if selected == nil {
                        ProgressView()
                            .tint(Palette.onAccent)
                            .transition(.opacity)
                    }
                }

                if let selected {
                    details(of: selected)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 80% lavender, so the Liquid Glass shows through. Solid before iOS 26.
            .glassButtonBackground(tint: Palette.accent.opacity(0.8), fallback: Palette.accent,
                                   in: RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        // Nothing to start yet while finding.
        .allowsHitTesting(selected != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardLabel(selected))
        .accessibilityHint(selected.map { "Starts walking directions to \($0.name)." } ?? "")
        .accessibilityAddTraits(selected == nil ? [] : .isButton)
        // A searched place can be cleared, back to the nearest stop. On top of
        // the card, not inside it, so it isn't part of the card's button.
        .overlay(alignment: .topTrailing) {
            if let selected, !selected.isNearestStop {
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

    private func cardLabel(_ selected: Destination?) -> String {
        guard let selected else { return "Finding the nearest stop" }
        return selected.isNearestStop
            ? "\(nearestStopLabel): \(selected.name). \(lines.map { "\($0.spoken). " } ?? "")\(walkingTime.spoken)."
            : "Your destination: \(selected.name). \(selected.subtitle). \(lines.map { "\($0.spoken). " } ?? "")\(walkingTime.spoken)."
    }

    /// Under the name, once there is a place: its address, the lines and the
    /// walk, and Navigate.
    private func details(of selected: Destination) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

            // Shows that the card starts the directions. Part of the card's
            // button, not a button of its own, so the card stays one element.
            HStack(spacing: 8) {
                Text("Navigate")
                    .font(.atkinson(20, .extraBold, relativeTo: .title3))
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            // 80% white, so the Liquid Glass shows through. Solid before iOS 26.
            .glassButtonBackground(tint: .white.opacity(0.8), fallback: .white,
                                   in: RoundedRectangle(cornerRadius: 18))
            .padding(.top, 8)
        }
    }

    /// "Nearest tram stop", "Nearest metro station"…, from the lines that stop
    /// there; with several kinds, the biggest (a station with trams too is a
    /// station). "Nearest stop" until the lines are in.
    private var nearestStopLabel: String {
        let modes = Set(lines?.groups.map(\.mode) ?? [])
        if modes.contains(.train) { return "Nearest train station" }
        if modes.contains(.metro) { return "Nearest metro station" }
        if modes.contains(.tram) { return "Nearest tram stop" }
        if modes.contains(.bus) { return "Nearest bus stop" }
        return "Nearest stop"
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
        // Its bottom corners follow the screen's, 16 pt in from them.
        .background(Palette.mapPanel, in: screenConcentricRectangle(26))
        .clipShape(screenConcentricRectangle(26))
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

/// The home screen's own voice, when VoiceOver is off: says a place found by
/// voice back. On its own audio session, like the navigation's voice, so
/// the microphone's ending doesn't cut it off.
@MainActor
private final class PickVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var done: CheckedContinuation<Void, Never>?
    private var last: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }

    /// Returns once it has been said, or stopped. One utterance per
    /// language: the names in the Dutch voice.
    func say(_ line: SpokenLine) async {
        stop()
        for part in line.parts where !part.text.allSatisfy(\.isWhitespace) {
            let utterance = AVSpeechUtterance.tandem(part.text, dutch: part.isDutch)
            synthesizer.speak(utterance)
            last = utterance
        }
        guard last != nil else { return }
        await withCheckedContinuation { done = $0 }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        last = nil
        done?.resume()
        done = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in if let last = self.last, ObjectIdentifier(last) == id { self.finish() } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in if let last = self.last, ObjectIdentifier(last) == id { self.finish() } }
    }
}
