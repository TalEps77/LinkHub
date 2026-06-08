import Foundation
import Security

/// Typed failures surfaced by `KeychainService`. Callers (Story 2.3 connect flow,
/// Story 2.6 Forget) decide success/failure based on these — no `NSError` leaks
/// past this boundary (architecture.md § Error types).
///
/// `unexpectedData` covers a successful `SecItemCopyMatching` that returned a
/// payload which is not valid UTF-8 `Data` (should not happen for items we wrote,
/// but we never force-unwrap). `unhandled(OSStatus)` carries the raw Security
/// framework status for any other failure so the call site / logs can inspect it.
enum KeychainError: Error, Equatable {
    case unexpectedData
    case unhandled(OSStatus)
}

/// Persists user-entered Wi-Fi passphrases in the login Keychain via the Security
/// framework, keyed by SSID. This is the ONLY long-lived password store in LinkHub
/// (NFR12): no UserDefaults, no plain files, no in-memory cache.
///
/// Stateless `enum` namespace with `static` funcs. `SecItem*` C APIs are
/// thread-safe, so the type holds no mutable state and is callable from any
/// isolation context (`Sendable`-clean by construction — there is nothing to send).
///
/// Attribute set (per FR31 / NFR12 / architecture.md "Keychain" + PRD 08 D7/D8):
///   - `kSecClass`          = `kSecClassGenericPassword`
///   - `kSecAttrService`    = `Bundle.main.bundleIdentifier`
///   - `kSecAttrAccount`    = SSID (verbatim, no prefix — architecture.md "Keychain account")
///   - `kSecAttrAccessible` = `kSecAttrAccessibleAfterFirstUnlock`
///   - `kSecValueData`      = UTF-8 bytes of the passphrase
///
/// No `kSecAttrSynchronizable` — local keychain only, no iCloud sync (docs/06).
/// No `keychain-access-groups` entitlement — the app reaches its own items via the
/// implicit bundle-ID group outside the sandbox (PRD 08 D8).
enum KeychainService {

    /// Keychain `service` attribute — the app's bundle identifier. Falls back to the
    /// canonical bundle id for unit-test hosts where `Bundle.main.bundleIdentifier`
    /// may be nil.
    static let service = Bundle.main.bundleIdentifier ?? "com.linkhub.app"

    // MARK: - Public API

    /// Stores (or replaces) the passphrase for `ssid`. Upsert: adds the item, or
    /// updates the existing one if a duplicate is present (`errSecDuplicateItem`).
    ///
    /// Callers persist a password ONLY after a confirmed successful connection
    /// (UX-DR31) — that rule lives in the caller (Story 2.3), not here.
    /// - Throws: `KeychainError.unhandled` carrying the raw `OSStatus` on failure.
    static func set(password: String, forSSID ssid: String) throws {
        let data = Data(password.utf8)
        let addStatus = SecItemAdd(addQuery(password: data, forSSID: ssid) as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Item exists — update its value in place rather than delete+re-add.
            let updateStatus = SecItemUpdate(
                baseQuery(forSSID: ssid) as CFDictionary,
                updateAttributes(password: data) as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandled(updateStatus)
            }
        default:
            throw KeychainError.unhandled(addStatus)
        }
    }

    /// Returns the stored passphrase for `ssid`, or `nil` if no item exists
    /// (`errSecItemNotFound`). On any other Security failure returns `nil` too — the
    /// caller treats a nil read as "not remembered" and re-prompts (per AC: the user
    /// is re-prompted only if retrieval fails).
    static func password(forSSID ssid: String) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(copyQuery(forSSID: ssid) as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        return password
    }

    /// Removes the stored passphrase for `ssid` (used by Story 2.6 "Forget").
    /// A missing item (`errSecItemNotFound`) is treated as success — the desired
    /// post-state (no stored password) already holds.
    /// - Throws: `KeychainError.unhandled` carrying the raw `OSStatus` on failure.
    static func remove(forSSID ssid: String) throws {
        let status = SecItemDelete(baseQuery(forSSID: ssid) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    // MARK: - Query construction (pure, unit-testable helpers)

    /// Identifies a single generic-password item by class + service + account.
    /// Used as the match query for update / delete.
    static func baseQuery(forSSID ssid: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid
        ]
    }

    /// Full attribute set for `SecItemAdd` — `baseQuery` plus the value and the
    /// `kSecAttrAccessibleAfterFirstUnlock` accessibility attribute.
    static func addQuery(password data: Data, forSSID ssid: String) -> [String: Any] {
        var query = baseQuery(forSSID: ssid)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return query
    }

    /// Attributes passed to `SecItemUpdate` (the second dictionary): the new value.
    /// The accessibility attribute is preserved from the original add.
    static func updateAttributes(password data: Data) -> [String: Any] {
        [kSecValueData as String: data]
    }

    /// `baseQuery` plus the flags that ask `SecItemCopyMatching` to return the
    /// stored data for the single matching item.
    static func copyQuery(forSSID ssid: String) -> [String: Any] {
        var query = baseQuery(forSSID: ssid)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
}
