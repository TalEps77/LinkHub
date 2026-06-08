#if DEBUG
import XCTest
import Combine
@testable import LinkHub

final class MockWiFiMonitorTests: XCTestCase {
    @MainActor
    func testInitialPublishedValuesMatchSampleData() {
        let mock = MockWiFiMonitor()
        XCTAssertEqual(mock.networks, MockWiFiMonitor.sampleNetworks)
        XCTAssertEqual(mock.connectedNetwork, MockWiFiMonitor.sampleNetworks.first { $0.isConnected })
        XCTAssertTrue(mock.isEnabled)
        XCTAssertTrue(mock.isHardwareAvailable)
        XCTAssertEqual(mock.scanStatus, .idle)
    }

    @MainActor
    func testRequestScanTransitionsScanStatus() async {
        let mock = MockWiFiMonitor()
        var observed: [ScanStatus] = []
        let cancellable = mock.scanStatusPublisher.sink { observed.append($0) }
        defer { cancellable.cancel() }

        await mock.requestScan()

        // Exact sequence: initial idle, scanning while sleeping, idle on completion.
        XCTAssertEqual(observed, [.idle, .scanning, .idle])
    }

    @MainActor
    func testStartStopAreNoOps() {
        let mock = MockWiFiMonitor()
        let networksBefore = mock.networks
        mock.start()
        mock.stop()
        XCTAssertEqual(mock.networks, networksBefore)
    }
}
#endif
