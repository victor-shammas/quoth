import XCTest
@testable import QuothCore

/// Synthetic audio: "speech" is a loud tone, a pause is near-silence.
private enum Audio {
    static func speech(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.1)) * 0.1 }
    }

    static func pause(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.1)) * 0.0005 }
    }
}

final class PauseSplitterTests: XCTestCase {
    func testWaitsWhileSpeechIsShort() {
        XCTAssertNil(PauseSplitter.cut(Audio.speech(2) + Audio.pause(1.5)))
    }

    func testCutsInTheFirstPauseAfterTheMinimum() throws {
        let audio = Audio.speech(2) + Audio.pause(1.5) + Audio.speech(3) + Audio.pause(1.5) + Audio.speech(2)
        let cut = try XCTUnwrap(PauseSplitter.cut(audio))
        XCTAssertTrue(cut.hasSpeech)
        // Inside the second pause, which starts at 6.5 s.
        XCTAssertGreaterThan(cut.end, Int(6.5 * 16_000))
        XCTAssertLessThan(cut.end, Int(7.5 * 16_000))
    }

    func testWaitsUntilThePauseIsLongEnough() {
        // A mid-sentence gap is not a pause; a second between sentences is.
        XCTAssertNil(PauseSplitter.cut(Audio.speech(5) + Audio.pause(0.8)))
        XCTAssertNotNil(PauseSplitter.cut(Audio.speech(5) + Audio.pause(1.2)))
    }

    func testCutsWithoutAPauseAtTheLimit() throws {
        XCTAssertNil(PauseSplitter.cut(Audio.speech(20)))
        let cut = try XCTUnwrap(PauseSplitter.cut(Audio.speech(26)))
        XCTAssertLessThanOrEqual(cut.end, 25 * 16_000)
        XCTAssertGreaterThanOrEqual(cut.end, Int(12.5 * 16_000))
    }

    func testALongPauseBeforeTheMinimumIsCutAtTheMinimum() throws {
        let cut = try XCTUnwrap(PauseSplitter.cut(Audio.speech(2) + Audio.pause(5)))
        XCTAssertTrue(cut.hasSpeech)
        XCTAssertEqual(cut.end, Int(PauseSplitter.minSegment * 16_000) / PauseSplitter.frameLength * PauseSplitter.frameLength)
    }

    func testSilenceIsCutWithoutSpeech() throws {
        let cut = try XCTUnwrap(PauseSplitter.cut(Audio.pause(6)))
        XCTAssertFalse(cut.hasSpeech)
    }

    func testKeyClicksAreNotSpeech() {
        // Five 40 ms clicks in 6 s of quiet room: typing while locked.
        var audio = Audio.pause(6)
        for at in [1.0, 2.0, 3.0, 4.0, 5.0] {
            let start = Int(at * 16_000)
            for i in start..<(start + 640) { audio[i] = Float(sin(Double(i) * 0.1)) * 0.1 }
        }
        // Whether or not the gaps are long enough to cut, clicks are never speech.
        XCTAssertNotEqual(PauseSplitter.cut(audio)?.hasSpeech, true)
        XCTAssertFalse(PauseSplitter.hasSpeech(audio))
        XCTAssertFalse(PauseSplitter.hasSpeech(Audio.pause(0.3) + Audio.speech(0.16) + Audio.pause(0.3)))
    }

    func testPushToTalkTakesShortWordsButNotSilence() {
        // A short "Yes." of about 200 ms between silences.
        XCTAssertTrue(PauseSplitter.hasSpeech(Audio.pause(0.5) + Audio.speech(0.2) + Audio.pause(0.5), minRun: PauseSplitter.minPushToTalkRun))
        XCTAssertFalse(PauseSplitter.hasSpeech(Audio.pause(2), minRun: PauseSplitter.minPushToTalkRun))
        XCTAssertFalse(PauseSplitter.hasSpeech([Float](repeating: 0, count: 32_000), minRun: PauseSplitter.minPushToTalkRun))
    }

    func testHasSpeech() {
        XCTAssertTrue(PauseSplitter.hasSpeech(Audio.pause(1.5) + Audio.speech(0.5)))
        XCTAssertFalse(PauseSplitter.hasSpeech(Audio.pause(2)))
        XCTAssertFalse(PauseSplitter.hasSpeech([]))
    }

    func testThresholdRisesWithNoiseWithinLimits() {
        XCTAssertEqual(PauseSplitter.threshold([0.0001, 0.0001, 0.0001, 0.0001, 0.0001]), PauseSplitter.minThreshold)
        XCTAssertEqual(PauseSplitter.threshold([0.1, 0.1, 0.1, 0.1, 0.1]), PauseSplitter.maxThreshold)
        XCTAssertEqual(PauseSplitter.threshold([0.01, 0.01, 0.01, 0.01, 0.01]), 0.025, accuracy: 0.0001)
    }
}

/// Answers each segment with its length in whole seconds, after a delay
/// that makes later segments finish first unless they are run in order.
/// Records the context each segment got, and fails segments of `failing`
/// seconds.
private final class SecondsTranscriber: Transcriber, @unchecked Sendable {
    let modelID = "fake"
    var failing: Int?
    private(set) var contexts: [TranscriptionContext] = []
    private let lock = NSLock()

    func transcribe(_ audio: [Float], context: TranscriptionContext) async throws -> Transcript {
        let seconds = audio.count / 16_000
        lock.withLock { contexts.append(context) }
        try await Task.sleep(nanoseconds: UInt64(max(0, 30 - seconds)) * 1_000_000)
        if seconds == failing { throw CancellationError() }
        var timings = TranscriberTimings()
        timings.language = "de"
        return Transcript(text: "\(seconds)s", timings: timings)
    }
}

