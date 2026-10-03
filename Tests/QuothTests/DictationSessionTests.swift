import XCTest
@testable import QuothCore
@testable import QuothDomain
@testable import QuothPlatform

/// `DictationSession` end to end, with fakes for the microphone, the
/// cursor, focus, the transcriber and the Quote Card: what reaches the
/// cursor, the card, observers and Copy Last Dictation.
@MainActor
final class DictationSessionTests: XCTestCase {
    // MARK: Fakes

    private final class FakeMicrophone: Microphone {
        var startError: Error?
        var finishError: Error?
        var recording: [Float] = []
        var hasRouteChanged = false
        private(set) var stopped = 0
        private(set) var keptBeforeRouteChange: Bool?
        let lastFirstSampleDelay: TimeInterval? = 0.05

        func start() throws { if let startError { throw startError } }
        func finish(keepBeforeRouteChange: Bool) throws -> [Float] {
            keptBeforeRouteChange = keepBeforeRouteChange
            if let finishError { throw finishError }
            return recording
        }
        func stop() { stopped += 1 }
        func samples(from offset: Int) -> [Float] { [] }
    }

    private final class FakeSink: TextSink {
        var canInsert = true
        var refuse: DeliveryError?
        private(set) var typed: [String] = []
        private(set) var scratched = 0
        private(set) var copied: [String] = []

        func deliver(_ text: String, focusAtStart: FocusSnapshot?) throws {
            if let refuse { throw refuse }
            if !text.isEmpty { typed.append(text) }
        }
        func scratchLast() -> Bool { scratched += 1; return true }
        func copyToClipboard(_ text: String) { copied.append(text) }
    }

    private struct FakeFocus: FocusProbe {
        func current() -> FocusSnapshot { FocusSnapshot(pid: 1, element: nil, isSecure: false) }
    }

    private final class FakeTranscriber: Transcriber, @unchecked Sendable {
        let modelID = "fake"
        var text = "Hello there."
        var error: Error?
        private(set) var calls = 0

        func transcribe(_ audio: [Float], context: TranscriptionContext) async throws -> Transcript {
            calls += 1
            if let error { throw error }
            return Transcript(text: text)
        }
    }

    private final class FakeCard: DictationTarget {
        var isOpen = false
        private(set) var appended: [String] = []
        private(set) var scratched = 0
        func open() { isOpen = true }
        func append(_ text: String) { appended.append(text) }
        func scratchLast() -> Bool { scratched += 1; return true }
    }

    private final class Events: DictationObserver {
        private(set) var log: [String] = []
        private(set) var errors: [Error] = []
        func dictationStarted() { log.append("started") }
        func dictationLocked() { log.append("locked") }
        func dictationTranscribing() { log.append("transcribing") }
        func dictationFinished(_ result: DictationResult) { log.append("finished") }
        func dictationFailed(_ error: Error) { log.append("failed"); errors.append(error) }
    }

    private struct Boom: Error {}

    // MARK: Setup

    private let microphone = FakeMicrophone()
    private let sink = FakeSink()
    private let transcriber = FakeTranscriber()
    private let card = FakeCard()
    private let events = Events()
    private var remembered: [String] = []
    private var abandoned = 0
    private var endedLocks: [String] = []

    private func makeSession(processors: [TranscriptProcessor] = []) -> DictationSession {
        let session = DictationSession(
            capture: microphone,
            transcriber: transcriber,
            processors: processors,
            observers: [events],
            delivery: sink,
            focus: FakeFocus()
        )
        session.card = card
        session.onTranscript = { [unowned self] in remembered.append($0) }
        session.onAbandonPress = { [unowned self] in abandoned += 1 }
        session.onEndLock = { [unowned self] in endedLocks.append($0) }
        return session
    }

    /// One second of a loud tone: speech, as far as `PauseSplitter` can tell.
    private let speech: [Float] = (0..<16_000).map { Float(sin(Double($0) * 0.1)) * 0.1 }
    private let silence = [Float](repeating: 0, count: 16_000)

