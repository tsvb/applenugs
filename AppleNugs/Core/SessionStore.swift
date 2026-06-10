import Foundation

/// Persists the login session as JSON in Application Support — the native
/// analog of the server's tokens.json. The file lives inside the app's
/// sandbox container and is chmod 600.
final class SessionStore {
    private let fileURL: URL
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
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        cached = try? Self.decoder.decode(PersistedSession.self, from: data)
        return cached
    }

    func save(_ session: PersistedSession) throws {
        let data = try Self.encoder.encode(session)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        cached = session
    }

    func clear() {
        cached = nil
        try? FileManager.default.removeItem(at: fileURL)
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
