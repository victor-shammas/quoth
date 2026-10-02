import CoreGraphics
import XCTest
@testable import QuothCore

final class GestureTests: XCTestCase {
    private let down = Gesture.Input.hotkeyDown(othersHeld: false)

    func testHoldStartsAndTranscribes() {
        var g = Gesture()
        XCTAssertEqual(g.handle(down, at: 10), .start)
        XCTAssertTrue(g.isHeld)
        XCTAssertEqual(g.handle(.hotkeyUp, at: 11.2), .transcribe)
        XCTAssertFalse(g.isHeld)
    }

    func testShortHoldIsDiscarded() {
        var g = Gesture()
        XCTAssertEqual(g.handle(down, at: 10), .start)
        XCTAssertEqual(g.handle(.hotkeyUp, at: 10.29), .cancel)
        XCTAssertFalse(g.isHeld)
    }

    func testHoldOfExactlyTheMinimumTranscribes() {
        var g = Gesture()
        _ = g.handle(down, at: 0)
        XCTAssertEqual(g.handle(.hotkeyUp, at: Gesture.minimumHold), .transcribe)
    }

    func testAnotherModifierCancelsAndTheRestOfTheHoldIsIgnored() {
        var g = Gesture()
        XCTAssertEqual(g.handle(down, at: 0), .start)
        XCTAssertEqual(g.handle(.otherModifier, at: 1), .cancel)
        XCTAssertNil(g.handle(.otherModifier, at: 2))
        XCTAssertTrue(g.isHeld)
        XCTAssertNil(g.handle(.hotkeyUp, at: 5))
        XCTAssertFalse(g.isHeld)
        // The next hold records again.
        XCTAssertEqual(g.handle(down, at: 6), .start)
    }

    func testPressWithAnotherModifierHeldDoesNotRecord() {
        var g = Gesture()
        XCTAssertNil(g.handle(.hotkeyDown(othersHeld: true), at: 0))
        XCTAssertTrue(g.isHeld)
        XCTAssertNil(g.handle(.hotkeyUp, at: 3))
        XCTAssertFalse(g.isHeld)
    }

    func testStrayEdgesDoNothing() {
        var g = Gesture()
        XCTAssertNil(g.handle(.hotkeyUp, at: 0))
        XCTAssertNil(g.handle(.otherModifier, at: 0))
        XCTAssertEqual(g.handle(down, at: 1), .start)
        XCTAssertNil(g.handle(down, at: 2))
        XCTAssertEqual(g.handle(.hotkeyUp, at: 3), .transcribe)
    }

    func testResetCancelsARecordingOnly() {
        var g = Gesture()
        XCTAssertNil(g.reset())
        _ = g.handle(down, at: 0)
        XCTAssertEqual(g.reset(), .cancel)
        XCTAssertFalse(g.isHeld)

        _ = g.handle(.hotkeyDown(othersHeld: true), at: 0)
        XCTAssertNil(g.reset())
        XCTAssertFalse(g.isHeld)
    }
}

final class GestureLockTests: XCTestCase {
    private let down = Gesture.Input.hotkeyDown(othersHeld: false)

    /// Tap at 0…0.1, second press at 0.3, released at 0.4: locked.
    private func locked() -> Gesture {
        var g = Gesture()
        XCTAssertEqual(g.handle(down, at: 0), .start)
        XCTAssertEqual(g.handle(.hotkeyUp, at: 0.1), .cancel)
        XCTAssertEqual(g.handle(down, at: 0.3), .start)
        XCTAssertEqual(g.handle(.hotkeyUp, at: 0.4), .lock)
        XCTAssertTrue(g.isLocked)
        XCTAssertFalse(g.isHeld)
        return g
    }

    func testDoubleTapLocksAndTheNextTapTranscribes() {
        var g = locked()
        XCTAssertEqual(g.handle(down, at: 60), .transcribe)
        XCTAssertFalse(g.isLocked)
        // The stopping press records nothing; its release is ignored.
        XCTAssertNil(g.handle(.hotkeyUp, at: 60.1))
        XCTAssertFalse(g.isHeld)
        XCTAssertEqual(g.handle(down, at: 70), .start)
    }

