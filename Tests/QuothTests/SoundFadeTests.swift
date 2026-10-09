import XCTest
@testable import QuothDomain
@testable import QuothPlatform

/// Fading other sound while dictating: the steps of a fade, when the volume
/// comes back, the setting, and that `FadingMicrophone` fades exactly while
/// the microphone records.
final class VolumeFadeTests: XCTestCase {
    func testAFadeEndsExactlyAtItsTarget() {
        XCTAssertEqual(VolumeFade.levels(from: 0.62, to: 0, over: 0.25).last, 0)
        XCTAssertEqual(VolumeFade.levels(from: 0, to: 0.62, over: 0.5).last, 0.62)
    }

    func testAFadeTakesAStepEachInterval() {
        XCTAssertEqual(VolumeFade.levels(from: 1, to: 0, over: 0.25, step: 0.02).count, 13)
        XCTAssertEqual(VolumeFade.levels(from: 1, to: 0, over: 0.5, step: 0.02).count, 25)
    }

    func testAFadeNeverCutsStraightToItsTarget() {
        // The point of the setting: no single step from sound to silence.
        let down = VolumeFade.levels(from: 0.8, to: 0, over: VolumeFade.outDuration)
        let up = VolumeFade.levels(from: 0, to: 0.8, over: VolumeFade.inDuration)
        XCTAssertGreaterThan(down.count, 5)
        XCTAssertGreaterThan(up.count, 5)
        for levels in [down, up] {
            let jumps = zip([levels[0]] + levels, levels).map { abs($1 - $0) }
            XCTAssertLessThan(jumps.max()!, 0.8 / 4)
        }
    }

    func testAFadeMovesOneWayAndEasesInAndOut() {
        let down = VolumeFade.levels(from: 1, to: 0, over: 0.5)
        XCTAssertEqual(down, down.sorted(by: >))
        let jumps = zip([1] + down, down).map { $0 - $1 }
        // Gentle at both ends, quickest in the middle.
        XCTAssertLessThan(jumps.first!, jumps[jumps.count / 2])
        XCTAssertLessThan(jumps.last!, jumps[jumps.count / 2])
    }

    func testAZeroLengthFadeIsOneStep() {
        XCTAssertEqual(VolumeFade.levels(from: 0.5, to: 0, over: 0), [0])
    }

    func testABluetoothHeadsetRecordingIsNotFaded() {
        XCTAssertFalse(VolumeFade.canFade(outputIsBluetooth: true, inputIsBluetooth: true))
        // AirPods listening while the Mac's microphone records.
        XCTAssertTrue(VolumeFade.canFade(outputIsBluetooth: true, inputIsBluetooth: false))
        XCTAssertTrue(VolumeFade.canFade(outputIsBluetooth: false, inputIsBluetooth: true))
        XCTAssertTrue(VolumeFade.canFade(outputIsBluetooth: false, inputIsBluetooth: false))
    }

    func testTheVolumeComesBackUnlessSomeoneTurnedItUp() {
        XCTAssertTrue(VolumeFade.shouldRestore(current: 0, lastSet: 0))
        // Devices round to their own steps.
        XCTAssertTrue(VolumeFade.shouldRestore(current: 0.0125, lastSet: 0))
        XCTAssertFalse(VolumeFade.shouldRestore(current: 0.4, lastSet: 0))
        // Partway down, still Quoth's.
        XCTAssertTrue(VolumeFade.shouldRestore(current: 0.3, lastSet: 0.3))
    }

    func testTheSettingDefaultsOffAndDecodes() throws {
        func decode(_ json: String) throws -> Settings {
            try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        }
        XCTAssertFalse(try decode("{}").sound.fadeWhileDictating)
        XCTAssertTrue(try decode(#"{"sound": {"fadeWhileDictating": true}}"#).sound.fadeWhileDictating)
        var on = Settings()
        on.sound.fadeWhileDictating = true
        XCTAssertFalse(on.reset().sound.fadeWhileDictating)
    }
}

final class FadingMicrophoneTests: XCTestCase {
    private struct Failure: Error {}

    private final class FakeMicrophone: Microphone {
        var startError: Error?
        var finishError: Error?
        private(set) var calls: [String] = []
        var hasRouteChanged = false
        let lastFirstSampleDelay: TimeInterval? = nil

        func start() throws {
            calls.append("start")
            if let startError { throw startError }
        }
        func finish(keepBeforeRouteChange: Bool) throws -> [Float] {
            calls.append("finish")
            if let finishError { throw finishError }
            return [0.1]
        }
        func stop() { calls.append("stop") }
        func samples(from offset: Int) -> [Float] { [] }
    }

    private final class FakeFader: SoundFading {
        private(set) var calls: [String] = []
        func fadeOut() { calls.append("out") }
        func fadeIn() { calls.append("in") }
    }

    private let microphone = FakeMicrophone()
    private let fader = FakeFader()

    private func fading(enabled: Bool = true) -> FadingMicrophone {
        let fading = FadingMicrophone(microphone, fader: fader)
        fading.isEnabled = enabled
        return fading
    }

    func testOffItNeverTouchesTheSound() throws {
        let mic = fading(enabled: false)
        try mic.start()
        _ = try mic.finish(keepBeforeRouteChange: false)
        XCTAssertEqual(fader.calls, [])
    }

    func testTheSoundFadesBeforeTheMicrophoneOpensAndComesBackAfterAFinish() throws {
        let mic = fading()
        try mic.start()
        XCTAssertEqual(fader.calls, ["out"])
        XCTAssertEqual(try mic.finish(keepBeforeRouteChange: false), [0.1])
        XCTAssertEqual(fader.calls, ["out", "in"])
    }

    func testTheSoundComesBackAfterADiscardedRecording() throws {
        let mic = fading()
        try mic.start()
        mic.stop()
        XCTAssertEqual(fader.calls, ["out", "in"])
    }

    func testTheSoundComesBackWhenTheMicrophoneFailsToStart() {
        microphone.startError = Failure()
        let mic = fading()
        XCTAssertThrowsError(try mic.start())
        XCTAssertEqual(fader.calls, ["out", "in"])
    }

    func testTheSoundComesBackWhenAFinishThrows() throws {
        microphone.finishError = Failure()
        let mic = fading()
        try mic.start()
        XCTAssertThrowsError(try mic.finish(keepBeforeRouteChange: false))
        XCTAssertEqual(fader.calls, ["out", "in"])
    }

    func testAPressWhileRecordingDoesNotFadeTwice() throws {
        // Every press tries the microphone, even mid-recording.
        let mic = fading()
        try mic.start()
        try mic.start()
        _ = try mic.finish(keepBeforeRouteChange: false)
        XCTAssertEqual(fader.calls, ["out", "in"])
    }

    func testTurningItOffMidRecordingStillBringsTheSoundBack() throws {
        let mic = fading()
        try mic.start()
        mic.isEnabled = false
        mic.stop()
        XCTAssertEqual(fader.calls, ["out", "in"])
    }

    func testAFinishWithoutARecordingLeavesTheSoundAlone() throws {
        let mic = fading()
        _ = try mic.finish(keepBeforeRouteChange: false)
        mic.stop()
        XCTAssertEqual(fader.calls, [])
    }
}
