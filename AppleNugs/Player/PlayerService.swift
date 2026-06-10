import AppKit
import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// One track in the queue. Plain data — no logic. `id` is unique per queue
/// entry so the same track can sit in the queue twice.
struct QueueTrack: Identifiable, Hashable {
    let id = UUID()
    let trackId: String
    let title: String?
    let artist: String?
    let show: String?
    var artworkPath: String? = nil
}

/// In-memory queue + AVPlayer playback engine. A direct port of the Blazor
/// PlayerService queue semantics, with the JS `<audio>` interop replaced by
/// AVFoundation: the asset carries the Referer/User-Agent headers the nugs
/// CDN requires, so no proxy server is involved.
@MainActor
@Observable
final class PlayerService {

    // --- queue state (ported 1:1 from the web PlayerService) -----------------

    private(set) var queue: [QueueTrack] = []
    private(set) var index = 0

    /// True once the last track has played to the end and the player is
    /// sitting idle — lets enqueue/play-next know to start playback rather
    /// than silently appending behind a finished queue.
    private var ended = false

    var current: QueueTrack? {
        queue.indices.contains(index) ? queue[index] : nil
    }
    var hasPrevious: Bool { index > 0 }
    var hasNext: Bool { index < queue.count - 1 }

    // --- live playback state (fed by AVPlayer observers) ----------------------

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var bufferedAhead: Double = 0
    private(set) var nowPick: StreamPick?
    private(set) var specs: AudioSpecs?
    private(set) var playbackError: String?

    var volume: Float {
        didSet {
            player.volume = volume
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
        }
    }

    struct AudioSpecs: Equatable {
        var sampleRate: Double
        var channels: Int
        var bitDepth: Int?
    }

    // --- internals ------------------------------------------------------------

    private static let volumeKey = "playerVolume"

    private let client: NugsClient
    private let stateStore = PlaybackStateStore()
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    /// Position to resume at when a restored queue first starts playing.
    /// Only meaningful for the track that was current at the last save —
    /// any user-driven track change clears it.
    private var pendingSeekPosition: Double?
    private var lastSavedPosition: Double = 0

    /// Cover art for the system Now Playing widget, keyed by image path.
    private var artworkCache: [String: NSImage] = [:]
    private var artworkTask: Task<Void, Never>?
    private var nowPlayingArtwork: MPMediaItemArtwork?

    /// Streams resolved for the current track, best-first. On AVPlayerItem
    /// failure we advance to the next pick — e.g. if a FLAC stream won't
    /// play, retry with AAC or HLS.
    private var picks: [StreamPick] = []
    private var pickIndex = 0

    /// Bumped on every track change so stale async loads can no-op.
    private var loadGeneration = 0