    func testAShortcutOnTheHotkeyEndsALockWithoutLosingIt() {
        // Shift+fn+→ mid-dictation: transcribe, never discard minutes of audio.
        var g = locked()
        XCTAssertEqual(g.handle(.hotkeyDown(othersHeld: true), at: 60), .transcribe)
        XCTAssertNil(g.handle(.hotkeyUp, at: 60.1))
        XCTAssertFalse(g.isLocked)
    }

    func testATripleTapIsDiscarded() {
        var g = locked()
        XCTAssertEqual(g.handle(down, at: 0.3 + Gesture.minimumLock - 0.1), .cancel)
        XCTAssertFalse(g.isLocked)
    }

    func testAPressThatStartedNoRecordingCannotLock() {
        var g = Gesture()
        _ = g.handle(down, at: 0)
        _ = g.handle(.hotkeyUp, at: 0.1)
        XCTAssertEqual(g.handle(down, at: 0.3), .start)
        g.abandonPress()
        XCTAssertNil(g.handle(.hotkeyUp, at: 0.4))
        XCTAssertFalse(g.isLocked)
        XCTAssertFalse(g.isHeld)
    }

    func testOtherModifiersWhileLockedDoNothing() {
        // The key is up while locked, so typing ⌘C mid-dictation is not a chord.
        var g = locked()
        XCTAssertNil(g.handle(.otherModifier, at: 10))
        XCTAssertTrue(g.isLocked)
    }

    func testTapThenHoldIsPushToTalk() {
        var g = Gesture()
        _ = g.handle(down, at: 0)
        _ = g.handle(.hotkeyUp, at: 0.1)
        XCTAssertEqual(g.handle(down, at: 0.3), .start)
        XCTAssertEqual(g.handle(.hotkeyUp, at: 2), .transcribe)
        XCTAssertFalse(g.isLocked)
    }

    func testSlowSecondTapIsAnotherDiscardedTap() {
        var g = Gesture()
        _ = g.handle(down, at: 0)
        _ = g.handle(.hotkeyUp, at: 0.1)
        XCTAssertEqual(g.handle(down, at: 0.1 + Gesture.doubleTapWindow + 0.01), .start)
        XCTAssertEqual(g.handle(.hotkeyUp, at: 0.6), .cancel)
        XCTAssertFalse(g.isLocked)
    }

    func testAHoldThenATapDoesNotLock() {
        // Only a discarded tap arms the lock, not the end of a dictation.
        var g = Gesture()
        _ = g.handle(down, at: 0)
        XCTAssertEqual(g.handle(.hotkeyUp, at: 2), .transcribe)
        _ = g.handle(down, at: 2.1)
        XCTAssertEqual(g.handle(.hotkeyUp, at: 2.2), .cancel)
        XCTAssertFalse(g.isLocked)
    }

    func testAChordOnTheSecondPressCancels() {
        var g = Gesture()
        _ = g.handle(down, at: 0)
        _ = g.handle(.hotkeyUp, at: 0.1)
        _ = g.handle(down, at: 0.3)
        XCTAssertEqual(g.handle(.otherModifier, at: 0.35), .cancel)
        XCTAssertNil(g.handle(.hotkeyUp, at: 0.4))
        XCTAssertFalse(g.isLocked)
    }

    func testLockDisabledIsPushToTalkOnly() {
        var g = Gesture(lockEnabled: false)
        _ = g.handle(down, at: 0)
        _ = g.handle(.hotkeyUp, at: 0.1)
        _ = g.handle(down, at: 0.3)
        XCTAssertEqual(g.handle(.hotkeyUp, at: 0.4), .cancel)
        XCTAssertFalse(g.isLocked)
    }

    func testExpireAndResetEndALock() {
        var g = locked()
        XCTAssertEqual(g.expireLock(), .transcribe)
        XCTAssertNil(g.expireLock())
        XCTAssertFalse(g.isLocked)

        // A key switch in Settings transcribes a lock rather than losing it.
        g = locked()
        XCTAssertEqual(g.reset(), .transcribe)
        XCTAssertFalse(g.isLocked)
    }
}

