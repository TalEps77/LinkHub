#if DEBUG
import XCTest
import Combine
@testable import LinkHub

final class MockEthernetMonitorTests: XCTestCase {
    @MainActor
    func testInitialInterfacesMatchSampleData() {
        let mock = MockEthernetMonitor()
        XCTAssertEqual(mock.interfaces, MockEthernetMonitor.sampleInterfaces)
        XCTAssertTrue(mock.interfaces.contains { $0.state == .active })
        XCTAssertTrue(mock.interfaces.contains { $0.state == .obtaining })
    }

    @MainActor
    func testCustomInterfacesAreSeeded() {
        let custom = [
            EthernetInterface(id: "en9", bsdName: "en9", displayName: "Dock LAN",
                              linkSpeedMbps: nil, ipv4: nil, state: .noLink)
        ]
        let mock = MockEthernetMonitor(interfaces: custom)
        XCTAssertEqual(mock.interfaces, custom)
    }

    @MainActor
    func testInterfacesPublisherEmitsOnMutation() {
        let mock = MockEthernetMonitor(interfaces: [])
        var observed: [[EthernetInterface]] = []
        let cancellable = mock.interfacesPublisher.sink { observed.append($0) }
        defer { cancellable.cancel() }

        mock.interfaces = MockEthernetMonitor.sampleInterfaces

        // Initial empty emission + the post-mutation sample emission.
        XCTAssertEqual(observed.first, [])
        XCTAssertEqual(observed.last, MockEthernetMonitor.sampleInterfaces)
    }

    @MainActor
    func testStartStopAreNoOps() {
        let mock = MockEthernetMonitor()
        let before = mock.interfaces
        mock.start()
        mock.stop()
        XCTAssertEqual(mock.interfaces, before)
    }
}
#endif
