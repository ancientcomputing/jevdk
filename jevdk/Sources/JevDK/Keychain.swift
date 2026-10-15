import Foundation
import Security

/// API keys for remote Jev providers, in the login Keychain. Never written to disk or logs.
enum Keychain {
    #if MAS_BUILD
    /// The Mac App Store build's own items, so with both builds installed it never finds (and makes
    /// macOS ask about) the DMG build's keys.
    private static let service = "ai.thisbrain.jevdk"
    #else
    private static let service = "JevDK"
    #endif

    static func get(_ account: String) -> String? {
        read(account, service: service)
    }

    static func set(_ value: String?, for account: String) {
        delete(account, service: service)
        guard let value, !value.isEmpty else { return }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8)]
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func read(_ account: String, service: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(_ account: String, service: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
