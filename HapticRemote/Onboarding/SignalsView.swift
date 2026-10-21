//
//  SignalsView.swift
//  HapticRemote (iPhone)
//
//  "04.2 – 04.7 Tutorial": the six signals, on one screen. "Next signal"
//  slides the next one in from the right; Back (or a swipe to the right)
//  slides the previous one back in from the left. The progress bar, the label
//  and the button stay where they are; only the signal itself moves.
//
//  The vibration loops by itself while a signal is shown, and the signal's
//  recorded voice (if it has one) plays once each time it slides in. Then,
//  once the line and the first round of the vibration are over, a voice says
//  to go on to the next signal (not on the last one, whose button is
//  Practise). Next to "SIGNAL 1 OF 6", the time the voice has played and
//  how long it is, e.g. "0:03 / 0:16".
//

import SwiftUI

struct SignalsView: View {
    @ObservedObject var coach: TutorialCoach
    /// Called after the last signal ("Practise").
    var onFinish: () -> Void

    /// Index into `TutorialSignal.all` of the signal on screen.
    @State private var index: Int
    /// Which way the signals slide: forward = in from the right.
    @State private var movingForward = true
    /// The recorded voice of the signal on screen.
    @State private var voice: RecordedVoice?
    @AppStorage(RecordedVoice.mutedKey) private var voiceMuted = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let owner = "signals"
    private var signals: [TutorialSignal] { TutorialSignal.all }
    private var signal: TutorialSignal { signals[index] }
    private var isLast: Bool { index == signals.count - 1 }

    /// `startIndex` is only passed in by the previews.
    init(coach: TutorialCoach, startIndex: Int = 0, onFinish: @escaping () -> Void) {
        self.coach = coach
        self.onFinish = onFinish
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        TutorialPage(tint: signal.color) {
            TutorialProgress(filled: index + 1)

            HStack {
                Eyebrow("SIGNAL \(index + 1) OF \(signals.count)")
                    .accessibilityLabel("Signal \(index + 1) of \(signals.count)")
                if let voice {
                    VoiceTime(voice: voice)
                }
            }

            // The part that slides. A new id per signal makes SwiftUI swap the
            // whole block, which runs the transition.
            signalContent
                .id(index)
                .transition(slide)
                .frame(maxHeight: .infinity)

            PrimaryButton(isLast ? "Practise" : "Next signal", action: next)
        }
        // Our own Back button: it steps back through the signals first, and
        // only leaves this screen from the first one.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: back) {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Back")
                VoiceMuteButton()
            }
        }
        // Swipe left for the next signal, right for the previous one.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height),
                          abs(drag.translation.width) > 60 else { return }
                    if drag.translation.width < 0 {
                        if !isLast { next() }
                    } else {
                        back()
                    }
                }
        )
        .onAppear {
            coach.start(signal, owner: owner)
            playRecording()
        }
        .onDisappear {
            coach.stop(owner: owner)
            voice?.stop()
        }
        .onChange(of: voiceMuted) { voice?.isMuted = voiceMuted }
        .onChange(of: index) {
            coach.start(signal, owner: owner)
            playRecording()
            // Move VoiceOver to the top of the new signal.
            AccessibilityNotification.ScreenChanged().post()
        }
    }

    private var signalContent: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            DirectionDial(signal: signal, isLit: coach.isLit, ringSwell: coach.ringSwell)
                // Only a picture: the title below says the same.
                .accessibilityHidden(true)

            Text(signal.title)
                .font(.atkinson(38, .extraBold, relativeTo: .largeTitle))
                .tracking(-0.76)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(signal.feel)
                .font(.atkinson(19, .bold, relativeTo: .title3))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Image("icon-volume-small")
                    .accessibilityHidden(true)
                Text("\u{201C}\(signal.voiceLine)\u{201D}")
                    .font(.atkinson(16, .medium, relativeTo: .callout))
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Voice says: \(signal.voiceLine)")

            Text(signal.tip)
                .font(.atkinson(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.caption)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
    }

    /// The signal's recorded voice, then "next signal", once; whatever was
    /// playing stops.
    private func playRecording() {
        voice?.stop()
        let clips = [signal.recording, isLast ? nil : "next signal"].compactMap { $0 }
        guard !clips.isEmpty else { return voice = nil }
        let voice = RecordedVoice(clips)
        self.voice = voice
        // Without a line of its own, "next signal" waits for the first round
        // of the vibration; a line is longer than a round anyway.
        let delay = signal.recording == nil ? signal.pattern.playbackDuration : 0
        Task { await voice.play(after: delay) }
    }

    /// In from the right going forward, in from the left going back.
    /// With Reduce Motion: a fade.
    private var slide: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading),
            removal: .move(edge: movingForward ? .leading : .trailing))
            .combined(with: .opacity)
    }

    private func next() {
        guard !isLast else {
            onFinish()
            return
        }
        movingForward = true
        withAnimation(.smooth(duration: 0.35)) { index += 1 }
    }

    private func back() {
        guard index > 0 else {
            dismiss()
            return
        }
        movingForward = false
        withAnimation(.smooth(duration: 0.35)) { index -= 1 }
    }
}

