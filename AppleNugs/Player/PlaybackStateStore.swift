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

    func save(_ state: PersistedPlayback) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
