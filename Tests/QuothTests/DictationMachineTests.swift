import XCTest
@testable import QuothDomain

/// The dictation loop's rules (ADR-007 §3), without audio, a tap or a model.
final class DictationMachineTests: XCTestCase {
    private typealias Effect = DictationMachine.Effect

    private func conditions(
        cardOpen: Bool = false,
        lockOpensCard: Bool = false,
        canInsert: Bool = true,
        liveText: Bool = true,
        routeChanged: Bool = false
    ) -> DictationMachine.LockConditions {
        .init(cardOpen: cardOpen, lockOpensCard: lockOpensCard, canInsert: canInsert, liveText: liveText, routeChanged: routeChanged)
    }

    /// A machine recording push-to-talk.
    private func recording() -> DictationMachine {
        var machine = DictationMachine()
        _ = machine.pressed(captureStarted: true)
        return machine
    }

    // MARK: Press

    func testAPressRecords() {
        var machine = DictationMachine()
        XCTAssertEqual(machine.pressed(captureStarted: true), [.started])
        XCTAssertEqual(machine.state, .recording)
        XCTAssertFalse(machine.isLocked)
    }

    func testAPressWhoseMicrophoneFailsChangesNothingAndAbandonsTheHold() {
        var machine = DictationMachine()
        XCTAssertEqual(machine.pressed(captureStarted: false), [.failed(.captureFailedToStart), .abandonPress])
        XCTAssertEqual(machine.state, .idle)
    }

    func testAFailedPressWhileTranscribingKeepsTranscribing() {
        var machine = recording()
        _ = machine.released()
        _ = machine.captured(.audio(hasSpeech: true))
        XCTAssertEqual(machine.pressed(captureStarted: false), [.failed(.captureFailedToStart), .abandonPress])
        XCTAssertEqual(machine.state, .transcribing)
    }

    // MARK: Release

    func testAReleaseFinishesTheCaptureAndTranscribesSpeech() {
        var machine = recording()
        XCTAssertEqual(machine.released(), [.finishCapture(keepBeforeRouteChange: false)])
        XCTAssertEqual(machine.captured(.audio(hasSpeech: true)), [.transcribing, .transcribe])
        XCTAssertEqual(machine.state, .transcribing)
        XCTAssertEqual(machine.transcribed(scratchesPrevious: false, cardOpen: false), [.deliver(.cursor)])
        XCTAssertEqual(machine.delivered(nil), [.remember, .finished])
        XCTAssertEqual(machine.state, .idle)
    }

