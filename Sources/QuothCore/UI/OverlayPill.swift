import QuothDomain
import SwiftUI

/// The pill: your words in quotes. Amber quotation marks, as in the app
/// icon, around a cream waveform on espresso; a lock when the recording is
/// locked, a laptop when it uses the Mac's microphone in place of playing
/// headphones, and the bars settling into dots while transcribing. The marks
/// lean in with your voice, unless Reduce Motion is on.
struct OverlayPill: View {
    @ObservedObject var model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Brand.espresso)
                    .shadow(color: .black.opacity(0.32), radius: 7, y: 2)
            )
            // A faint cream rim, so the pill holds its shape on a dark background.
            .overlay(
                Capsule()
                    .strokeBorder(Brand.cream.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(model.state == .hidden ? 0 : 1)
            .animation(
                .timingCurve(0.16, 1, 0.3, 1, duration: RecordingOverlay.scaleDuration),
                value: model.state
            )
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .hidden, .recording, .locked, .transcribing:
            HStack(spacing: 8) {
                quotes(opening: true, level: model.levels.first ?? 0)
                if model.state == .locked {
                    // The key is free; the next tap stops.
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.amber)
                        .transition(.scale.combined(with: .opacity))
                }
                if model.macMicrophone, model.state != .transcribing {
                    // Listening through the Mac, not the headphones.
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.amber)
                        .transition(.scale.combined(with: .opacity))
                }
                // The same bars throughout, so transcribing is the recording
                // bars settling rather than a swap to a spinner.
                Waveform(
                    levels: model.levels,
                    transcribing: model.state == .transcribing,
                    heardVoice: model.heardVoice
                )
                .frame(width: 51, height: 20)
                quotes(opening: false, level: model.levels.last ?? 0)
            }
            .animation(.easeOut(duration: 0.2), value: model.state)
        case .message(let text):
            HStack(spacing: 8) {
                QuotePair(opening: true).frame(width: 15, height: 12)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Brand.cream)
                    .lineLimit(1)
                    .fixedSize()
                QuotePair().frame(width: 15, height: 12)
            }
            .frame(height: 20)
        }
    }

    /// A pair of marks that leans toward the waveform as you speak: the
    /// opening pair rises, the closing one dips.
    private func quotes(opening: Bool, level: Float) -> some View {
        let lift = reduceMotion || model.state == .transcribing ? 0 : CGFloat(min(1, level)) * 2.5
        return QuotePair(opening: opening)
            .frame(width: 17, height: 14)
            .offset(y: opening ? 2 - lift : -2 + lift)
            .scaleEffect(1 + lift * 0.05)
            .animation(.easeOut(duration: 0.12), value: lift)
    }
}

/// The bars between the quotes.
private struct Waveform: View {
    let levels: [Float]
    var transcribing = false
    var heardVoice = false

    private struct Bar {
        var width: CGFloat = 2.5
        var height: CGFloat
        var opacity: Double = 1
    }

    /// Height of an idle bar after a silent recording, as a fraction of the
    /// full height.
    private static let restHeight: CGFloat = 0.2
    /// Size of the dots the middle bars settle into while transcribing.
    private static let dotSize: CGFloat = 3.5
    /// How long the bars take to settle into dots.
    private static let settleDuration = 0.25

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3.75) {
                ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                    let bar = bar(i, level: level, height: geo.size.height)
                    Capsule()
                        .fill(Brand.cream)
                        .frame(width: bar.width, height: bar.height)
                        .opacity(bar.opacity)
                        .animation(
                            transcribing ? .easeInOut(duration: Self.settleDuration) : .easeOut(duration: 0.09),
                            value: bar.height
                        )
                        .animation(.easeInOut(duration: Self.settleDuration), value: bar.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// While recording, each bar follows the level. While transcribing, the
    /// outer bars fade where they stand and the middle ones settle into dots;
    /// after a silent recording, every bar just rests.
    private func bar(_ i: Int, level: Float, height: CGFloat) -> Bar {
        let live = max(0.10, CGFloat(level)) * height
        guard transcribing else { return Bar(height: live) }
        guard heardVoice else { return Bar(height: Self.restHeight * height) }
        let outer = i == 0 || i == levels.count - 1
        return outer ? Bar(height: live, opacity: 0) : Bar(width: Self.dotSize, height: Self.dotSize)
    }
}
