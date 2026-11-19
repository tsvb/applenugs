import CryptoKit
import Foundation
import Security

/// The per-install 256-bit key every download is sealed with. Lives in the
/// Keychain as its own generic-password item (same service as the login
/// item, account "download-key"), this-device-only and never synced — so a
/// backup or a copied Application Support folder carries ciphertext without
/// the key. Created lazily on the first download, deleted on logout.
///
/// There is deliberately NO file fallback (unlike `SessionStore`): a key next
/// to the files it protects protects nothing. If the Keychain refuses, the
/// download fails and says so.
///
/// Thread-safe: used from detached sealing tasks and the resource loader's
/// queue. The lock also serializes the create-if-missing race between two
/// tracks finishing at once.
final class DownloadKeyStore: @unchecked Sendable {
    static let shared = DownloadKeyStore()

    enum Failure: LocalizedError {
        case missing
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missing:
                return "The offline download key is missing."
            case .keychain(let status):
                return "Couldn't store the offline download key in the Keychain (\(status))."
            }
        }
    }

    private let lock = NSLock()
    private var cached: SymmetricKey?
    private let service = Bundle.main.bundleIdentifier ?? "com.timvbs.applenugs"
    private let account = "download-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    /// The key, creating and storing it first when `creatingIfMissing`.
    func key(creatingIfMissing: Bool) throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        if let data = read() {
            let key = SymmetricKey(data: data)
            cached = key
            return key
        }
        guard creatingIfMissing else { throw Failure.missing }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var add = baseQuery
        add[kSecValueData as String] = data
        // AfterFirstUnlock, not WhenUnlocked: a downloaded queue keeps playing
        // (and preloading the next track) on a locked iPhone.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "Yeti offline downloads key"
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = read() {
            // Another process/thread won; use theirs, never overwrite it (that
            // would orphan every file sealed with it).
            let key = SymmetricKey(data: existing)
            cached = key
            return key
        }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        cached = key
        return key
    }

    /// Remove the key. Every sealed file becomes permanently unreadable, so
    /// this is only called alongside deleting them (logout).
    func delete() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        SecItemDelete(baseQuery as CFDictionary)
    }

    private func read() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 32 else { return nil }
        return data
    }
}
