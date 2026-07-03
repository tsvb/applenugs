import Foundation

// The persisted record of what's downloaded: one manifest, one entry per
// show, one entry per track file. Pure data + mutation helpers — all disk
// and transfer work lives in DownloadStore/DownloadManager.

struct DownloadedTrack: Codable, Equatable {
    let trackId: String
    var title: String?
    var artist: String?
    var durationText: String?
    /// File name inside the show's directory, e.g. "12345.flac".
    var fileName: String
    /// AudioFormat.rawValue of the downloaded pick (raw string so the
    /// manifest stays decodable if formats evolve).
    var formatRaw: String?
    var bytes: Int64
}

struct DownloadedShow: Codable, Equatable {
    let containerID: String
    var title: String?
    var artist: String?
    var artworkPath: String?
    var tracks: [DownloadedTrack]

    var totalBytes: Int64 {
        tracks.reduce(0) { $0 + $1.bytes }
    }
}

struct DownloadManifest: Codable, Equatable {
    var shows: [DownloadedShow] = []

    /// Insert the show, replacing any existing entry with the same id.
    mutating func upsert(_ show: DownloadedShow) {
        removeShow(id: show.containerID)
        shows.append(show)
    }

    mutating func removeShow(id: String) {
        shows.removeAll { $0.containerID == id }
    }

    func show(id: String) -> DownloadedShow? {
        shows.first { $0.containerID == id }
    }

    func track(id: String) -> DownloadedTrack? {
        for show in shows {
            if let t = show.tracks.first(where: { $0.trackId == id }) { return t }
        }
        return nil
    }
}
