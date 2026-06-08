import XCTest
@testable import LinkHub

final class SignalBarsTests: XCTestCase {
    func testActiveBarsBucketBoundaries() {
        XCTAssertEqual(SignalBars.activeBars(for: -60), 4)
        XCTAssertEqual(SignalBars.activeBars(for: -61), 3)
        XCTAssertEqual(SignalBars.activeBars(for: -70), 3)
        XCTAssertEqual(SignalBars.activeBars(for: -71), 2)
        XCTAssertEqual(SignalBars.activeBars(for: -80), 2)
        XCTAssertEqual(SignalBars.activeBars(for: -81), 1)
    }

    func testActiveBarsHandlesEdgeCases() {
        for rssi in [0, -60, -1000] {
            let bars = SignalBars.activeBars(for: rssi)
            XCTAssertTrue((1...4).contains(bars), "rssi \(rssi) → \(bars) out of 1...4")
        }
    }
}
