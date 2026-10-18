//
//  SearchView.swift
//  HapticRemote (iPhone)
//
//  "Search a place or stop", opened from the search field on the home
//  screen, and its voice search ("06 Search · Listening" in Figma), opened
//  from the microphone button there or in the field. One screen for both:
//  the same field and search, with Apple Maps' suggestions below it while
//  typing, or the microphone while listening. Picking a place (or saying
//  one: the first place Apple Maps finds) shows it on the home screen, in
//  the lavender card and on the map, ready to start walking directions.
//  The voice parts are in VoiceSearch.swift.
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

struct SearchView: View {
    /// Opens listening (the microphone button on the home screen) instead of typing.
    var startsListening = false
    /// A place was picked: the home screen closes this and shows it.
    var onPick: (Destination) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var search = PlaceSearch()
    @StateObject private var listener = SpeechListener()
    @FocusState private var fieldFocused: Bool
    @State private var mode: Mode = .typing
    @State private var phase: VoicePhase = .listening

    enum Mode {
        /// The keyboard and Apple Maps' suggestions.
        case typing
        /// The microphone: "06 Search · Listening".
        case listening
    }

    enum VoicePhase: Equatable {
        case listening
        case lookingUp
        /// Nothing to look up, or nothing found: the title and the line under it.
        case failed(String, String)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            field

            // Below the field: the suggestions, or the microphone while listening.
            // A plain cross-fade between the two, laid over the space under
            // the field rather than in it: then neither can push the title
            // and the field around, e.g. when the microphone doesn't fit yet
            // while the keyboard slides away, or both are there mid-fade.
            Color.clear
                .overlay(alignment: .top) {
                    switch mode {
                    case .typing:
                        results
                            .transition(.opacity)
                    case .listening:
                        voice
                            .transition(.opacity)
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, mode == .listening ? 10 : 0)
        // While listening there is no keyboard, so its room isn't kept free.
        // Otherwise, as the keyboard slides away, the microphone doesn't fit
        // above it yet and pushes the title down for a moment.
        .ignoresSafeArea(.keyboard, edges: mode == .listening ? .bottom : [])
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            listener.onFinish = finishedSpeaking
            if startsListening { listen() } else { fieldFocused = true }
        }
        .onDisappear { listener.stop() }
        // The words appear in the field as they are heard.
        .onChange(of: listener.transcript) { _, words in
            if mode == .listening { search.query = words }
        }
        // Tapping the field while listening: type instead.
        .onChange(of: fieldFocused) { _, focused in
            if focused, mode == .listening { typeInstead() }
        }
        .onChange(of: listener.failure) { _, failure in
            if let failure { phase = .failed(failure.title, failure.detail) }
        }
        .onChange(of: phase) { _, phase in
            // Not while listening: VoiceOver's voice would be heard as speech.
            if mode == .listening, phase != .listening {
                AccessibilityNotification.Announcement("\(voiceTitle). \(voiceSubtitle)").post()
            }
        }
        // The number of results, for VoiceOver users who can't see the list grow.
        .onChange(of: search.suggestions.count) { _, count in
            guard mode == .typing, !search.query.isEmpty else { return }
            AccessibilityNotification.Announcement(
                count == 0 ? "No results" : count == 1 ? "1 result" : "\(count) results").post()
        }
    }

    // MARK: - Header and field

    private var header: some View {
        HStack {
            Text("Where to?")
                .font(.atkinson(28, .extraBold, relativeTo: .title))
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Cancel") { dismiss() }
                .font(.atkinson(18, .bold, relativeTo: .body))
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
        }
    }

