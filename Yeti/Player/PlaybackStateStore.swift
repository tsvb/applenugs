import Foundation

/// Snapshot of the queue, cursor, and playback position, persisted across
/// launches — the web roadmap's "persistent now-playing" item. Lives beside
/// session.json in Application Support.
struct PersistedPlayback: Codable {
    struct Track: Codable {
        var trackId: String
        var title: String?
        var artist: String?
        var show: String?
        var artworkPath: String?
        var showId: String?
    }

    var tracks: [Track]
    var index: Int
    var position: Double
}

final class PlaybackStateStore {
    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleNugs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("nowplaying.json")
    }

    func load() -> PersistedPlayback? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedPlayback.self, from: data)
    }

    /// Writes are suppressed under `-UITEST`.
    ///
    /// A seeded launch (`-UITestSeedQueue`) parks a stub queue, and anything
    /// that touched the transport from there — starting playback, skipping,
    /// clearing — used to persist those stubs straight over the real resume
    /// queue. That has cost a real queue at least once. Reads are deliberately
    /// left alone: a test launch restoring the real queue is harmless, and
    /// blocking it would change what the harness renders.
    func save(_ state: PersistedPlayback) {
        // `isUITestRun` only exists in DEBUG, and so does the seeding it guards.
        #if DEBUG
        guard !AppModel.isUITestRun else { return }
        #endif
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Also suppressed under `-UITEST` — "Clear" in a seeded launch would
    /// otherwise DELETE the real resume queue outright, which is the worse half
    /// of the same hazard `save(_:)` guards against.
    func clear() {
        #if DEBUG
        guard !AppModel.isUITestRun else { return }
        #endif
        try? FileManager.default.removeItem(at: fileURL)
    }
}