@MainActor
final class LiveTranscriptionTests: XCTestCase {
    private var recording: [Float] = []
    private var typed: [String] = []
    private var copied: [String] = []
    private var failNext: DeliveryError?
    private var notices: [String] = []
    private let transcriber = SecondsTranscriber()

    private func makeLive() -> LiveTranscription {
        LiveTranscription(
            samples: { [unowned self] offset in offset < recording.count ? Array(recording[offset...]) : [] },
            transcriber: transcriber,
            context: TranscriptionContext(),
            processors: [],
            deliver: { [unowned self] text in
                if let error = failNext {
                    failNext = nil
                    if error == .focusChanged { copied.append(text) }
                    throw error
                }
                typed.append(text)
            },
            copy: { [unowned self] in copied.append($0) },
            notice: { [unowned self] in notices.append(($0 as? UserFacingError)?.userMessage ?? "\($0)") }
        )
    }

    func testSegmentsAreTypedInOrderAndTheTailAtTheEnd() async {
        let live = makeLive()
        recording = Audio.speech(10) + Audio.pause(1.5)
        live.poll()
        recording += Audio.speech(5) + Audio.pause(1.5)
        live.poll()
        recording += Audio.speech(2)
        let outcome = await live.finish(capture: recording)
        XCTAssertEqual(typed.count, 3)
        XCTAssertEqual(typed.first, "10s")
        XCTAssertEqual(outcome.segments, 3)
        XCTAssertNil(outcome.deliveryError)
        XCTAssertEqual(outcome.text, typed.joined(separator: " "))
        XCTAssertTrue(copied.isEmpty)
    }

    func testSegmentsContinueThePreviousOneInItsLanguage() async {
        let live = makeLive()
        recording = Audio.speech(10) + Audio.pause(1.5)
        live.poll()
        recording += Audio.speech(5)
        _ = await live.finish(capture: recording)
        XCTAssertEqual(transcriber.contexts.count, 2)
        XCTAssertNil(transcriber.contexts[0].previousText)
        XCTAssertNil(transcriber.contexts[0].language)
        XCTAssertEqual(transcriber.contexts[1].previousText, "10s")
        XCTAssertEqual(transcriber.contexts[1].language, "de")
    }

    func testAFailedSegmentIsReportedAtOnce() async {
        let live = makeLive()
        transcriber.failing = 10
        recording = Audio.speech(10) + Audio.pause(1.5)
        live.poll()
        await live.waitForSegments()
        XCTAssertEqual(notices, [LiveTextNotice.segmentFailed.userMessage])
        recording += Audio.speech(5)
        let outcome = await live.finish(capture: recording)
        XCTAssertEqual(typed.count, 1)
        XCTAssertNotNil(outcome.transcriptionError)
    }

    func testAFocusChangeIsReportedAtOnce() async {
        let live = makeLive()
        recording = Audio.speech(10) + Audio.pause(1.5)
        failNext = .focusChanged
        live.poll()
        await live.waitForSegments()
        XCTAssertEqual(notices, [DeliveryError.focusChanged.userMessage])
    }

    func testHeldTextJoinsLikeDictations() {
        XCTAssertEqual(LiveTranscription.join(["One.", "Two."]), "One. Two.")
        XCTAssertEqual(LiveTranscription.join(["今日は", "晴れです"]), "今日は晴れです")
        XCTAssertEqual(LiveTranscription.join(["Hi", ", there"]), "Hi, there")
    }

    func testSilentSegmentsAreNotTranscribed() async {
        let live = makeLive()
        recording = Audio.pause(8)
        live.poll()
        let outcome = await live.finish(capture: recording)
        XCTAssertEqual(outcome.segments, 0)
        XCTAssertTrue(typed.isEmpty)
    }

    func testAfterAFocusChangeTheRestGoesToTheClipboard() async {
        let live = makeLive()
        recording = Audio.speech(10) + Audio.pause(1.5)
        live.poll()
        await live.waitForSegments()
        recording += Audio.speech(5) + Audio.pause(1.5)
        failNext = .focusChanged
        live.poll()
        recording += Audio.speech(6)
        let outcome = await live.finish(capture: recording)
        XCTAssertEqual(typed, ["10s"])
        XCTAssertEqual(outcome.deliveryError as? DeliveryError, .focusChanged)
        // The failed segment and everything after it, once, at the end.
        // Segments start inside the previous pause, so they run long.
        XCTAssertEqual(copied.last, "6s 7s")
    }

    func testAPasswordFieldStopsDelivery() async {
        let live = makeLive()
        recording = Audio.speech(10) + Audio.pause(1.5)
        failNext = .secureField
        live.poll()
        recording += Audio.speech(5)
        let outcome = await live.finish(capture: recording)
        XCTAssertTrue(typed.isEmpty)
        XCTAssertTrue(copied.isEmpty)
        XCTAssertEqual(outcome.deliveryError as? DeliveryError, .secureField)
    }

    func testCancelDeliversNothingMore() async {
        let live = makeLive()
        recording = Audio.speech(10) + Audio.pause(1.5)
        live.cancel()
        live.poll()
        let outcome = await live.finish(capture: recording + Audio.speech(3))
        XCTAssertTrue(typed.isEmpty)
        XCTAssertEqual(outcome.chars, 0)
    }
}
