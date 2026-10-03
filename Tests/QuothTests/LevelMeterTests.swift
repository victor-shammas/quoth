import XCTest
@testable import QuothDomain

final class LevelMeterTests: XCTestCase {
    private func meter() -> LevelMeter { LevelMeter(jitter: { 1 }) }

    func testBarsMoveOncePerRefresh() {
        var meter = meter()
        XCTAssertNotNil(meter.add(0.2, at: 1.0))
        XCTAssertNil(meter.add(0.2, at: 1.05))
        XCTAssertNotNil(meter.add(0.2, at: 1.1))
    }

    func testTheMiddleBarsPeakHighest() throws {
        var meter = meter()
        let bars = try XCTUnwrap(meter.add(0.04, at: 1))
        XCTAssertEqual(bars.count, LevelMeter.barCount)
        XCTAssertEqual(bars[2], bars[3])
        XCTAssertGreaterThan(bars[2], bars[1])
        XCTAssertGreaterThan(bars[1], bars[0])
        XCTAssertEqual(bars[0], bars[5])
    }

    func testABarIsTheRMSSinceTheLastRefreshShaped() throws {
        var meter = meter()
        _ = meter.add(0, at: 1)
        _ = meter.add(0.03, at: 1.02)
        let bars = try XCTUnwrap(meter.add(0.04, at: 1.1))
        // RMS of 0.03 and 0.04 is about 0.0354; shaped: sqrt × 3.4.
        XCTAssertEqual(bars[2], (0.0354 as Float).squareRoot() * 3.4, accuracy: 0.001)
    }

    func testLoudLevelsAreCappedAtFull() throws {
        var meter = meter()
        XCTAssertEqual(try XCTUnwrap(meter.add(1, at: 1))[2], 1)
    }

    func testSilenceIsNotVoice() {
        var meter = meter()
        _ = meter.add(0.001, at: 1)
        XCTAssertFalse(meter.heardVoice)
        _ = meter.add(0.05, at: 2)
        XCTAssertTrue(meter.heardVoice)
        meter.reset()
        XCTAssertFalse(meter.heardVoice)
    }
}
