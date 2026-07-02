import Foundation
import Observation

/// What the UI asks about a show's offline state.
enum ShowDownloadState: Equatable {
    case none
    case downloading(Double)   // 0...1 across the whole show
    case downloaded
    case failed(String)
}

/// Everything a download needs to know about a show up front, captured from
/// the album screen at tap time so completion never depends on the network.
struct ShowDownloadRequest {
    struct Track {
        let trackId: String
        let title: String?
        let artist: String?
        let durationText: String?
    }
    let containerID: String
    let title: String?
    let artist: String?
    let artworkPath: String?
    let tracks: [Track]
}

/// Source of truth for the offline library: the persisted manifest, live
/// per-track transfer progress, and the orchestration that turns a request
/// into files on disk. Platform-neutral; the Mac target can adopt it as-is.
@MainActor
@Observable
final class DownloadStore {

    private(set) var manifest = DownloadManifest()
    /// Live transfer progress per trackId (only while downloading).
    private(set) var trackProgress: [String: Double] = [:]
    /// Last failure message per containerID (cleared on retry/delete).
    private(set) var failures: [String: String] = [:]

    /// Shows currently in flight: containerID → pending request + received
    /// track files (so a show is committed to the manifest only when whole).
    private var inFlight: [String: PendingShow] = [:]
    private struct PendingShow {
        var request: ShowDownloadRequest
        var remaining: Set<String>          // trackIds still transferring
        var completed: [String: (fileName: String, bytes: Int64, formatRaw: String?)] = [:]
        /// Which download attempt this is — stale resolution loops from a
        /// cancelled/failed attempt check it and stand down.
        var generation: Int = 0
    }
    private var downloadGeneration = 0
    /// trackId → owning containerID for routing manager callbacks.
    private var trackOwner: [String: String] = [:]
    /// trackId → chosen pick metadata, captured at fetch time.
    private var pendingPicks: [String: StreamPick] = [:]

    private var manager: DownloadManager!
    private let client: NugsClient
    private let root: URL
    private let manifestURL: URL

    init(client: NugsClient) {
        self.client = client

        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleNugs/Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        root = dir
        manifestURL = dir.appendingPathComponent("manifest.json")

        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode(DownloadManifest.self, from: data) {
            manifest = decoded
        }

        // Bulk audio has no business in iCloud/device backups.
        var noBackup = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? noBackup.setResourceValues(values)

        // Reconcile disk with the manifest: show directories without a
        // manifest entry are half-finished downloads from a dead run.
        let known = Set(manifest.shows.map(\.containerID))
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for entry in entries
            where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && !known.contains(entry.lastPathComponent) {
                try? FileManager.default.removeItem(at: entry)
            }
        }