/// How far the voice has got and how long it is, "0:03 / 0:16", counting
/// up while it plays. Before it starts it shows 0:00; once it has ended, or
/// been stopped, the full length.
private struct VoiceTime: View {
    let voice: RecordedVoice

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            Text("\(Self.format(voice.played(at: context.date))) / \(Self.format(voice.duration))")
                .font(.atkinson(14, .bold, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(Palette.caption)
                .fixedSize()
        }
        // Read once, not every quarter second.
        .accessibilityLabel("Voice, \(Int(voice.duration.rounded())) seconds")
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// The big round dial: two thin rings around a glass circle in the signal's
/// colour, with the arrow on top. The circle and its halo light up with every
/// tap of the vibration, like the buttons on the home screen, and the halo
/// and rings swell outwards with it, like a ripple.
struct DirectionDial: View {
    let signal: TutorialSignal
    var isLit = false
    /// Set while a preset moves the rings its own way (Coil); nil = the rings
    /// swell with `isLit`.
    var ringSwell: RingSwell? = nil
    /// Width and height. Drawn at 250 pt (the tutorial) and scaled from there;
    /// the navigation screens use 280.
    var size: CGFloat = 250

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Halo
            Circle()
                .fill(signal.color.opacity(isLit ? 0.3 : 0.12))
                .modifier(Swell(isLit: isLit, ringSwell: ringSwell, scale: 1.08, enabled: !reduceMotion))
            Circle()
                .stroke(signal.color.opacity(0.25), lineWidth: 2)
                .frame(width: 244, height: 244)
                .modifier(Swell(isLit: isLit, ringSwell: ringSwell, scale: 1.1, enabled: !reduceMotion))
            Circle()
                .stroke(signal.color.opacity(0.55), lineWidth: 2)
                .frame(width: 214, height: 214)
                .modifier(Swell(isLit: isLit, ringSwell: ringSwell, scale: 1.06, enabled: !reduceMotion))

            // 80% colour so the Liquid Glass shows through; full colour on a tap.
            Circle()
                .fill(.clear)
                .frame(width: 176, height: 176)
                .glassButtonBackground(signal.color.opacity(isLit ? 1 : 0.8), in: Circle())

            // A new id per arrow, so a change of signal cross-fades the arrow
            // (when the change is animated) instead of swapping it.
            Image(signal.dialIcon)
                .id(signal.dialIcon)
                .transition(.opacity)
        }
        .frame(width: 250, height: 250)
        .scaleEffect(size / 250)
        .frame(width: size, height: size)
    }
}

/// Grows a ring to `scale` while the vibration taps: out fast, back slowly.
/// With a `ringSwell` (Coil), the ring follows that instead. Only the size
/// animates; the colour flash stays instant. Off with Reduce Motion (the
/// colour still flashes).
private struct Swell: ViewModifier {
    let isLit: Bool
    let ringSwell: RingSwell?
    let scale: CGFloat
    let enabled: Bool

    private var level: Double { ringSwell?.level ?? (isLit ? 1 : 0) }
    private var animation: Animation {
        ringSwell?.animation ?? (isLit ? .easeOut(duration: 0.08) : .easeOut(duration: 0.35))
    }

    func body(content: Content) -> some View {
        content.animation(animation) {
            $0.scaleEffect(enabled ? 1 + (scale - 1) * level : 1)
        }
    }
}