final class HotkeyMatchTests: XCTestCase {
    private func input(_ keycode: Int64, _ flags: CGEventFlags, _ key: HotkeyKey, held: Bool) -> Gesture.Input? {
        HotkeyMonitor.input(keycode: keycode, flags: flags, key: key, held: held)
    }

    /// Device-dependent low bits, which vary by keyboard and must not matter.
    private let rightOptionDeviceBit = CGEventFlags(rawValue: 0x40)
    private let leftOptionDeviceBit = CGEventFlags(rawValue: 0x20)

    func testKeycodesAndFlags() {
        XCTAssertEqual(HotkeyKey.allCases.map(\.keycode), [63, 58, 61, 55, 54, 59, 62, 56, 60])
        XCTAssertEqual(HotkeyKey.fn.flag, .maskSecondaryFn)
        XCTAssertEqual(HotkeyKey.rightOption.flag, .maskAlternate)
        XCTAssertEqual(HotkeyKey.leftCommand.flag, .maskCommand)
        XCTAssertEqual(HotkeyKey.rightControl.flag, .maskControl)
        XCTAssertEqual(HotkeyKey.leftShift.flag, .maskShift)
    }

    func testRightOptionMatchesItsOwnSideOnly() {
        let key = HotkeyKey.rightOption
        XCTAssertEqual(input(61, [.maskAlternate, rightOptionDeviceBit], key, held: false), .hotkeyDown(othersHeld: false))
        // Left option sets the same flag; it is not the hotkey.
        XCTAssertNil(input(58, [.maskAlternate, leftOptionDeviceBit], key, held: false))
        // A keyboard that sets no device bits still matches by keycode.
        XCTAssertEqual(input(61, .maskAlternate, key, held: false), .hotkeyDown(othersHeld: false))
    }

    func testReleaseByKeycodeWithFlagClear() {
        XCTAssertEqual(input(61, [], .rightOption, held: true), .hotkeyUp)
    }

    func testReleaseWhileTheOtherSideHoldsTheSharedFlag() {
        XCTAssertEqual(input(54, .maskCommand, .rightCommand, held: true), .hotkeyUp)
    }

    func testFlagClearOnAnyEventWhileHeldIsARelease() {
        // A missed release: the next modifier event shows the flag gone.
        XCTAssertEqual(input(56, .maskShift, .rightCommand, held: true), .hotkeyUp)
    }

    func testOtherModifierWhileHeldIsAChord() {
        XCTAssertEqual(input(55, .maskCommand, .rightCommand, held: true), .otherModifier)
        XCTAssertEqual(input(56, [.maskCommand, .maskShift], .rightCommand, held: true), .otherModifier)
        XCTAssertEqual(input(58, [.maskSecondaryFn, .maskAlternate], .fn, held: true), .otherModifier)
    }

    func testCapsLockAndUnknownKeycodesAreNotChords() {
        XCTAssertNil(input(57, [.maskCommand, .maskAlphaShift], .rightCommand, held: true))
        XCTAssertNil(input(179, .maskSecondaryFn, .fn, held: true))
    }

    func testPressWithAnotherModifierDownIsAChord() {
        XCTAssertEqual(input(61, [.maskAlternate, .maskCommand], .rightOption, held: false), .hotkeyDown(othersHeld: true))
        XCTAssertEqual(input(63, [.maskSecondaryFn, .maskShift], .fn, held: false), .hotkeyDown(othersHeld: true))
    }

    func testFnMatchesByFlagAsBefore() {
        XCTAssertEqual(input(63, .maskSecondaryFn, .fn, held: false), .hotkeyDown(othersHeld: false))
        // Any event with the fn flag set is a press, whatever its keycode.
        XCTAssertEqual(input(179, .maskSecondaryFn, .fn, held: false), .hotkeyDown(othersHeld: false))
        XCTAssertNil(input(63, .maskSecondaryFn, .fn, held: true))
        XCTAssertEqual(input(63, [], .fn, held: true), .hotkeyUp)
        XCTAssertNil(input(63, [], .fn, held: false))
    }

    func testOtherKeysDoNothingWhenIdle() {
        XCTAssertNil(input(55, .maskCommand, .rightCommand, held: false))
        XCTAssertNil(input(54, [], .rightCommand, held: false))
    }
}