    func testSilenceTranscribesNothing() {
        var machine = recording()
        _ = machine.released()
        XCTAssertEqual(machine.captured(.audio(hasSpeech: false)), [.transcribing, .failed(.noSpeech)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testAReleaseWithNothingRecordingDoesNothing() {
        var machine = DictationMachine()
        XCTAssertEqual(machine.released(), [])
    }

    func testALostCaptureDeliversNothing() {
        var machine = recording()
        _ = machine.released()
        XCTAssertEqual(machine.captured(.lost), [.failed(.captureLost)])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: Overlapping dictations

    func testAPressWhileTranscribingRecordsAndTheEarlierDictationStillDelivers() {
        var machine = recording()
        _ = machine.released()
        _ = machine.captured(.audio(hasSpeech: true))
        XCTAssertEqual(machine.pressed(captureStarted: true), [.started])
        XCTAssertEqual(machine.state, .recording)
        XCTAssertEqual(machine.transcribed(scratchesPrevious: false, cardOpen: false), [.deliver(.cursor)])
        XCTAssertEqual(machine.delivered(nil), [.remember, .finished])
        // The new recording carries on.
        XCTAssertEqual(machine.state, .recording)
        _ = machine.released()
        _ = machine.captured(.audio(hasSpeech: true))
        XCTAssertEqual(machine.state, .transcribing)
    }

    func testTwoTranscriptionsInFlightSettleOnlyWhenBothEnd() {
        var machine = recording()
        _ = machine.released()
        _ = machine.captured(.audio(hasSpeech: true))
        _ = machine.pressed(captureStarted: true)
        _ = machine.released()
        _ = machine.captured(.audio(hasSpeech: true))
        _ = machine.delivered(nil)
        XCTAssertEqual(machine.state, .transcribing)
        XCTAssertEqual(machine.transcriptionFailed(), [.failed(.transcriptionFailed)])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: Cancel

    func testACancelStopsWithoutTranscribing() {
        var machine = recording()
        XCTAssertEqual(machine.cancelled(), [.stopCapture, .failed(.cancelled)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testACancelWithNothingRecordingDoesNothing() {
        var machine = DictationMachine()
        XCTAssertEqual(machine.cancelled(), [])
    }

    func testACancelledLockWaitsForItsSegments() {
        var machine = recording()
        _ = machine.locked(conditions())
        XCTAssertEqual(machine.cancelled(), [.stopCapture, .cancelLive, .awaitLive, .failed(.cancelled)])
        XCTAssertEqual(machine.state, .transcribing)
        machine.liveCancelled()
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: Lock

    func testALockTypesLiveAtTheCursor() {
        var machine = recording()
        XCTAssertEqual(machine.locked(conditions()), [.startLive(.cursor), .locked])
        XCTAssertTrue(machine.isLocked)
        XCTAssertEqual(machine.released(), [.finishCapture(keepBeforeRouteChange: true)])
        XCTAssertEqual(machine.captured(.audio(hasSpeech: true)), [.transcribing, .finishLive])
        XCTAssertEqual(machine.liveFinished(.init(chars: 12)), [.remember, .finished])
        XCTAssertEqual(machine.state, .idle)
    }

    func testALockWithoutLiveTextTranscribesAtTheEnd() {
        var machine = recording()
        XCTAssertEqual(machine.locked(conditions(liveText: false)), [.locked])
        _ = machine.released()
        XCTAssertEqual(machine.captured(.audio(hasSpeech: true)), [.transcribing, .transcribe])
    }

    func testALockGoesToTheOpenCard() {
        var machine = recording()
        XCTAssertEqual(machine.locked(conditions(cardOpen: true)), [.openCard, .startLive(.card), .locked])
    }

    func testALockGoesToTheCardWhenSettingsSaySo() {
        var machine = recording()
        XCTAssertEqual(machine.locked(conditions(lockOpensCard: true)), [.openCard, .startLive(.card), .locked])
    }

    func testALockGoesToTheCardWhenTheBuildCantPaste() {
        var machine = recording()
        XCTAssertEqual(machine.locked(conditions(canInsert: false)), [.openCard, .startLive(.card), .locked])
    }

    func testTheCardTakesALockWithoutLiveTextAtTheEnd() {
        var machine = recording()
        XCTAssertEqual(machine.locked(conditions(canInsert: false, liveText: false)), [.openCard, .locked])
    }

    func testAMicrophoneChangeDuringTheDoubleTapEndsTheLockAtOnce() {
        var machine = recording()
        XCTAssertEqual(machine.locked(conditions(routeChanged: true)), [.endLock(reason: "the microphone changed"), .startLive(.cursor), .locked])
    }

    func testALockWithNothingRecordingDoesNothing() {
        var machine = DictationMachine()
        XCTAssertEqual(machine.locked(conditions()), [])
        XCTAssertFalse(machine.isLocked)
    }

    // MARK: Microphone changes

    func testAMicrophoneChangeEndsALock() {
        var machine = recording()
        _ = machine.locked(conditions())
        XCTAssertEqual(machine.routeChanged(), [.endLock(reason: "the microphone changed")])
    }

    func testAMicrophoneChangeLeavesPushToTalkToItsRelease() {
        let machine = recording()
        XCTAssertEqual(machine.routeChanged(), [])
    }

    func testALostLockCancelsItsLiveTextWithoutWaiting() {
        var machine = recording()
        _ = machine.locked(conditions())
        _ = machine.released()
        XCTAssertEqual(machine.captured(.lost), [.cancelLive, .failed(.captureLost)])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: Delivery

    func testWhileTheCardIsOpenEveryDictationGoesIntoIt() {
        let machine = DictationMachine()
        XCTAssertEqual(machine.transcribed(scratchesPrevious: false, cardOpen: true), [.deliver(.card)])
    }

    func testScratchThatRemovesTheLastDeliveryFirst() {
        let machine = DictationMachine()
        XCTAssertEqual(machine.transcribed(scratchesPrevious: true, cardOpen: false), [.scratchLast(.cursor), .deliver(.cursor)])
        XCTAssertEqual(machine.transcribed(scratchesPrevious: true, cardOpen: true), [.scratchLast(.card), .deliver(.card)])
    }

    func testAPasswordFieldIsNeverRemembered() {
        var machine = recording()
        _ = machine.released()
        _ = machine.captured(.audio(hasSpeech: true))
        XCTAssertEqual(machine.delivered(.secureField), [.failed(.notDelivered(.secureField))])
    }

    func testCopiedTextIsRemembered() {
        for error in [DeliveryError.focusChanged, .copied] {
            var machine = recording()
            _ = machine.released()
            _ = machine.captured(.audio(hasSpeech: true))
            XCTAssertEqual(machine.delivered(error), [.remember, .failed(.notDelivered(error))])
        }
    }

    // MARK: The end of live text

    private func lockedAndReleased() -> DictationMachine {
        var machine = recording()
        _ = machine.locked(conditions())
        _ = machine.released()
        _ = machine.captured(.audio(hasSpeech: true))
        return machine
    }

    func testLiveTextStoppedByAPasswordFieldIsNeverRemembered() {
        var machine = lockedAndReleased()
        XCTAssertEqual(machine.liveFinished(.init(chars: 5, deliveryError: .secureField)), [.failed(.notDelivered(.secureField))])
    }

    func testLiveTextAfterAFocusChangeIsRememberedAndReported() {
        var machine = lockedAndReleased()
        XCTAssertEqual(machine.liveFinished(.init(chars: 5, deliveryError: .focusChanged)), [.remember, .failed(.notDelivered(.focusChanged))])
    }

    func testALockWithNoTextReportsWhy() {
        var silent = lockedAndReleased()
        XCTAssertEqual(silent.liveFinished(.init(chars: 0)), [.remember, .failed(.noSpeech)])
        var broken = lockedAndReleased()
        XCTAssertEqual(broken.liveFinished(.init(chars: 0, transcriptionFailed: true)), [.remember, .failed(.transcriptionFailed)])
    }

    func testALockWithSomeTextFinishesEvenIfASegmentFailed() {
        var machine = lockedAndReleased()
        XCTAssertEqual(machine.liveFinished(.init(chars: 9, transcriptionFailed: true)), [.remember, .finished])
    }
}