    /// The same field for both: typed text, or the words as they are heard
    /// (outlined in lavender while listening). The microphone button starts
    /// listening, or stops it and goes back to typing.
    private var field: some View {
        SearchBar(isListening: mode == .listening,
                  onMicrophone: { if mode == .listening { typeInstead() } else { listen() } }) {
            Image("icon-search")
                .accessibilityHidden(true)
            TextField("", text: $search.query,
                      prompt: Text(mode == .listening ? "Say where you want to go" : "Search a place or stop")
                        .foregroundStyle(Palette.secondaryText))
                .font(.atkinson(18, mode == .listening ? .medium : .regular, relativeTo: .body))
                .foregroundStyle(Palette.text)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    // Return picks the top suggestion.
                    if let first = search.suggestions.first { pick(first) }
                }
                .accessibilityLabel(mode == .listening ? "Heard" : "Search a place or stop")
            if mode == .typing {
                if !search.query.isEmpty {
                    Button {
                        search.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Palette.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
        }
    }

    // MARK: - Typing: results

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(search.suggestions, id: \.self) { suggestion in
                    row(suggestion)
                }
            }
            .padding(.bottom, 10)

            if let message = search.message {
                Text(message)
                    .font(.atkinson(17, relativeTo: .body))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func row(_ suggestion: MKLocalSearchCompletion) -> some View {
        Button {
            pick(suggestion)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "mappin")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 44, height: 44)
                    .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.atkinson(18, .bold, relativeTo: .headline))
                        .foregroundStyle(Palette.text)
                    if !suggestion.subtitle.isEmpty {
                        Text(suggestion.subtitle)
                            .font(.atkinson(15, relativeTo: .subheadline))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                if search.resolving == suggestion {
                    ProgressView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(search.resolving != nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows it on the home screen")
    }

    private func pick(_ suggestion: MKLocalSearchCompletion) {
        Task {
            if let destination = await search.resolve(suggestion) {
                onPick(destination)
            }
        }
    }

    // MARK: - Listening

    private var voice: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            // Tapped while listening: done talking, look it up now. Otherwise: listen again.
            Button {
                if phase == .listening, listener.isRunning { listener.finishNow() } else { listen() }
            } label: {
                ListeningCircles(level: phase == .listening ? listener.level : 0, reduceMotion: reduceMotion)
                    .opacity(phase == .listening ? 1 : 0.6)
            }
            .buttonStyle(.plain)
            .disabled(phase == .lookingUp)
            .accessibilityLabel(phase == .listening ? "Done talking" : "Listen again")

            VStack(spacing: 14) {
                Text(voiceTitle)
                    .font(.atkinson(30, .extraBold, relativeTo: .title))
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(voiceSubtitle)
                    .font(.atkinson(18, relativeTo: .body))
                    .foregroundStyle(Palette.secondaryText)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            // Clear of the circles: the outer one swells up to 24 points past
            // its frame on a loud word, and should never touch the title.
            .padding(.top, 40)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                chip("\"Take me home\"") { understand("take me home") }
                chip("\"Nearest stop\"") { understand("nearest stop") }
            }
            .frame(maxWidth: .infinity)

            Button(action: typeInstead) {
                HStack(spacing: 10) {
                    Image("icon-keyboard")
                        .accessibilityHidden(true)
                    Text("Type instead")
                        .font(.atkinson(20, .bold, relativeTo: .headline))
                        .foregroundStyle(Palette.text)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
    }

    private var voiceTitle: String {
        switch phase {
        case .listening: "Listening…"
        case .lookingUp: "Looking it up…"
        case .failed(let title, _): title
        }
    }

    private var voiceSubtitle: String {
        switch phase {
        case .listening: "Say a place, a stop or an address"
        case .lookingUp: "Finding \(search.query)"
        case .failed(_, let detail): detail
        }
    }

    private func chip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.atkinson(15, .bold, relativeTo: .subheadline))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Palette.card2, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(phase == .lookingUp)
    }

    // MARK: - Switching

    private func listen() {
        fieldFocused = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            mode = .listening
            phase = .listening
        }
        listener.start()
    }

    /// To typing, keeping what was heard so far in the field.
    private func typeInstead() {
        listener.stop()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { mode = .typing }
        fieldFocused = true
    }

    /// The user stopped talking.
    private func finishedSpeaking(_ words: String) {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            phase = .failed("Didn't catch that", "Tap the microphone and try again")
            return
        }
        understand(words)
    }

