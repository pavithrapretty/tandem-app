//
//  TutorialCoach.swift
//  HapticRemote (iPhone)
//
//  Plays a signal for the tutorial: the vibration and the voice line, over
//  and over without an extra pause, until the screen changes. In practice only the vibration plays.
//
//  Every screen passes its own `owner` name. When you move between screens,
//  the new screen can appear before the old one disappears; the owner makes
//  sure the old screen's "stop" can't silence the new screen's signal.
//

import AVFoundation
import Combine

@MainActor
final class TutorialCoach: ObservableObject {
    /// True for a short moment every time a tap of the vibration fires, so
    /// the dial can flash along with it.
    @Published private(set) var isLit = false
    /// How the dial's rings move, for a preset that moves them its own way.
    @Published private(set) var ringSwell: RingSwell?

    private let haptics = PhoneHapticPlayer()
    private let voice = AVSpeechSynthesizer()

    /// TODO: switch back to true to speak the voice lines again. Off for now
    /// because hearing them on every screen gets in the way while testing.
    private let speaksVoiceLines = false

    /// The longest pause between the last tap of a round and the first tap of
    /// the next one, so the vibration feels continuous. (`playbackDuration`
    /// already adds 0.3 s after the last tap, so the gap is 1.2 s.) It is
    /// still clearly longer than the gaps inside a pattern (at most 0.9 s, in
    /// Turn right), so each round is felt as one group.
    private let maxPause: TimeInterval = 0.9

    /// The loop that is running, and the screen that started it.
    private var loopTask: Task<Void, Never>?
    private var owner: String?

    /// Muted = no vibration and no voice. The Xcode previews use this, so the
    /// canvas doesn't keep talking while you look at a screen.
    private let isMuted: Bool

    init(muted: Bool = false) {
        isMuted = muted
        haptics.$isLit.assign(to: &$isLit)
        haptics.$ringSwell.assign(to: &$ringSwell)
        // The voice gets its own audio session. The haptics library shares the
        // app's session and switches it off when a vibration ends, which used
        // to cut the voice off halfway through the sentence.
        voice.usesApplicationAudioSession = false
    }

    /// Play `signal` again and again until `stop(owner:)` or another `start`.
    func start(_ signal: TutorialSignal, speak: Bool = true, owner: String) {
        stopAll()
        guard !isMuted else { return }
        self.owner = owner
        // The pattern's own rhythm (as on the home screen), but never a longer
        // pause than `maxPause`. Signal lost, for example, really buzzes every
        // 10 seconds; in the tutorial it repeats right away.
        let roundLength = min(signal.pattern.runLength,
                              signal.pattern.playbackDuration + maxPause)
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.playRound(signal, speak: speak, lasting: roundLength)
            }
        }
    }

    /// Play `signal` a single time (the rows on the Ready screen).
    func playOnce(_ signal: TutorialSignal, speak: Bool = false, owner: String) {
        stopAll()
        guard !isMuted else { return }
        self.owner = owner
        loopTask = Task { [weak self] in
            await self?.playRound(signal, speak: speak, lasting: signal.pattern.playbackDuration)
        }
    }

    /// Stop, but only if `owner` is the screen that is playing.
    func stop(owner: String) {
        guard owner == self.owner else { return }
        stopAll()
    }

    private func stopAll() {
        loopTask?.cancel()
        loopTask = nil
        owner = nil
        haptics.stop()
        voice.stopSpeaking(at: .immediate)
    }

    /// One vibration with the voice line at the same time. Returns after
    /// `seconds`, or later if the voice is still speaking.
    private func playRound(_ signal: TutorialSignal, speak: Bool, lasting seconds: TimeInterval) async {
        haptics.play(signal.pattern, vibrate: true, once: true)
        if speak && speaksVoiceLines {
            voice.speak(.tandem(signal.voiceLine))
        }

        let clock = ContinuousClock()
        let roundEnd = clock.now + .seconds(seconds)
        // Wait until the round is over and the voice has finished speaking.
        while !Task.isCancelled && (clock.now < roundEnd || voice.isSpeaking) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

private extension Pattern {
    /// How long one run of the pattern takes, including the pause at the end
    /// before it starts again (the same timing the home screen loops with).
    var runLength: TimeInterval {
        steps.reduce(0) { $0 + max($1.delay, Pattern.minimumGap) }
    }
}