        manager = DownloadManager(
            onProgress: { [weak self] trackId, fraction in
                self?.trackProgress[trackId] = fraction
            },
            onComplete: { [weak self] trackId, result in
                self?.transferFinished(trackId: trackId, result: result)
            })
    }

    // --- queries ---------------------------------------------------------------

    func state(for containerID: String) -> ShowDownloadState {
        if let pending = inFlight[containerID] {
            let total = pending.request.tracks.count
            guard total > 0 else { return .downloading(0) }
            // Completed tracks count 1.0 each; live ones their fraction.
            let done = Double(pending.completed.count)
            let live = pending.remaining.reduce(0.0) { $0 + (trackProgress[$1] ?? 0) }
            return .downloading(min((done + live) / Double(total), 1))
        }
        if let message = failures[containerID] { return .failed(message) }
        if manifest.show(id: containerID) != nil { return .downloaded }
        return .none
    }

    func isDownloaded(trackId: String) -> Bool {
        localURL(trackId: trackId) != nil
    }

    /// The playable local file for a track — nil unless it exists on disk.
    func localURL(trackId: String) -> URL? {
        for show in manifest.shows {
            if let track = show.tracks.first(where: { $0.trackId == trackId }) {
                let url = root.appendingPathComponent(show.containerID, isDirectory: true)
                    .appendingPathComponent(track.fileName)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
        }
        return nil
    }

    // --- commands ---------------------------------------------------------------

    /// Download a whole show. No-op while the same show is in flight or
    /// already downloaded (delete first to re-download).
    func download(_ request: ShowDownloadRequest) {
        guard inFlight[request.containerID] == nil, !request.tracks.isEmpty,
              manifest.show(id: request.containerID) == nil else { return }
        failures[request.containerID] = nil

        let dir = root.appendingPathComponent(request.containerID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        downloadGeneration += 1
        let generation = downloadGeneration
        inFlight[request.containerID] = PendingShow(
            request: request,
            remaining: Set(request.tracks.map(\.trackId)),
            generation: generation)
        for track in request.tracks {
            trackOwner[track.trackId] = request.containerID
            trackProgress[track.trackId] = 0
        }

        // Resolve picks sequentially (cheap API calls), then hand transfers
        // to the background session, which parallelizes on its own.
        Task { [weak self] in
            for track in request.tracks {
                guard let self,
                      self.inFlight[request.containerID]?.generation == generation else { return }
                do {
                    let picks = try await self.client.resolveStreams(trackId: track.trackId)
                    // Re-check after the await: the attempt may have been
                    // cancelled/failed while resolution was in flight.
                    guard self.inFlight[request.containerID]?.generation == generation else { return }
                    guard let pick = bestDownloadablePick(picks),
                          let url = URL(string: pick.url) else {
                        self.transferFinished(
                            trackId: track.trackId,
                            result: .failure(NugsError.badResponse("stream-only track (no downloadable format)")))
                        continue
                    }
                    self.pendingPicks[track.trackId] = pick
                    self.manager.fetch(trackId: track.trackId, from: url)
                } catch {
                    guard self.inFlight[request.containerID]?.generation == generation else { return }
                    self.transferFinished(trackId: track.trackId, result: .failure(error))
                }
            }
        }
    }

    /// Remove a downloaded show's files and manifest entry (also cancels an
    /// in-flight download of that show).
    func delete(containerID: String) {
        if var pending = inFlight.removeValue(forKey: containerID) {
            manager.cancel(trackIds: pending.remaining)
            for trackId in pending.remaining {
                trackOwner[trackId] = nil
                trackProgress[trackId] = nil
                pendingPicks[trackId] = nil
            }
            pending.remaining = []
        }
        failures[containerID] = nil
        manifest.removeShow(id: containerID)
        saveManifest()
        try? FileManager.default.removeItem(
            at: root.appendingPathComponent(containerID, isDirectory: true))
    }

    // --- internals ---------------------------------------------------------------

    private func transferFinished(trackId: String, result: Result<URL, Error>) {
        trackProgress[trackId] = nil
        let pick = pendingPicks.removeValue(forKey: trackId)
        guard let containerID = trackOwner.removeValue(forKey: trackId),
              var pending = inFlight[containerID] else {
            // No owner: a ghost from a superseded/cancelled attempt. Its
            // parked file would otherwise sit in the inbox forever.
            if case .success(let parked) = result {
                try? FileManager.default.removeItem(at: parked)
            }
            return
        }
        pending.remaining.remove(trackId)

        switch result {
        case .success(let parkedFile):
            let ext = pick?.downloadFileExtension ?? "bin"
            let fileName = "\(trackId).\(ext)"
            let dest = root.appendingPathComponent(containerID, isDirectory: true)
                .appendingPathComponent(fileName)
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: parkedFile, to: dest)
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                let bytes = (attrs?[.size] as? Int64) ?? 0
                pending.completed[trackId] = (fileName, bytes, pick?.format.rawValue)
            } catch {
                failShow(containerID: containerID, pending: pending, message: error.localizedDescription)
                return
            }

        case .failure(let error):
            failShow(containerID: containerID, pending: pending, message: error.localizedDescription)
            return
        }

        if pending.remaining.isEmpty {
            // Whole show landed — commit to the manifest.
            let request = pending.request
            let tracks: [DownloadedTrack] = request.tracks.compactMap { track in
                guard let done = pending.completed[track.trackId] else { return nil }
                return DownloadedTrack(
                    trackId: track.trackId, title: track.title, artist: track.artist,
                    durationText: track.durationText, fileName: done.fileName,
                    formatRaw: done.formatRaw, bytes: done.bytes)
            }
            manifest.upsert(DownloadedShow(
                containerID: request.containerID, title: request.title,
                artist: request.artist, artworkPath: request.artworkPath, tracks: tracks))
            saveManifest()
            inFlight[containerID] = nil
        } else {
            inFlight[containerID] = pending
        }
    }

    /// One failed track fails the show: cancel its siblings, clean up, record
    /// the message so the UI can offer retry.
    private func failShow(containerID: String, pending: PendingShow, message: String) {
        manager.cancel(trackIds: pending.remaining)
        for trackId in pending.remaining {
            trackOwner[trackId] = nil
            trackProgress[trackId] = nil
            pendingPicks[trackId] = nil
        }
        inFlight[containerID] = nil
        failures[containerID] = message
        try? FileManager.default.removeItem(
            at: root.appendingPathComponent(containerID, isDirectory: true))
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
