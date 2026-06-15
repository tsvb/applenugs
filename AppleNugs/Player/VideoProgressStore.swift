import Foundation
import Observation

/// One video's resume point. `id` is the container/release id; `videoSku` lets
/// the Continue Watching strip reopen + replay without re-fetching the SKU.
struct VideoProgress: Codable, Identifiable, Hashable {
    var id: String
    var videoSku: Int
    var title: String
    var artistName: String
    var imageURL: String?
    var positionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date
}

/// Persists per-video playback positions as JSON in Application Support — the
/// same idiom as SessionStore/FavoritesStore (atomic write, chmod 600).
/// @Observable so the Continue Watching strip updates reactively. Livestreams
/// are never recorded here (no meaningful resume); the caller enforces that.
@MainActor
@Observable
final class VideoProgressStore {
    private(set) var items: [VideoProgress] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleNugs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("videoprogress.json")
        load()
    }

    // --- reads --------------------------------------------------------------

    func progress(for id: String) -> VideoProgress? {
        items.first { $0.id == id }
    }

    /// Newest first, for the Continue Watching strip.
    var recent: [VideoProgress] {
        items.sorted { $0.updatedAt > $1.updatedAt }
    }

    // --- writes -------------------------------------------------------------

    /// Insert or update by id.
    func record(_ p: VideoProgress) {
        if let idx = items.firstIndex(where: { $0.id == p.id }) {
            items[idx] = p
        } else {
            items.append(p)
        }
        save()
    }

    /// Remove a finished (or no-longer-resumable) video.
    func markFinished(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: idx)
        save()
    }

    // --- persistence --------------------------------------------------------

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([VideoProgress].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? Self.encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
