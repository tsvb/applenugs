import Foundation
import Observation

struct FavArtist: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var savedAt: Date
}

struct FavShow: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var artistName: String
    var dateText: String?
    var venue: String?
    var imageURL: String?
    var savedAt: Date
}

struct FavVideo: Codable, Identifiable, Hashable {
    var id: String
    var videoSku: Int
    var title: String
    var artistName: String
    var dateText: String?
    var isLive: Bool
    var imageURL: String?
    var savedAt: Date
}

/// Persists followed artists and saved shows as JSON in Application Support —
/// the same idiom as SessionStore. @Observable, so stars and the Favorites view
/// update reactively on any toggle. Favorites persist across logout (they are
/// catalog references, not account secrets).
@MainActor
@Observable
final class FavoritesStore {
    private(set) var favArtists: [FavArtist] = []
    private(set) var favShows: [FavShow] = []
    private(set) var favVideos: [FavVideo] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleNugs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("favorites.json")
        load()
    }

    // --- sorted accessors ---------------------------------------------------

    var artists: [FavArtist] {
        favArtists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var shows: [FavShow] {
        favShows.sorted { $0.savedAt > $1.savedAt }
    }
    var videos: [FavVideo] {
        favVideos.sorted { $0.savedAt > $1.savedAt }
    }
    var isEmpty: Bool { favArtists.isEmpty && favShows.isEmpty && favVideos.isEmpty }

    // --- artists ------------------------------------------------------------

    func isArtistFavorited(_ id: String) -> Bool { favArtists.contains { $0.id == id } }

    func toggleArtist(id: String, name: String) {
        if let idx = favArtists.firstIndex(where: { $0.id == id }) {
            favArtists.remove(at: idx)
        } else {
            favArtists.append(FavArtist(id: id, name: name, savedAt: Date()))
        }
        save()
    }

    // --- shows --------------------------------------------------------------

    func isShowFavorited(_ id: String) -> Bool { favShows.contains { $0.id == id } }

    func toggleShow(id: String, title: String, artistName: String,
                    dateText: String?, venue: String?, imageURL: String?) {
        if let idx = favShows.firstIndex(where: { $0.id == id }) {
            favShows.remove(at: idx)
        } else {
            favShows.append(FavShow(id: id, title: title, artistName: artistName,
                                    dateText: dateText, venue: venue,
                                    imageURL: imageURL, savedAt: Date()))
        }
        save()
    }

    // --- videos -------------------------------------------------------------

    func isVideoFavorited(_ id: String) -> Bool { favVideos.contains { $0.id == id } }

    func toggleVideo(_ v: FavVideo) {
        if let idx = favVideos.firstIndex(where: { $0.id == v.id }) {
            favVideos.remove(at: idx)
        } else {
            var stamped = v
            stamped.savedAt = Date()
            favVideos.append(stamped)
        }
        save()
    }

    // --- persistence --------------------------------------------------------

    private struct Stored: Codable {
        var artists: [FavArtist]
        var shows: [FavShow]
        var videos: [FavVideo]

        init(artists: [FavArtist], shows: [FavShow], videos: [FavVideo]) {
            self.artists = artists
            self.shows = shows
            self.videos = videos
        }

        // Tolerate files written before `videos` existed (decode it as empty).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            artists = try c.decodeIfPresent([FavArtist].self, forKey: .artists) ?? []
            shows = try c.decodeIfPresent([FavShow].self, forKey: .shows) ?? []
            videos = try c.decodeIfPresent([FavVideo].self, forKey: .videos) ?? []
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode(Stored.self, from: data) else { return }
        favArtists = decoded.artists
        favShows = decoded.shows
        favVideos = decoded.videos
    }

    private func save() {
        let stored = Stored(artists: favArtists, shows: favShows, videos: favVideos)
        guard let data = try? Self.encoder.encode(stored) else { return }
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
