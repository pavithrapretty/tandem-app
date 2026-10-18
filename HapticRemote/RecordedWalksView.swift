//
//  RecordedWalksView.swift
//  HapticRemote (iPhone)
//
//  Settings, Recorded walks: the real walks recorded on this phone
//  (TripRecorder), newest first. Each can be shared (AirDrop to a Mac, to
//  look through what the guidance did), replayed through the navigation
//  screen (TripReplay), or deleted. The switch at the top turns recording off.
//

import SwiftUI

struct RecordedWalksView: View {
    /// For the replay, which vibrates here and on the watch like a walk.
    @ObservedObject var connectivity: ConnectivityManager
    @ObservedObject var phoneHaptics: PhoneHapticPlayer

    @AppStorage(TripRecorder.settingKey) private var recordsWalks = true
    @State private var walks: [RecordedWalk] = []
    @State private var replaying: TripReplay?
    @State private var deleting: RecordedWalk?

    var body: some View {
        TutorialPage {
            Text("Recorded walks")
                .font(.atkinson(34, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.68)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $recordsWalks) {
                    Text("Record walks")
                        .font(.atkinson(19, .bold, relativeTo: .headline))
                        .foregroundStyle(Palette.text)
                }
                .tint(Palette.accent)
                Text("Saves the GPS, steps and compass of each walk on this phone only, to look back at why the guidance did what it did. Nothing is sent anywhere unless you share it.")
                    .font(.atkinson(16, relativeTo: .callout))
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))

            if walks.isEmpty {
                Text("No walks recorded yet. They appear here after you navigate somewhere.")
                    .font(.atkinson(17, relativeTo: .body))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                ForEach(walks) { walk in
                    card(walk)
                }
            }

            Spacer(minLength: 0)
        }
        .onAppear { walks = RecordedWalk.all() }
        .fullScreenCover(item: $replaying) { replay in
            GuidanceView(destination: replay.walk.destination, replay: replay,
                         connectivity: connectivity, phoneHaptics: phoneHaptics)
        }
        .confirmationDialog("Delete this walk?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let deleting { try? FileManager.default.removeItem(at: deleting.url) }
                deleting = nil
                walks = RecordedWalk.all()
            }
        }
        .navigationTitle("Recorded walks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func card(_ walk: RecordedWalk) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("To \(walk.destination.name)")
                    .font(.atkinson(19, .bold, relativeTo: .headline))
                    .foregroundStyle(Palette.text)
                Text(details(walk))
                    .font(.atkinson(16, relativeTo: .callout))
                    .foregroundStyle(Palette.secondaryText)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                Button {
                    replaying = TripReplay(walk)
                } label: {
                    action("Replay", systemImage: "play.fill")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Plays the walk back on the navigation screen, in real time.")

                ShareLink(item: walk.url) {
                    action("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)

                Button {
                    deleting = walk
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .frame(width: 48, height: 48)
                        .glassButtonBackground(tint: nil, fallback: Palette.card2,
                                               in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func action(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.atkinson(16, .bold, relativeTo: .callout))
        }
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, minHeight: 48)
        .glassButtonBackground(tint: nil, fallback: Palette.card2, in: RoundedRectangle(cornerRadius: 16))
    }

    /// "18 Oct, 15:04 · 12 min · 0.8 MB"
    private func details(_ walk: RecordedWalk) -> String {
        let date = walk.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        let minutes = max(1, Int((walk.duration / 60).rounded()))
        let size = ByteCountFormatter.string(fromByteCount: Int64(walk.bytes), countStyle: .file)
        return "\(date) · \(minutes) min · \(size)"
    }
}
