import XCTest
import Security
@testable import LinkHub

final class KeychainServiceTests: XCTestCase {

    // A stable, unlikely-to-collide SSID for live round-trip tests.
    private let testSSID = "LinkHubUnitTest-DoNotUse"

    // MARK: - Pure query-attribute assertions (no live Keychain access)

    func testBaseQueryHasClassServiceAccount() {
        let query = KeychainService.baseQuery(forSSID: "MyNet")

        XCTAssertEqual(query[kSecClass as String] as! CFString, kSecClassGenericPassword)
        XCTAssertEqual(query[kSecAttrService as String] as? String, KeychainService.service)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "MyNet")
        // baseQuery must NOT carry data, accessibility, or return/limit flags.
        XCTAssertNil(query[kSecValueData as String])
        XCTAssertNil(query[kSecAttrAccessible as String])
        XCTAssertNil(query[kSecReturnData as String])
    }

    func testAddQueryUsesAfterFirstUnlockAndCarriesData() {
        let data = Data("hunter2".utf8)
        let query = KeychainService.addQuery(password: data, forSSID: "MyNet")

        // FR31 / NFR12 attribute set assertion.
        XCTAssertEqual(query[kSecClass as String] as! CFString, kSecClassGenericPassword)
        XCTAssertEqual(query[kSecAttrService as String] as? String, KeychainService.service)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "MyNet")
        XCTAssertEqual(query[kSecValueData as String] as? Data, data)
        XCTAssertEqual(
            query[kSecAttrAccessible as String] as! CFString,
            kSecAttrAccessibleAfterFirstUnlock
        )
    }

    func testServiceMatchesBundleIdentifier() {
        // Service must be the bundle id (or the documented fallback in test hosts).
        let expected = Bundle.main.bundleIdentifier ?? "com.linkhub.app"
        XCTAssertEqual(KeychainService.service, expected)
    }

    func testCopyQueryRequestsDataAndSingleMatch() {
        let query = KeychainService.copyQuery(forSSID: "MyNet")

        XCTAssertEqual(query[kSecClass as String] as! CFString, kSecClassGenericPassword)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "MyNet")
        XCTAssertEqual(query[kSecReturnData as String] as! CFBoolean, kCFBooleanTrue)
        XCTAssertEqual(query[kSecMatchLimit as String] as! CFString, kSecMatchLimitOne)
    }

    func testUpdateAttributesCarryOnlyValue() {
        let data = Data("newpass".utf8)
        let attrs = KeychainService.updateAttributes(password: data)

        XCTAssertEqual(attrs[kSecValueData as String] as? Data, data)
        // Must not re-specify class/service/account (those belong to the match query).
        XCTAssertNil(attrs[kSecClass as String])
        XCTAssertNil(attrs[kSecAttrService as String])
    }

    // MARK: - Live round-trip (guarded — skips when no usable Keychain)

    /// set -> get -> overwrite (upsert) -> remove. Guarded with `XCTSkip` because the
    /// unsigned/headless unit-test host may lack a usable login Keychain
    /// (`errSecMissingEntitlement` / `errSecNotAvailable` / `errSecInteractionNotAllowed`).
    func testLiveRoundTrip() throws {
        try? KeychainService.remove(forSSID: testSSID)   // ensure clean start

        do {
            try KeychainService.set(password: "first-pass", forSSID: testSSID)
        } catch KeychainError.unhandled(let status) {
            throw XCTSkip("Keychain unavailable on this test host (OSStatus \(status)); skipping live round-trip.")
        }

        addTeardownBlock { try? KeychainService.remove(forSSID: self.testSSID) }

        // get returns what we set.
        XCTAssertEqual(KeychainService.password(forSSID: testSSID), "first-pass")

        // Upsert: set again with a different value updates in place (errSecDuplicateItem path).
        try KeychainService.set(password: "second-pass", forSSID: testSSID)
        XCTAssertEqual(KeychainService.password(forSSID: testSSID), "second-pass")

        // remove deletes it; subsequent read is nil.
        try KeychainService.remove(forSSID: testSSID)
        XCTAssertNil(KeychainService.password(forSSID: testSSID))
    }

    /// Reading an SSID that was never stored returns nil (not a thrown error).
    func testPasswordForUnknownSSIDReturnsNil() throws {
        // Best-effort cleanup in case a prior failed run left an entry.
        try? KeychainService.remove(forSSID: testSSID)
        XCTAssertNil(KeychainService.password(forSSID: testSSID))
    }

    /// remove on a non-existent SSID is a no-op success (errSecItemNotFound tolerated).
    func testRemoveUnknownSSIDDoesNotThrow() {
        XCTAssertNoThrow(try KeychainService.remove(forSSID: "NeverStored-\(UUID().uuidString)"))
    }
}
