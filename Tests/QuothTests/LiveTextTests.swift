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
        XCTAssertNil(PauseSplitter.cut(Audio.speech(2) + Audio.pause(1)))
    }

    func testCutsInTheFirstPauseAfterTheMinimum() throws {
        let audio = Audio.speech(2) + Audio.pause(1) + Audio.speech(3) + Audio.pause(1) + Audio.speech(2)
        let cut = try XCTUnwrap(PauseSplitter.cut(audio))
        XCTAssertTrue(cut.hasSpeech)
        // Inside the second pause, which starts at 6 s.
        XCTAssertGreaterThan(cut.end, 6 * 16_000)
        XCTAssertLessThan(cut.end, 7 * 16_000)
    }

    func testWaitsUntilThePauseIsLongEnough() {
        XCTAssertNil(PauseSplitter.cut(Audio.speech(5) + Audio.pause(0.3)))
        XCTAssertNotNil(PauseSplitter.cut(Audio.speech(5) + Audio.pause(0.7)))
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

    func testHasSpeech() {
        XCTAssertTrue(PauseSplitter.hasSpeech(Audio.pause(1) + Audio.speech(0.5)))
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
private struct SecondsTranscriber: Transcriber {
    var modelID = "fake"

    func transcribe(_ audio: [Float], context: TranscriptionContext) async throws -> Transcript {
        let seconds = audio.count / 16_000
        try await Task.sleep(nanoseconds: UInt64(max(0, 30 - seconds)) * 1_000_000)
        return Transcript(text: "\(seconds)s")
    }
}

@MainActor
final class LiveTranscriptionTests: XCTestCase {
    private var recording: [Float] = []
    private var typed: [String] = []
    private var copied: [String] = []
    private var failNext: DeliveryError?

    private func makeLive() -> LiveTranscription {
        LiveTranscription(
            samples: { [unowned self] offset in offset < recording.count ? Array(recording[offset...]) : [] },
            transcriber: SecondsTranscriber(),
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
            copy: { [unowned self] in copied.append($0) }
        )
    }

    func testSegmentsAreTypedInOrderAndTheTailAtTheEnd() async {
        let live = makeLive()
        recording = Audio.speech(10) + Audio.pause(1)
        live.poll()
        recording += Audio.speech(5) + Audio.pause(1)
        live.poll()
        recording += Audio.speech(2)
        let outcome = await live.finish(capture: recording)
        XCTAssertEqual(typed.count, 3)
        XCTAssertEqual(typed.first, "10s")
        XCTAssertEqual(outcome.segments, 3)
        XCTAssertNil(outcome.deliveryError)
        XCTAssertTrue(copied.isEmpty)
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
        recording = Audio.speech(10) + Audio.pause(1)
        live.poll()
        await live.waitForSegments()
        recording += Audio.speech(5) + Audio.pause(1)
        failNext = .focusChanged
        live.poll()
        recording += Audio.speech(6)
        let outcome = await live.finish(capture: recording)
        XCTAssertEqual(typed, ["10s"])
        XCTAssertEqual(outcome.deliveryError as? DeliveryError, .focusChanged)
        // The failed segment and everything after it, once, at the end.
        // Segments start inside the previous pause, so they run long.
        XCTAssertEqual(copied.last, "6s 6s")
    }

    func testAPasswordFieldStopsDelivery() async {
        let live = makeLive()
        recording = Audio.speech(10) + Audio.pause(1)
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
        recording = Audio.speech(10) + Audio.pause(1)
        live.cancel()
        live.poll()
        let outcome = await live.finish(capture: recording + Audio.speech(3))
        XCTAssertTrue(typed.isEmpty)
        XCTAssertEqual(outcome.chars, 0)
    }
}
