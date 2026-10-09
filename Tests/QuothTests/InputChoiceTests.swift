import XCTest
@testable import QuothDomain

/// Which input a press records: the Mac's microphone in place of Bluetooth
/// headphones only while they play (`InputChoice`), and the setting.
final class InputChoiceTests: XCTestCase {
    private let headphones: UInt32 = 7
    private let mac: UInt32 = 42

    private func choose(
        defaultInput: UInt32? = 7,
        defaultIsBluetooth: Bool = true,
        playing: Bool = true,
        macMicrophone: UInt32? = 42,
        enabled: Bool = true,
        lidClosed: Bool = false
    ) -> ChosenInput? {
        InputChoice.choose(
            defaultInput: defaultInput,
            defaultIsBluetooth: defaultIsBluetooth,
            bluetoothPlaying: playing,
            macMicrophone: macMicrophone,
            enabled: enabled,
            lidClosed: lidClosed
        )
    }

    func testPlayingHeadphonesGiveWayToTheMacMicrophone() {
        XCTAssertEqual(choose(), ChosenInput(id: mac, inPlaceOfHeadset: true))
    }

    func testWithNothingPlayingTheHeadphonesAreRecorded() {
        // Dictating away from the Mac still works.
        XCTAssertEqual(choose(playing: false), ChosenInput(id: headphones))
    }

    func testWithTheSettingOffTheHeadphonesAreRecorded() {
        XCTAssertEqual(choose(enabled: false), ChosenInput(id: headphones))
    }

    func testWithTheLidClosedTheHeadphonesAreRecorded() {
        XCTAssertEqual(choose(lidClosed: true), ChosenInput(id: headphones))
    }

    func testAMacWithoutItsOwnMicrophoneKeepsTheHeadphones() {
        XCTAssertEqual(choose(macMicrophone: nil), ChosenInput(id: headphones))
    }

    func testOtherDefaultInputsStay() {
        XCTAssertEqual(choose(defaultInput: 9, defaultIsBluetooth: false), ChosenInput(id: 9))
        XCTAssertEqual(choose(defaultInput: mac, defaultIsBluetooth: false), ChosenInput(id: mac))
    }

    func testNoDefaultInputIsNoInput() {
        XCTAssertNil(choose(defaultInput: nil))
    }

    func testTheSettingDefaultsOnAndDecodes() throws {
        func decode(_ json: String) throws -> Settings {
            try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try decode("{}").microphone.builtInWhileBluetoothPlays)
        XCTAssertFalse(try decode(#"{"microphone": {"builtInWhileBluetoothPlays": false}}"#).microphone.builtInWhileBluetoothPlays)
        var off = Settings()
        off.microphone.builtInWhileBluetoothPlays = false
        XCTAssertTrue(off.reset().microphone.builtInWhileBluetoothPlays)
    }

    func testTheNoticeSaysWhatToDo() {
        XCTAssertTrue(MicrophoneNotice.macMicrophoneHeardNothing.userMessage.contains("Pause the music"))
    }
}
