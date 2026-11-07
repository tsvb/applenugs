import Foundation

// The persisted record of what's downloaded: one manifest, one entry per
// show, one entry per track file. Pure data + mutation helpers — all disk
// and transfer work lives in DownloadStore/DownloadManager.

struct DownloadedTrack: Codable, Equatable {
    let trackId: String
    var title: String?
    var artist: String?
    var durationText: String?
    /// File name inside the show's directory: an opaque `<uuid>.yeti` for a
    /// sealed download. Manifests from before encryption hold the raw CDN
    /// file here ("12345.flac") until the launch migration seals it.
    var fileName: String
    /// AudioFormat.rawValue of the downloaded pick (raw string so the
    /// manifest stays decodable if formats evolve).
    var formatRaw: String?
    /// On-disk size (the sealed file's, once sealed).
    var bytes: Int64
    /// The container's UTI (e.g. "org.xiph.flac"), recorded when sealed. The
    /// file's own authenticated header is what playback trusts; this is the
    /// manifest's readable copy. Optional so pre-encryption manifests decode.
    var contentType: String? = nil

    /// True once the file is in the sealed format. Anything else is a
    /// plaintext download awaiting migration, and never plays.
    var isSealed: Bool {
        fileName.hasSuffix("." + SealedFile.fileExtension)
    }
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

    /// Sum of every downloaded show's bytes — drives the storage footer.
    var totalBytes: Int64 {
        shows.reduce(0) { $0 + $1.totalBytes }
    }

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

    /// Every track still stored as plaintext, with its show — the launch
    /// migration's work list (empty once migrated, so it is idempotent).
    var unsealedTracks: [(containerID: String, track: DownloadedTrack)] {
        shows.flatMap { show in
            show.tracks.filter { !$0.isSealed }.map { (show.containerID, $0) }
        }
    }

    /// The file names a show's directory is supposed to contain. Anything
    /// else in there is debris from an interrupted write or migration.
    func fileNames(containerID: String) -> Set<String> {
        Set(show(id: containerID)?.tracks.map(\.fileName) ?? [])
    }

    /// Point one track at a new file (the migration's commit step). Returns
    /// false — changing nothing — unless the track still names `oldFileName`,
    /// so a stale migration step can never clobber a newer entry.
    @discardableResult
    mutating func replaceFile(trackId: String, containerID: String, oldFileName: String,
                              newFileName: String, bytes: Int64, contentType: String) -> Bool {
        guard let s = shows.firstIndex(where: { $0.containerID == containerID }),
              let t = shows[s].tracks.firstIndex(where: {
                  $0.trackId == trackId && $0.fileName == oldFileName
              }) else { return false }
        shows[s].tracks[t].fileName = newFileName
        shows[s].tracks[t].bytes = bytes
        shows[s].tracks[t].contentType = contentType
        return true
    }

    func track(id: String) -> DownloadedTrack? {
        for show in shows {
            if let t = show.tracks.first(where: { $0.trackId == id }) { return t }
        }
        return nil
    }
}
