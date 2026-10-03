import Foundation

/// Where to cut a locked recording into segments for live text (fork
/// addition). Pure, so the rules are tested without a microphone.
///
/// A segment ends inside the first pause of at least `minPause` that leaves
/// it at least `minSegment` long, with half a pause of silence either side
/// of the cut; a long pause can be cut anywhere after the minimum. With no such pause it ends at
/// the quietest moment before `maxSegment`, since Whisper hears 30 s at a
/// time. Loudness is the RMS of 30 ms frames, against a threshold that
/// rises with the background noise.
public enum PauseSplitter {
    public static let sampleRate = 16_000.0
    /// 30 ms at 16 kHz.
    public static let frameLength = 480
    /// Segments shorter than this give Whisper too little context.
    public static let minSegment: TimeInterval = 4
    /// A gap this long is a pause between sentences. Shorter ones happen
    /// mid-sentence, and a cut there makes Whisper end the segment with a
    /// period that can't be taken back once typed.
    public static let minPause: TimeInterval = 1.0
    /// Cut even without a pause by now.
    public static let maxSegment: TimeInterval = 25
    /// Frames quieter than this are silence on a quiet microphone. Silent
    /// recordings measure about 0.001; speech averages 0.06 to 0.08.
    public static let minThreshold: Float = 0.008
    /// The threshold never rises above this, however noisy the room.
    public static let maxThreshold: Float = 0.03
    /// Consecutive loud frames that make speech rather than a key click or
    /// a thump: 240 ms. A typed key is 30 to 160 ms.
    public static let minSpeechRun = 8

    public struct Cut: Equatable {
        /// Samples from the start that make up the segment.
        public var end: Int
        /// Whether the segment holds speech. A silent one is dropped, since
        /// Whisper invents text ("Thank you.") for silence.
        public var hasSpeech: Bool
    }

    /// The next segment of `samples`, or nil to wait for more audio.
    public static func cut(_ samples: [Float]) -> Cut? {
        let levels = frameLevels(samples)
        guard !levels.isEmpty else { return nil }
        let threshold = self.threshold(levels)
        let minFrames = frames(minSegment)
        let pauseFrames = frames(minPause)
        let maxFrames = frames(maxSegment)

        var runStart: Int?
        for (i, level) in levels.enumerated() {
            if level < threshold {
                let start = runStart ?? i
                runStart = start
                let cutFrame = max(start + pauseFrames / 2, minFrames)
                if i + 1 - cutFrame >= pauseFrames / 2, i - start + 1 >= pauseFrames {
                    return makeCut(atFrame: cutFrame, levels: levels, threshold: threshold)
                }
            } else {
                runStart = nil
            }
        }

        guard levels.count >= maxFrames else { return nil }
        // No pause in time: cut at the quietest stretch in the second half.
        let window = pauseFrames / 2
        var best = maxFrames / 2
        var bestLevel = Float.greatestFiniteMagnitude
        for start in (maxFrames / 2)..<(maxFrames - window) {
            let level = levels[start..<(start + window)].reduce(0, +)
            if level < bestLevel {
                bestLevel = level
                best = start + window / 2
            }
        }
        return makeCut(atFrame: best, levels: levels, threshold: threshold)
    }

    /// `samples` cut at each pause, as live text cuts a locked recording,
    /// leaving out parts with no speech. One part when there is no pause.
    public static func parts(_ samples: [Float]) -> [[Float]] {
        var parts: [[Float]] = []
        var offset = 0
        while offset < samples.count, let cut = cut(Array(samples[offset...])), cut.end > 0 {
            if cut.hasSpeech { parts.append(Array(samples[offset..<offset + cut.end])) }
            offset += cut.end
        }
        let rest = Array(samples[offset...])
        if hasSpeech(rest) { parts.append(rest) }
        return parts
    }

    /// Whether `samples` hold speech: for the tail left when a lock ends,
    /// and for a push-to-talk dictation, which takes a shorter `minRun`
    /// (150 ms) so a short "Yes." still counts.
    public static func hasSpeech(_ samples: [Float], minRun: Int = minSpeechRun) -> Bool {
        let levels = frameLevels(samples)
        return speech(in: levels[...], threshold: threshold(levels), minRun: minRun)
    }

    /// Consecutive loud frames for push-to-talk: 150 ms.
    public static let minPushToTalkRun = 5

    // MARK: - Helpers

    private static func makeCut(atFrame frame: Int, levels: [Float], threshold: Float) -> Cut {
        Cut(end: frame * frameLength, hasSpeech: speech(in: levels[..<frame], threshold: threshold))
    }

    private static func speech(in levels: ArraySlice<Float>, threshold: Float, minRun: Int = minSpeechRun) -> Bool {
        var run = 0
        for level in levels {
            run = level >= threshold ? run + 1 : 0
            if run >= minRun { return true }
        }
        return false
    }

    private static func frames(_ seconds: TimeInterval) -> Int {
        Int(seconds * sampleRate) / frameLength
    }

    public static func frameLevels(_ samples: [Float]) -> [Float] {
        let count = samples.count / frameLength
        guard count > 0 else { return [] }
        return samples.withUnsafeBufferPointer { buffer in
            (0..<count).map { i in
                var power: Float = 0
                for sample in buffer[(i * frameLength)..<((i + 1) * frameLength)] {
                    power += sample * sample
                }
                return (power / Float(frameLength)).squareRoot()
            }
        }
    }

    /// 2.5 × the background noise (the 20th percentile frame), clamped.
    public static func threshold(_ levels: [Float]) -> Float {
        guard !levels.isEmpty else { return minThreshold }
        let floor = levels.sorted()[levels.count / 5]
        return min(maxThreshold, max(minThreshold, floor * 2.5))
    }
}
