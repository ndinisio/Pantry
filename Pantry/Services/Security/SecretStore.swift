import Foundation
import Security

/// Where credentials live.
///
/// No key is ever compiled into the app, written to Info.plist, or committed. There are
/// exactly two ways a key reaches Pantry:
///
/// 1. The user types it into Settings, and it is stored in the Keychain on their device.
/// 2. A `GROQ_API_KEY` environment variable set on the Xcode scheme, for development only.
///
/// For anything beyond personal use, point Pantry at a backend you control instead
/// (Settings → AI → Secure proxy) so the credential never ships inside the app at all.
enum SecretStore {

    enum Key: String, CaseIterable {
        case groqAPIKey = "com.pantryapp.Pantry.groq-api-key"
        case proxyURL = "com.pantryapp.Pantry.proxy-url"
        case proxyToken = "com.pantryapp.Pantry.proxy-token"

        /// The scheme environment variable checked as a development fallback.
        var environmentVariable: String? {
            switch self {
            case .groqAPIKey: return "GROQ_API_KEY"
            case .proxyURL: return "PANTRY_AI_PROXY_URL"
            case .proxyToken: return "PANTRY_AI_PROXY_TOKEN"
            }
        }
    }

    // MARK: - Reading

    /// Keychain first, then the development environment variable.
    static func value(for key: Key) -> String? {
        if let stored = keychainValue(for: key), !stored.isEmpty { return stored }
        if let name = key.environmentVariable,
           let fromEnvironment = ProcessInfo.processInfo.environment[name],
           !fromEnvironment.isEmpty {
            return fromEnvironment
        }
        return nil
    }

    static func hasValue(for key: Key) -> Bool {
        value(for: key)?.isEmpty == false
    }

    /// Masked form for display, e.g. "gsk_••••••4f2a". Never shows the whole key.
    static func maskedValue(for key: Key) -> String? {
        guard let value = value(for: key), value.count > 8 else { return nil }
        let prefix = value.prefix(4)
        let suffix = value.suffix(4)
        return "\(prefix)••••••\(suffix)"
    }

    // MARK: - Writing

    @discardableResult
    static func set(_ value: String?, for key: Key) -> Bool {
        guard let value, !value.isEmpty else { return remove(key) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    @discardableResult
    static func remove(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Private

    private static func keychainValue(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
