//
//  RecordedVoice.swift
//  HapticRemote (iPhone)
//
//  Recorded voice lines for the tutorial (mp3 files in this folder), played
//  one straight after the other: the intro, and on the signals screen a
//  signal's line followed by "next signal". They start a second after
//  `play()` (or later, if asked), so the screen has settled first. Other
//  apps' audio is turned down while they play, and comes back up when they
//  end or are stopped.
//
//  VoiceMuteButton, in the tutorial's navigation bar, mutes them for the
//  whole tutorial (and next time). Muted, they still play silently, so the
//  timings around them stay the same.
//

import AVFoundation
import SwiftUI

final class RecordedVoice: NSObject, AVAudioPlayerDelegate {
    /// UserDefaults key: true = the recordings are muted.
    static let mutedKey = "tutorialVoiceMuted"

    /// Set from VoiceMuteButton's setting; works on clips already playing too.
    var isMuted = UserDefaults.standard.bool(forKey: RecordedVoice.mutedKey) {
        didSet { players.forEach { $0.volume = isMuted ? 0 : 1 } }
    }
    /// After the last clip has played to its end (not when stopped).
    var onFinish: (() -> Void)?
    /// From the first clip's start to the last one's end, from when they are
    /// set to play until they end or are stopped.
    private(set) var playback: ClosedRange<Date>?
    /// The clips have ended or were stopped.
    private(set) var isOver = false

    /// All the clips together, in seconds.
    var duration: TimeInterval { players.reduce(0) { $0 + $1.duration } }

    /// Seconds played at `date`: 0 before the first clip starts, the full
    /// length once they have ended or were stopped.
    func played(at date: Date) -> TimeInterval {
        guard let playback else { return isOver ? duration : 0 }
        return min(max(date.timeIntervalSince(playback.lowerBound), 0), duration)
    }

    private let players: [AVAudioPlayer]
    /// Set by `stop()`, so a `play()` still switching the session on doesn't
    /// start after all.
    private var isStopped = false
    /// The audio session is on for these clips, until they end or are stopped.
    private var sessionIsOn = false
    /// From `play()` to the first clip, at the least.
    private static let minimumDelay: TimeInterval = 1

    /// `names`: mp3 files in the app, without ".mp3". A missing one is left out.
    init(_ names: [String]) {
        players = names.compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "mp3")
                .flatMap { try? AVAudioPlayer(contentsOf: $0) }
        }
        super.init()
        players.forEach {
            $0.volume = isMuted ? 0 : 1
            $0.prepareToPlay()
        }
        players.last?.delegate = self
    }

    /// `delay`: seconds before the first clip, never less than one.
    func play(after delay: TimeInterval = 0) async {
        guard let first = players.first else { return }
        isStopped = false
        isOver = false
        try? await AudioSessionQueue.run { session in
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        }
        // Left the screen while the session was switching on.
        guard !Task.isCancelled, !isStopped else { return AudioSessionQueue.deactivate() }
        sessionIsOn = true
        let wait = max(delay, Self.minimumDelay)
        let begin = Date() + wait
        playback = begin...(begin + duration)
        // All on the audio clock, so each starts the moment the one before
        // it ends, with no gap.
        var start = first.deviceCurrentTime + wait
        for player in players {
            player.currentTime = 0
            player.play(atTime: start)
            start += player.duration
        }
    }

    /// Also cancels clips that are still waiting for their turn.
    func stop() {
        isStopped = true
        playback = nil
        isOver = true
        players.forEach { $0.stop() }
        guard sessionIsOn else { return }
        sessionIsOn = false
        AudioSessionQueue.deactivate()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.sessionIsOn else { return }
            self.sessionIsOn = false
            self.playback = nil
            self.isOver = true
            AudioSessionQueue.deactivate()
            self.onFinish?()
        }
    }
}

/// A thin line that fills up as the voice plays, in the style of the
/// tutorial's progress bar. On the intro, above "Welcome to Tandem".
struct VoiceProgressBar: View {
    let voice: RecordedVoice

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let fraction = voice.duration > 0 ? voice.played(at: context.date) / voice.duration : 0
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.track)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.text)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement()
        .accessibilityLabel("Voice, \(Int(voice.duration.rounded())) seconds")
    }
}

/// Mutes and unmutes the tutorial's recorded voice. Next to the back arrow,
/// or top left on the intro, which has none.
struct VoiceMuteButton: View {
    @AppStorage(RecordedVoice.mutedKey) private var isMuted = false

    var body: some View {
        Button {
            isMuted.toggle()
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.body.weight(.semibold))
                // The same width either way, so the bar doesn't shift.
                .frame(width: 28)
        }
        .accessibilityLabel("Voice")
        .accessibilityValue(isMuted ? "Muted" : "On")
        .accessibilityHint(isMuted ? "Plays the recorded voice again." : "Mutes the recorded voice.")
    }
}