    /// Said or tapped: the nearest stop, home, or a place to look up.
    private func understand(_ words: String) {
        listener.stop()
        let spoken = words.lowercased()
        if spoken.contains("nearest") {
            phase = .lookingUp
            Task {
                let stop: Destination? = if let here = CLLocationManager().location?.coordinate {
                    await NearestStopFinder.find(near: here)
                } else {
                    nil
                }
                onPick(stop ?? .centraalAsNearest)
            }
            return
        }
        if spoken.contains("centraal") || spoken.contains("central station") {
            onPick(.centraal)
            return
        }
        if spoken == "home" || spoken.contains("take me home") || spoken.contains("go home") {
            // There is no home address in the app yet.
            phase = .failed("No home address yet", "Say a place, a stop or an address instead")
            return
        }
        phase = .lookingUp
        Task {
            if let destination = await PlaceLookup.find(words) {
                onPick(destination)
            } else {
                phase = .failed("Couldn't find \(words)", "Tap the microphone and try again, or type instead")
            }
        }
    }
}

// MARK: - Search bar

/// The search field with the microphone button beside it, the same on the
/// home screen and the search screen: what goes in it (a button, or the
/// text field) comes from `content`.
struct SearchBar<Content: View>: View {
    var showsMicrophone = true
    /// While listening: an X in the microphone's place, to stop, and a lavender outline.
    var isListening = false
    var onMicrophone: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            content

            if showsMicrophone {
                Button(action: onMicrophone) {
                    // Dark on lavender: the cream icon would barely show on it.
                    Group {
                        if isListening {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                        } else {
                            Image("icon-mic")
                                .renderingMode(.template)
                        }
                    }
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isListening ? "Stop listening" : "Search by voice")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, showsMicrophone ? 8 : 18)
        .frame(minHeight: 64)
        .glassButtonBackground(tint: nil, fallback: Palette.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            if isListening {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.accent, lineWidth: 2)
            }
        }
    }
}

// MARK: - Search

/// Apple Maps' suggestions for what the user typed, nearest first, and the
/// place behind the one they pick.
@MainActor
private final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            completer.queryFragment = query
            if query.isEmpty {
                suggestions = []
                message = nil
            }
        }
    }
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    /// Shown under the list: nothing found, or something went wrong.
    @Published private(set) var message: String?
    /// The suggestion being looked up after a tap.
    @Published private(set) var resolving: MKLocalSearchCompletion?

    private let completer = MKLocalSearchCompleter()
    /// Results near here come first: the user's last known position, or Amsterdam.
    private let region: MKCoordinateRegion

    override init() {
        let center = CLLocationManager().location?.coordinate
            ?? CLLocationCoordinate2D(latitude: 52.3731, longitude: 4.8926)
        region = MKCoordinateRegion(center: center, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        super.init()
        completer.delegate = self
        completer.region = region
        completer.resultTypes = [.pointOfInterest, .address]
    }

    /// Looks up where the picked suggestion is. Nil when it can't be found.
    func resolve(_ suggestion: MKLocalSearchCompletion) async -> Destination? {
        resolving = suggestion
        defer { resolving = nil }
        let request = MKLocalSearch.Request(completion: suggestion)
        request.region = region
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            message = "Couldn't find where \(suggestion.title) is. Try another result."
            AccessibilityNotification.Announcement(message!).post()
            return nil
        }
        return Destination(name: suggestion.title, subtitle: suggestion.subtitle,
                           coordinate: item.placemark.coordinate,
                           isStop: item.pointOfInterestCategory == .publicTransport)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.suggestions = results
            self.message = results.isEmpty && !self.query.isEmpty ? "No places found." : nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            // Typing fast cancels the previous search; that isn't worth a message.
            guard !self.query.isEmpty else { return }
            self.suggestions = []
            self.message = "Search isn't working right now. Check the internet connection."
        }
    }
}

#Preview {
    Typography.registerFonts()
    return SearchView(onPick: { _ in })
}

#Preview("Listening") {
    Typography.registerFonts()
    return SearchView(startsListening: true, onPick: { _ in })
}