    init(client: NugsClient) {
        self.client = client
        let saved = UserDefaults.standard.object(forKey: Self.volumeKey) as? Float
        volume = saved ?? 1.0
        player.volume = volume

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        registerRemoteCommands()
        restorePersistedState()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistState() }
        }
    }

    // --- queue operations -------------------------------------------------------

    /// Replace the queue with a contextual track list and start at an index.
    func play(_ tracks: [QueueTrack], startAt startIndex: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        startAt(min(max(startIndex, 0), queue.count - 1))
    }

    /// Append to the end of the queue. Returns true when the caller should
    /// show a confirmation toast (i.e. playback was untouched); when nothing
    /// is playing the visible now-playing change is feedback enough.
    @discardableResult
    func enqueue(_ tracks: [QueueTrack]) -> Bool {
        guard !tracks.isEmpty else { return false }
        let startHere = current == nil || ended
        let firstNew = queue.count
        queue.append(contentsOf: tracks)
        if startHere {
            startAt(firstNew)
            return false
        }
        persistState()
        return true
    }

    /// Insert immediately after the current track. Same toast contract as
    /// `enqueue`.
    @discardableResult
    func playNext(_ tracks: [QueueTrack]) -> Bool {
        guard !tracks.isEmpty else { return false }
        if current == nil || ended {
            let firstNew = queue.count
            queue.append(contentsOf: tracks)
            startAt(firstNew)
            return false
        }
        queue.insert(contentsOf: tracks, at: index + 1)
        persistState()
        return true
    }

    /// Jump straight to a track already in the queue and play it.
    func jump(to i: Int) {
        guard queue.indices.contains(i), i != index else { return }
        startAt(i)
    }

    /// Remove a track. Playback continues uninterrupted unless the playing
    /// track itself is removed, in which case whatever slides into its slot
    /// starts (or playback stops if the queue empties).
    func remove(at i: Int) {
        guard queue.indices.contains(i) else { return }
        let wasCurrent = i == index
        queue.remove(at: i)

        if queue.isEmpty {
            index = 0
            ended = false
            stopPlayback()
        } else if i < index {
            index -= 1            // keep the cursor on the same track
        } else if wasCurrent {
            index = min(index, queue.count - 1)
            ended = false
            pendingSeekPosition = nil
            startCurrent()        // play whatever now occupies the slot
        }
        persistState()
    }

    func next() {
        guard hasNext else { return }
        startAt(index + 1)
    }

    func previous() {
        guard hasPrevious else { return }
        startAt(index - 1)
    }

    func clear() {
        queue = []
        index = 0
        ended = false
        stopPlayback()
        persistState()
    }

    // --- transport -----------------------------------------------------------

    func togglePlayPause() {
        guard player.currentItem != nil else {
            // A restored (or finished) queue with nothing loaded yet —
            // (re)start the current track; pendingSeekPosition resumes
            // where the last session left off.
            if current != nil { startCurrent() }
            return
        }
        if player.timeControlStatus == .paused {
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
        pushNowPlayingInfo()
    }

    func resume() {
        guard player.currentItem != nil else {
            if current != nil { startCurrent() }
            return
        }
        player.play()
        isPlaying = true
        pushNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        pushNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, seconds)
        pushNowPlayingInfo()
    }

    // --- playback engine --------------------------------------------------------

    private func startAt(_ i: Int) {
        pendingSeekPosition = nil
        index = i
        ended = false
        startCurrent()
        persistState()
    }

    private func startCurrent() {
        loadGeneration += 1
        let generation = loadGeneration
        detachItem()
        currentTime = pendingSeekPosition ?? 0
        duration = 0
        bufferedAhead = 0
        nowPick = nil
        specs = nil
        playbackError = nil

        guard let track = current else {
            loadArtwork(for: nil)
            pushNowPlayingInfo()
            return
        }
        loadArtwork(for: track)
        pushNowPlayingInfo()

        Task {
            do {
                let resolved = try await client.resolveStreams(trackId: track.trackId)
                guard generation == loadGeneration else { return }
                guard !resolved.isEmpty else {
                    playbackError = "nugs has no stream for this track."
                    return
                }
                picks = resolved
                pickIndex = 0
                loadCurrentPick()
            } catch {
                guard generation == loadGeneration else { return }
                playbackError = error.localizedDescription
            }
        }
    }

    private func loadCurrentPick() {
        guard pickIndex < picks.count else {
            playbackError = "Every available stream format failed to play."
            isPlaying = false
            return
        }
        let pick = picks[pickIndex]
        guard let url = URL(string: pick.url) else {
            pickIndex += 1
            loadCurrentPick()
            return
        }
        nowPick = pick

        // The nugs CDN requires the play.nugs.net Referer and a mobile UA —
        // the whole reason the web port needed a proxy. Natively the asset
        // just carries them.
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Referer": NugsConstants.playerReferer,
                "User-Agent": NugsConstants.mobileUserAgent,
            ],
        ])
        let item = AVPlayerItem(asset: asset)
        observe(item)
        player.replaceCurrentItem(with: item)
        if let position = pendingSeekPosition {
            pendingSeekPosition = nil
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
        loadSpecs(from: asset, format: pick.format)
        pushNowPlayingInfo()
    }

    private func observe(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, item === self.player.currentItem else { return }
                if item.status == .failed {
                    // Signed URL rejected or format undecodable here — fall
                    // through to the next available format for this track,
                    // and drop the cached picks so a retry re-probes.
                    if let track = self.current {
                        self.client.invalidateStreams(for: track.trackId)
                    }
                    self.pickIndex += 1
                    self.loadCurrentPick()
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnded() }
        }
    }

    /// Fired when the current item plays to the end.
    private func handleEnded() {
        if hasNext {
            next()
        } else {
            ended = true  // queue finished — next enqueue/play-next restarts playback
            isPlaying = false
            pushNowPlayingInfo()
            persistState()
        }
    }

    private func detachItem() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.replaceCurrentItem(with: nil)
    }

    private func stopPlayback() {
        loadGeneration += 1
        detachItem()
        loadArtwork(for: nil)
        isPlaying = false
        currentTime = 0
        duration = 0
        bufferedAhead = 0
        nowPick = nil
        specs = nil
        playbackError = nil
        pushNowPlayingInfo()
    }

    /// ~4x/sec runtime snapshot, the AVFoundation analog of the web port's
    /// JS-pushed PlaybackStatus.
    private func tick() {
        guard let item = player.currentItem else { return }
        let t = player.currentTime()
        currentTime = t.seconds.isFinite ? max(0, t.seconds) : 0
        let d = item.duration.seconds
        duration = d.isFinite ? d : 0
        isPlaying = player.timeControlStatus != .paused

        bufferedAhead = item.loadedTimeRanges
            .map(\.timeRangeValue)
            .filter { $0.start <= t && t <= $0.end }
            .map { ($0.end - t).seconds }
            .max() ?? 0

        // Keep the on-disk position roughly current without writing 4x/sec.
        if abs(currentTime - lastSavedPosition) >= 5 {
            persistState()
        }

        pushNowPlayingInfo()
    }

    /// Exact specs from the decoder once the asset is readable — replaces the
    /// web port's hand-rolled FLAC/MP4 header parsing.
    private func loadSpecs(from asset: AVURLAsset, format: AudioFormat) {
        let generation = loadGeneration
        Task {
            guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
                  let descriptions = try? await tracks.first?.load(.formatDescriptions),
                  let description = descriptions.first
            else { return }
            guard generation == loadGeneration else { return }
            guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
            else { return }
            specs = AudioSpecs(
                sampleRate: asbd.mSampleRate,
                channels: Int(asbd.mChannelsPerFrame),
                // Compressed formats report 0 bits/channel; fall back to the
                // bit depth implied by the format tier.
                bitDepth: asbd.mBitsPerChannel > 0 ? Int(asbd.mBitsPerChannel) : format.impliedBitDepth)
        }
    }

    // --- persistence -----------------------------------------------------------

    /// Restore the last session's queue at launch, paused: the transport and
    /// dashboard show where you left off, and the first play re-resolves the
    /// stream and seeks back to the saved position.
    private func restorePersistedState() {
        guard let saved = stateStore.load(), !saved.tracks.isEmpty else { return }
        queue = saved.tracks.map {
            QueueTrack(trackId: $0.trackId, title: $0.title,
                       artist: $0.artist, show: $0.show,
                       artworkPath: $0.artworkPath)
        }
        index = min(max(saved.index, 0), queue.count - 1)
        if saved.position > 1 {
            pendingSeekPosition = saved.position
            currentTime = saved.position
        }
        pushNowPlayingInfo()
    }

    private func persistState() {
        guard !queue.isEmpty else {
            stateStore.clear()
            lastSavedPosition = 0
            return
        }
        lastSavedPosition = currentTime
        stateStore.save(PersistedPlayback(
            tracks: queue.map {
                PersistedPlayback.Track(trackId: $0.trackId, title: $0.title,
                                        artist: $0.artist, show: $0.show,
                                        artworkPath: $0.artworkPath)
            },
            index: index,
            position: currentTime))
    }

    // --- artwork --------------------------------------------------------------

    private func loadArtwork(for track: QueueTrack?) {
        artworkTask?.cancel()
        nowPlayingArtwork = nil
        guard let path = track?.artworkPath else { return }
        if let cached = artworkCache[path] {
            setNowPlayingArtwork(cached)
            return
        }
        guard let url = NugsConstants.imageURL(path: path, height: 600) else { return }
        artworkTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data),
                  !Task.isCancelled
            else { return }
            // Tiny bounded cache — one show's worth of art is one entry.
            if artworkCache.count > 8 { artworkCache.removeAll() }
            artworkCache[path] = image
            guard current?.artworkPath == path else { return }
            setNowPlayingArtwork(image)
        }
    }

    private func setNowPlayingArtwork(_ image: NSImage) {
        nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        pushNowPlayingInfo()
    }

    // --- system media integration --------------------------------------------------

    /// Media keys / Control Center / AirPods controls.
    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.current != nil else { return .noActionableNowPlayingItem }
            self.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.current != nil else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.current != nil else { return .noActionableNowPlayingItem }
            self.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.hasNext else { return .noActionableNowPlayingItem }
            self.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.hasPrevious else { return .noActionableNowPlayingItem }
            self.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }
    }

    private func pushNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title ?? "Unknown track",
            MPMediaItemPropertyArtist: track.artist ?? "",
            MPMediaItemPropertyAlbumTitle: track.show ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }
}
