import XCTest
@testable import LinkHub

/// Table-driven coverage of the pure `CWErrorDomain` code → `WiFiConnectionFailure` mapper.
/// No CoreWLAN dependency — the mapper takes a plain `Int`, so this runs on any platform/host.
final class WiFiConnectionFailureTests: XCTestCase {

    func testMapsKnownCWErrorCodesToTypedCauses() {
        let cases: [(code: Int, expected: WiFiConnectionFailure)] = [
            (-3905, .associationTimeout),   // kCWTimeoutErr
            (-3908, .associationTimeout),   // kCWDeviceTimeoutErr
            (1,     .authenticationError),  // kCWEAPOLErr
            (-3907, .outOfRange),           // kCWUnsupportedCapabilitiesErr
            (-3906, .outOfRange),           // kCWUnspecifiedFailureErr
            (-3903, .outOfRange),           // kCWNotSupportedErr
        ]
        for c in cases {
            XCTAssertEqual(
                WiFiConnectionFailure.map(cwErrorCode: c.code),
                c.expected,
                "code \(c.code) should map to \(c.expected)"
            )
        }
    }

    func testUnrecognizedCodeFallsThroughToUnknownCarryingTheCode() {
        // A couple of codes that are NOT in the explicit table (e.g. kCWInvalidParameterErr,
        // kCWNoMemoryErr, an arbitrary positive code) must surface as .unknown with the raw value.
        for code in [-3900, -3901, -3902, 42, 0] {
            XCTAssertEqual(WiFiConnectionFailure.map(cwErrorCode: code), .unknown(code: code))
        }
    }

    func testUnknownPreservesDistinctCodes() {
        // .unknown is Equatable on the associated value — two different unknown codes differ.
        XCTAssertNotEqual(
            WiFiConnectionFailure.map(cwErrorCode: -3900),
            WiFiConnectionFailure.map(cwErrorCode: -3901)
        )
    }
}
