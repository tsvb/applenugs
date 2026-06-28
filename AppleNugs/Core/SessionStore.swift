import Foundation
import Security

/// Persists the login session (OAuth access + refresh tokens and subscription
/// metadata). The refresh token is a long-lived bearer credential, so it
/// belongs in the Keychain rather than a plaintext file. We store it as a
/// generic-password item and keep a chmod-600 file in the sandbox container
/// only as a fallback for builds where the Keychain isn't available (an
/// unsigned/ad-hoc dev build has no keychain-access entitlement). A legacy
/// session.json is migrated into the Keychain on first load and then removed.
final class SessionStore {
    private let fileURL: URL
    private let keychain = KeychainItem(
        service: Bundle.main.bundleIdentifier ?? "com.timvbs.applenugs",
        account: "session")
    private var cached: PersistedSession?

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleNugs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("session.json")
    }

    func load() -> PersistedSession? {
        if let cached { return cached }

        // Keychain is the source of truth.
        if let data = keychain.read(), let session = decode(data) {
            cached = session
            return session
        }

        // No Keychain item: read the legacy file and migrate it in. If the
        // Keychain accepts it, drop the plaintext file; otherwise keep using it.
        guard let data = try? Data(contentsOf: fileURL), let session = decode(data) else { return nil }
        cached = session
        if keychain.write(data) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return session
    }

    func save(_ session: PersistedSession) throws {
        let data = try Self.encoder.encode(session)
        cached = session
        if keychain.write(data) {
            // Token now lives in the Keychain — remove any plaintext copy.
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        // Keychain unavailable (e.g. unsigned dev build): fall back to the
        // chmod-600 file inside the app's sandbox container.
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func clear() {
        cached = nil
        keychain.delete()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func decode(_ data: Data) -> PersistedSession? {
        try? Self.decoder.decode(PersistedSession.self, from: data)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Thin wrapper over a single Keychain generic-password item. Every method is
/// best-effort: any `OSStatus` failure (notably `errSecMissingEntitlement` on
/// an unsigned/ad-hoc build) is reported as nil/false so `SessionStore` can fall
/// back to file storage instead of failing to persist the session.
private struct KeychainItem {
    let service: String
    let account: String

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Insert or update the item. Returns false on any Keychain error.
    func write(_ data: Data) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            // Human-readable label shown in Keychain Access (and any rare access
            // prompt) instead of the raw bundle id, so it never reads as a
            // cryptic "what is this?" item to the user.
            kSecAttrLabel as String: "AppleNugs login",
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = baseQuery
        addQuery.merge(attributes) { _, new in new }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
