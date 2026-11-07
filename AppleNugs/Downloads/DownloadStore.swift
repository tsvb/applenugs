import AVFoundation
import Foundation
import Observation

/// What the player asks about a track's download.
enum LocalPlayback: Equatable {
    /// Not downloaded (or not yet sealed) — stream it.
    case none
    /// Downloaded and allowed to play: the `yeti-local://` pick.
    case available(StreamPick)
    /// Downloaded, but the subscription hasn't been confirmed online within
    /// `OfflineAccessPolicy.window`. Stream it if the network allows; if not,
    /// the player says "Go online to keep listening offline".
    case needsVerification
}

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
///
/// Files at rest are sealed (`SealedFile`): each finished transfer is
/// encrypted off the main actor into `<uuid>.yeti` and the plaintext deleted
/// at once; playback decrypts through `SealedAssetLoader`. Plaintext
/// downloads from before encryption are sealed by a one-time launch
/// migration — or deleted if they can't be — and never play as they are.
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
        var remaining: Set<String>          // trackIds still transferring or sealing
        var completed: [String: Sealed] = [:]
        /// Which download attempt this is — stale resolution loops from a
        /// cancelled/failed attempt check it and stand down.
        var generation: Int = 0
    }
    /// One sealed track file, ready to be committed to the manifest.
    private struct Sealed {
        var fileName: String
        var bytes: Int64
        var formatRaw: String?
        var contentType: String
    }
    private var downloadGeneration = 0
    /// Bumped by `deleteAll` so a migration pass started before it stands down.
    private var libraryEpoch = 0
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
        DownloadSealing.protect(dir)

        // Reconcile disk with the manifest: show directories without a
        // manifest entry are half-finished downloads from a dead run, and
        // files inside a known show that the manifest doesn't name are debris
        // from an interrupted seal or migration step (either side of its
        // manifest save) — a sealed file never committed, or the plaintext
        // original of one that was.
        let known = Set(manifest.shows.map(\.containerID))
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for entry in entries
            where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                guard known.contains(entry.lastPathComponent) else {
                    try? FileManager.default.removeItem(at: entry)
                    continue
                }
                let expected = manifest.fileNames(containerID: entry.lastPathComponent)
                for file in (try? FileManager.default.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: nil)) ?? []
                where !expected.contains(file.lastPathComponent) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }

        manager = DownloadManager(
            onProgress: { [weak self] trackId, fraction in
                guard let self else { return }
                // URLSession delivers progress per network chunk (tens to
                // hundreds of callbacks/sec across parallel tracks), and
                // @Observable notifies on every set — coalesce to visible
                // increments (~1% of a track). Completion doesn't pass here:
                // transferFinished clears the entry and counts the track as
                // done, so nothing sticks at 99%.
                if fraction - (self.trackProgress[trackId] ?? 0) >= 0.01 {
                    self.trackProgress[trackId] = fraction
                }
            },
            onComplete: { [weak self] trackId, result in
                self?.transferFinished(trackId: trackId, result: result)
            })

        migrateUnsealedDownloads()
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
        sealedFile(trackId: trackId) != nil
    }

    /// How the player should treat a track: play the download, stream it, or
    /// stream it because the download is waiting on a subscription check.
    func localPlayback(trackId: String, now: Date = Date()) -> LocalPlayback {
        guard let (containerID, track) = sealedFile(trackId: trackId) else { return .none }
        guard OfflineAccessPolicy.allowsOfflinePlay(
            lastVerifiedAt: OfflineVerification.lastVerifiedAt(), now: now) else {
            return .needsVerification
        }
        var components = URLComponents()
        components.scheme = SealedFile.urlScheme
        components.host = "download"
        components.path = "/\(containerID)/\(track.fileName)"
        guard let url = components.url else { return .none }
        let format = track.formatRaw.flatMap(AudioFormat.init(rawValue:)) ?? .unknown
        return .available(StreamPick(url: url.absoluteString, platformId: 0, format: format))
    }

    /// The asset for a `yeti-local://download/<containerID>/<file>` pick from
    /// `localPlayback`: decrypted on the fly by its own resource loader.
    func makeAsset(for url: URL) -> AVURLAsset? {
        // pathComponents is ["/", containerID, fileName].
        let parts = url.pathComponents
        guard url.scheme == SealedFile.urlScheme, parts.count == 3,
              !parts[1].contains(".."), !parts[2].contains("..") else { return nil }
        let fileURL = root.appendingPathComponent(parts[1], isDirectory: true)
            .appendingPathComponent(parts[2])
        return SealedURLAsset(fileURL: fileURL, name: parts[2]) {
            try DownloadKeyStore.shared.key(creatingIfMissing: false)
        }
    }

    /// The manifest entry for a track whose sealed file is on disk. Plaintext
    /// entries awaiting migration don't count — they never play.
    private func sealedFile(trackId: String) -> (containerID: String, track: DownloadedTrack)? {
        for show in manifest.shows {
            guard let track = show.tracks.first(where: { $0.trackId == trackId }) else { continue }
            guard track.isSealed else { return nil }
            let url = root.appendingPathComponent(show.containerID, isDirectory: true)
                .appendingPathComponent(track.fileName)
            return FileManager.default.fileExists(atPath: url.path) ? (show.containerID, track) : nil
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
        DownloadSealing.protect(dir)

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

        // Resolve picks sequentially, a short pause apart, then hand each
        // transfer to the background session (at most two per host at once).
        // `.download` makes an HLS-only tier fall through to one with a file.
        Task { [weak self] in
            for (i, track) in request.tracks.enumerated() {
                if i > 0 { try? await Task.sleep(for: DownloadPacing.resolveGap) }
                guard let self,
                      self.inFlight[request.containerID]?.generation == generation else { return }
                do {
                    let picks = try await self.client.resolveStreams(
                        trackId: track.trackId, purpose: .download)
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

    /// Logout: every download, every in-flight transfer, the manifest, and the
    /// key. Call after the player has let go of any local item.
    func deleteAll() {
        libraryEpoch += 1
        manager.cancel(trackIds: Array(trackOwner.keys))
        inFlight = [:]
        trackOwner = [:]
        trackProgress = [:]
        pendingPicks = [:]
        failures = [:]
        manifest = DownloadManifest()
        saveManifest()
        for entry in (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        where entry != manifestURL {
            try? FileManager.default.removeItem(at: entry)
        }
        DownloadKeyStore.shared.delete()
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

        switch result {
        case .success(let parkedFile):
            // Seal off the main actor (a FLAC set is tens of MB). The track
            // stays in `remaining` — showing as fully transferred — until the
            // sealed file is committed in `sealFinished`.
            trackProgress[trackId] = 1
            let contentType = SealedFile.contentType(
                forExtension: pick?.downloadFileExtension ?? "bin")
            let fileName = "\(UUID().uuidString.lowercased()).\(SealedFile.fileExtension)"
            let dest = root.appendingPathComponent(containerID, isDirectory: true)
                .appendingPathComponent(fileName)
            let generation = pending.generation
            let formatRaw = pick?.format.rawValue
            Task.detached(priority: .utility) { [weak self] in
                let outcome = Result {
                    try DownloadSealing.seal(plaintext: parkedFile, to: dest,
                                             contentType: contentType, deletingPlaintext: true)
                }
                await self?.sealFinished(
                    trackId: trackId, containerID: containerID, generation: generation,
                    dest: dest, outcome: outcome.map {
                        Sealed(fileName: fileName, bytes: $0, formatRaw: formatRaw,
                               contentType: contentType)
                    })
            }

        case .failure(let error):
            pending.remaining.remove(trackId)
            failShow(containerID: containerID, pending: pending, message: error.localizedDescription)
        }
    }

    /// A finished transfer has been sealed (or failed to). Commits the show
    /// once every track is in. A seal that lands after its show was deleted,
    /// failed, or restarted removes its own file.
    private func sealFinished(trackId: String, containerID: String, generation: Int,
                              dest: URL, outcome: Result<Sealed, Error>) {
        guard var pending = inFlight[containerID], pending.generation == generation,
              pending.remaining.contains(trackId) else {
            try? FileManager.default.removeItem(at: dest)
            return
        }
        trackProgress[trackId] = nil
        pending.remaining.remove(trackId)

        switch outcome {
        case .success(let sealed):
            pending.completed[trackId] = sealed
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
                    formatRaw: done.formatRaw, bytes: done.bytes,
                    contentType: done.contentType)
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

    // --- migration ---------------------------------------------------------------

    /// Seal every plaintext download left by a pre-encryption build, one
    /// track at a time, off the main actor. Per track the order is: write the
    /// sealed file → point the manifest at it and save → delete the
    /// plaintext. A crash between any two steps leaves an unreferenced file
    /// that the next launch's sweep (in init) deletes, and an entry that
    /// still names a file that exists — so re-running is always safe, and a
    /// finished migration has nothing left to do. A track that can't be
    /// sealed takes its whole show with it: plaintext is never kept.
    private func migrateUnsealedDownloads() {
        let work = manifest.unsealedTracks
        guard !work.isEmpty else { return }
        let epoch = libraryEpoch
        let root = self.root
        Task { [weak self] in
            for (containerID, track) in work {
                guard let self, self.libraryEpoch == epoch else { return }
                let dir = root.appendingPathComponent(containerID, isDirectory: true)
                let source = dir.appendingPathComponent(track.fileName)
                // Still the same entry? (The show may have been deleted.)
                guard self.manifest.show(id: containerID)?.tracks
                    .contains(where: { $0.trackId == track.trackId && $0.fileName == track.fileName }) == true
                else { continue }
                guard FileManager.default.fileExists(atPath: source.path) else {
                    // Nothing to seal; the track would only stream anyway.
                    // Drop the show rather than keep a half-local entry.
                    self.delete(containerID: containerID)
                    continue
                }
                let ext = (track.fileName as NSString).pathExtension
                let contentType = SealedFile.contentType(forExtension: ext)
                let newName = "\(UUID().uuidString.lowercased()).\(SealedFile.fileExtension)"
                let dest = dir.appendingPathComponent(newName)
                let outcome = await Task.detached(priority: .utility) {
                    Result {
                        try DownloadSealing.seal(plaintext: source, to: dest,
                                                 contentType: contentType, deletingPlaintext: false)
                    }
                }.value
                guard self.libraryEpoch == epoch else {
                    try? FileManager.default.removeItem(at: dest)
                    return
                }
                switch outcome {
                case .success(let bytes):
                    if self.manifest.replaceFile(trackId: track.trackId, containerID: containerID,
                                                 oldFileName: track.fileName, newFileName: newName,
                                                 bytes: bytes, contentType: contentType) {
                        self.saveManifest()
                        try? FileManager.default.removeItem(at: source)
                    } else {
                        try? FileManager.default.removeItem(at: dest)
                    }
                case .failure:
                    try? FileManager.default.removeItem(at: dest)
                    self.delete(containerID: containerID)
                }
            }
        }
    }
}

/// The file work of sealing a download, kept off the main actor.
enum DownloadSealing {
    /// Seal `plaintext` into `destination` with the install's key (created on
    /// first use) and return the sealed file's size. On failure nothing is
    /// left at `destination`. With `deletingPlaintext`, the plaintext is
    /// removed whatever the outcome.
    static func seal(plaintext: URL, to destination: URL, contentType: String,
                     deletingPlaintext: Bool) throws -> Int64 {
        defer {
            if deletingPlaintext { try? FileManager.default.removeItem(at: plaintext) }
        }
        do {
            let key = try DownloadKeyStore.shared.key(creatingIfMissing: true)
            try SealedFile.seal(contentsOf: plaintext, to: destination, key: key,
                                contentType: contentType)
            protect(destination)
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// iOS data protection for a download file or folder. Deliberately
    /// `.completeUntilFirstUserAuthentication`, NOT `.complete`: the
    /// resource loader decrypts lazily, chunk by chunk, as playback reaches
    /// them — and the gapless preload opens the next track's file mid-queue.
    /// Under `.complete` both become unreadable seconds after the phone locks,
    /// so a downloaded show would stop at the first unread chunk on the lock
    /// screen. This matches the key's Keychain class
    /// (`AfterFirstUnlockThisDeviceOnly`). No-op on macOS.
    static func protect(_ url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path)
        #endif
    }
}