    /// Waits for the session's transcriptions to end.
    private func settle(_ session: DictationSession, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while session.state != .idle, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Lets a `DispatchQueue.main.async` block run.
    private func nextTurn() async {
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    }

    // MARK: Push-to-talk

    func testADictationIsTypedAndRemembered() async {
        let session = makeSession()
        microphone.recording = speech
        session.handle(.pressed)
        XCTAssertEqual(session.state, .recording)
        session.handle(.released)
        await settle(session)
        XCTAssertEqual(sink.typed, ["Hello there."])
        XCTAssertEqual(remembered, ["Hello there."])
        XCTAssertEqual(events.log, ["started", "transcribing", "finished"])
        XCTAssertEqual(microphone.keptBeforeRouteChange, false)
    }

    func testAMicrophoneThatWontStartAbandonsThePress() {
        let session = makeSession()
        microphone.startError = Boom()
        session.handle(.pressed)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(abandoned, 1)
        XCTAssertEqual(events.log, ["failed"])
        XCTAssertTrue(events.errors.first is Boom)
    }

    func testSilenceIsNotTranscribed() async {
        let session = makeSession()
        microphone.recording = silence
        session.handle(.pressed)
        session.handle(.released)
        await settle(session)
        XCTAssertEqual(transcriber.calls, 0)
        XCTAssertEqual(events.log, ["started", "transcribing", "failed"])
        XCTAssertEqual(events.errors.first as? DictationError, .noAudio)
    }

    func testALostCaptureReportsWhy() async {
        let session = makeSession()
        microphone.finishError = Boom()
        session.handle(.pressed)
        session.handle(.released)
        await settle(session)
        XCTAssertEqual(transcriber.calls, 0)
        XCTAssertEqual(events.log, ["started", "failed"])
        XCTAssertTrue(events.errors.first is Boom)
    }

    func testAFailedTranscriptionReportsWhy() async {
        let session = makeSession()
        microphone.recording = speech
        transcriber.error = Boom()
        session.handle(.pressed)
        session.handle(.released)
        await settle(session)
        XCTAssertEqual(sink.typed, [])
        XCTAssertEqual(remembered, [])
        XCTAssertTrue(events.errors.first is Boom)
    }

    func testACancelledRecordingStopsTheMicrophoneAndTranscribesNothing() async {
        let session = makeSession()
        session.handle(.pressed)
        session.handle(.cancelled)
        await settle(session)
        XCTAssertEqual(microphone.stopped, 1)
        XCTAssertEqual(transcriber.calls, 0)
        XCTAssertEqual(events.errors.first as? DictationError, .cancelled)
    }

    // MARK: Where the text goes

    func testWhileTheCardIsOpenTheTranscriptGoesIntoIt() async {
        let session = makeSession()
        card.isOpen = true
        microphone.recording = speech
        session.handle(.pressed)
        session.handle(.released)
        await settle(session)
        XCTAssertEqual(card.appended, ["Hello there."])
        XCTAssertEqual(sink.typed, [])
        XCTAssertEqual(remembered, ["Hello there."])
    }

    func testAPasswordFieldIsNeverRemembered() async {
        let session = makeSession()
        sink.refuse = .secureField
        microphone.recording = speech
        session.handle(.pressed)
        session.handle(.released)
        await settle(session)
        XCTAssertEqual(remembered, [])
        XCTAssertEqual(events.errors.first as? DeliveryError, .secureField)
    }

    func testCopiedTextIsRememberedAndReported() async {
        let session = makeSession()
        sink.refuse = .focusChanged
        microphone.recording = speech
        session.handle(.pressed)
        session.handle(.released)
        await settle(session)
        XCTAssertEqual(remembered, ["Hello there."])
        XCTAssertEqual(events.errors.first as? DeliveryError, .focusChanged)
    }

    func testScratchThatRemovesThePreviousInsertion() async {
        let session = makeSession(processors: [VoiceCommands()])
        transcriber.text = "Scratch that."
        microphone.recording = speech
        session.handle(.pressed)
        session.handle(.released)
        await settle(session)
        XCTAssertEqual(sink.scratched, 1)
        XCTAssertEqual(sink.typed, [])
    }

    // MARK: Locks

    func testALockInABuildThatCantPasteGoesToTheCard() async {
        let session = makeSession()
        sink.canInsert = false
        session.handle(.pressed)
        session.handle(.locked)
        XCTAssertTrue(card.isOpen)
        XCTAssertEqual(events.log, ["started", "locked"])
        session.handle(.cancelled)
        await settle(session)
    }

    func testAMicrophoneChangeEndsALockAndKeepsWhatCameBefore() async {
        let session = makeSession()
        session.liveText = false
        session.handle(.pressed)
        session.handle(.locked)
        session.routeChanged()
        await nextTurn()
        XCTAssertEqual(endedLocks, ["the microphone changed"])
        microphone.recording = speech
        session.handle(.released)
        await settle(session)
        XCTAssertEqual(microphone.keptBeforeRouteChange, true)
        XCTAssertEqual(sink.typed, ["Hello there."])
    }

    func testAMicrophoneChangeLeavesPushToTalkToItsRelease() async {
        let session = makeSession()
        session.handle(.pressed)
        session.routeChanged()
        await nextTurn()
        XCTAssertEqual(endedLocks, [])
        session.handle(.cancelled)
    }
}
