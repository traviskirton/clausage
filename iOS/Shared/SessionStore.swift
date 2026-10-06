import Foundation
import Security

/// What the iPhone needs to talk to claude.ai after signing in: the `sessionKey` cookie, the user agent the sign-in web view used,
/// and the organization to ask about.
struct ClaudeSessionRecord: Codable, Equatable {
    var sessionKey: String
    var userAgent: String
    var orgID: String
    var orgName: String
}

/// Keychain storage shared by the app and the widget extension (same access group), readable after the first unlock
/// so background refresh and widgets keep working with the screen locked.
enum SessionStore {
    static let accessGroup = "G3GED29J33.com.postfl.clausage-ios.shared"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "claude-session",
         kSecAttrAccount as String: "default",
         kSecAttrAccessGroup as String: accessGroup]
    }

    static func load() -> ClaudeSessionRecord? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(ClaudeSessionRecord.self, from: data)
    }

    /// Returns false if the Keychain refused (for example a missing entitlement).
    @discardableResult
    static func save(_ record: ClaudeSessionRecord) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        SecItemDelete(base as CFDictionary)
        var q = base
        q[kSecValueData as String] = data
        // This iPhone only: never synced to iCloud Keychain and never restored from a backup onto another device.
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func clear() { SecItemDelete(base as CFDictionary) }

    /// Items saved by older builds were backup-eligible; re-save once so they become this-device-only.
    static func migrateToThisDeviceOnly() {
        let flag = "sessionThisDeviceOnly"
        guard !SharedStore.defaults.bool(forKey: flag) else { return }
        if let record = load() { save(record) }
        SharedStore.defaults.set(true, forKey: flag)
    }
}
