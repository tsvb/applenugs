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
    var showId: String? = nil
}

/// In-memory queue + AVQueuePlayer playback engine. A direct port of the
/// Blazor PlayerService queue semantics, with the JS `<audio>` interop
/// replaced by AVFoundation: the asset carries the Referer/User-Agent
/// headers the nugs CDN requires, so no proxy server is involved.
///
/// Track transitions are gapless: while a track plays, the next queue
/// entry's stream is resolved and parked behind it in the AVQueuePlayer,
/// so the decoder never spins down at set-segue boundaries.
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

    /// True while the player is stalled / spinning up
    /// (`timeControlStatus == .waitingToPlayAtSpecifiedRate`) — playback was
    /// requested but no audio is coming yet. Drives the transport's buffering
    /// indicator and keeps the system Now Playing clock from advancing as if
    /// audio were playing.
    private(set) var isBuffering = false

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
    private let player = AVQueuePlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var timeControlObservation: NSKeyValueObservation?

    /// The item being played (head of the AVQueuePlayer), tracked explicitly
    /// so auto-advance into the preloaded item can be told apart from user
    /// actions and from stale notifications.
    private var currentItem: AVPlayerItem?

    /// The next queue entry, resolved and parked behind the current item so
    /// the transition is gapless.
    private struct Preload {
        var trackUID: UUID
        var picks: [StreamPick]
        var pickIndex: Int
        var item: AVPlayerItem
        var statusObservation: NSKeyValueObservation
        var pick: StreamPick { picks[pickIndex] }
    }
    private var preload: Preload?
    private var preloadTask: Task<Void, Never>?

    /// Position to resume at when a restored queue first starts playing.
    /// Only meaningful for the track that was current at the last save —
    /// any user-driven track change clears it.
    private var pendingSeekPosition: Double?
    private var lastSavedPosition: Double = 0

    /// True while the video player owns system Now Playing + remote commands.
    /// Gates this service's Now Playing writes and remote-command handlers so
    /// audio and video never both drive the system playback UI.
    private var suspendedForVideo = false

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
        // One observer for every item we ever enqueue (only ours exist in
        // this process); the handler filters by identity. Registered once
        // because with gapless transitions items end while a *different*
        // item is already playing.
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                self?.itemDidEnd(note.object as? AVPlayerItem)
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistState() }
        }
        // The periodic time observer is silent while the timebase is stalled, so
        // track buffering via timeControlStatus: it flips to
        // .waitingToPlayAtSpecifiedRate on a stall and back to .playing on
        // recovery, which the periodic tick would miss.
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                guard buffering != self.isBuffering else { return }
                self.isBuffering = buffering
                self.pushNowPlayingInfo()
            }
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
        schedulePreload()  // the playing track may have just gained a successor
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
        schedulePreload()  // index+1 changed — re-park the right successor
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
        schedulePreload()  // no-op unless the parked successor was affected
        persistState()
    }

    func next() {
        guard hasNext else { return }
        // If the next track is already parked behind the current one,
        // promote it — manual skips ride the gapless path too.
        if let p = preload, queue[index + 1].id == p.trackUID,
           currentItem != nil, player.currentItem === currentItem {
            player.advanceToNextItem()
            adoptPreload(p)
            player.play()
            isPlaying = true
        } else {
            startAt(index + 1)
        }
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

    /// Arbiter hook for the video player: pause audio if it is playing and
    /// report whether it was, so the caller can resume it later. Also marks
    /// audio as suspended so it stops writing system Now Playing and stops
    /// responding to remote commands while video owns playback — otherwise both
    /// services write the shared MPNowPlayingInfoCenter and a Control Center
    /// play would resume audio on top of the video.
    @discardableResult
    func pauseForExternalAudio() -> Bool {
        suspendedForVideo = true
        let wasPlaying = isPlaying
        if wasPlaying { pause() }
        return wasPlaying
    }

    /// Counterpart to `pauseForExternalAudio`: the external (video) owner has
    /// relinquished. Clears the suspension — so audio owns Now Playing and the
    /// remote commands again — and optionally resumes playback.
    func endExternalPlayback(resume: Bool) {
        suspendedForVideo = false
        if resume { self.resume() }
    }

    func seek(to seconds: Double) {
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, seconds)
        pushNowPlayingInfo()
    }

    /// Relative seek, shared by the skip buttons, keyboard, and Control Center.
    /// No-op until a duration is known.
    func seek(by delta: Double) {
        guard duration > 0 else { return }
        seek(to: min(max(currentTime + delta, 0), duration))
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
        detachEngine()
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

        // Rebuilding the head item invalidates whatever was parked behind
        // it; the preload is rescheduled below (cheap — picks are cached).
        discardPreload()
        let item = makeItem(url: url)
        observeCurrent(item)
        player.removeAllItems()
        currentItem = item
        player.insert(item, after: nil)
        // The resume seek is deferred to `.readyToPlay` (see applyPendingSeek):
        // seeking now, before the item is ready (status .unknown, empty
        // seekableTimeRanges), is silently dropped, so playback would resume
        // at 0 while the UI shows the saved position.
        player.play()
        isPlaying = true
        loadSpecs(from: item.asset, format: pick.format)
        schedulePreload()
        pushNowPlayingInfo()
    }

    /// The nugs CDN requires the play.nugs.net Referer and a mobile UA —
    /// the whole reason the web port needed a proxy. Natively the asset
    /// just carries them.
    private func makeItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Referer": NugsConstants.playerReferer,
                "User-Agent": NugsConstants.mobileUserAgent,
            ],
        ])
        return AVPlayerItem(asset: asset)
    }

    private func observeCurrent(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, item === self.currentItem else { return }
                switch item.status {
                case .failed:
                    // Signed URL rejected or format undecodable here — fall
                    // through to the next available format for this track,
                    // and drop the cached picks so a retry re-probes.
                    if let track = self.current {
                        Task { await self.client.invalidateStreams(for: track.trackId) }
                    }
                    self.pickIndex += 1
                    self.loadCurrentPick()
                case .readyToPlay:
                    self.applyPendingSeek()
                default:
                    break
                }
            }
        }
    }

    /// Apply a deferred resume seek once the item is ready. A seek issued before
    /// `.readyToPlay` is dropped, so the restore path stashes the saved position
    /// in `pendingSeekPosition` and lands it here (precise, zero-tolerance).
    private func applyPendingSeek() {
        guard let position = pendingSeekPosition else { return }
        pendingSeekPosition = nil
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Fired whenever any of our items plays to the end.
    private func itemDidEnd(_ item: AVPlayerItem?) {
        guard let item, item === currentItem else { return }
        if let p = preload, queue.indices.contains(index + 1),
           queue[index + 1].id == p.trackUID {
            // AVQueuePlayer has already advanced into the preloaded item —
            // the gapless transition. Adopt it and keep the chain going.
            adoptPreload(p)
        } else if hasNext {
            // No preload ready (resolution in flight, or it failed) — fall
            // back to a full load and accept the small gap.
            startAt(index + 1)
        } else {
            ended = true  // queue finished — next enqueue/play-next restarts playback
            isPlaying = false
            pushNowPlayingInfo()
            persistState()
        }
    }

    /// The preloaded item just became the player's head (auto-advance or
    /// manual skip) — promote all the bookkeeping loadCurrentPick would
    /// have set up.
    private func adoptPreload(_ p: Preload) {
        loadGeneration += 1   // invalidate in-flight loads for the old track
        p.statusObservation.invalidate()
        statusObservation?.invalidate()
        preload = nil

        index += 1
        ended = false
        pendingSeekPosition = nil
        currentItem = p.item
        picks = p.picks
        pickIndex = p.pickIndex
        nowPick = p.pick
        playbackError = nil
        currentTime = 0
        duration = 0
        specs = nil

        observeCurrent(p.item)  // re-observe with current-track semantics
        isPlaying = player.timeControlStatus != .paused
        loadSpecs(from: p.item.asset, format: p.pick.format)
        loadArtwork(for: current)
        schedulePreload()
        pushNowPlayingInfo()
        persistState()
    }

    // --- gapless preload --------------------------------------------------------

    /// Resolve the next queue entry and park it behind the current item.
    /// No-op when the right item is already parked.
    private func schedulePreload() {
        if let p = preload, queue.indices.contains(index + 1),
           queue[index + 1].id == p.trackUID {
            return
        }
        preloadTask?.cancel()
        discardPreload()
        guard queue.indices.contains(index + 1), currentItem != nil else { return }
        let track = queue[index + 1]
        let generation = loadGeneration
        preloadTask = Task {
            guard let resolved = try? await client.resolveStreams(trackId: track.trackId),
                  !resolved.isEmpty else { return }
            guard !Task.isCancelled, generation == loadGeneration,
                  queue.indices.contains(index + 1), queue[index + 1].id == track.id
            else { return }
            buildPreload(track: track, picks: resolved, startingAt: 0)
        }
    }

    private func buildPreload(track: QueueTrack, picks: [StreamPick], startingAt pickIdx: Int) {
        guard pickIdx < picks.count else { return }
        guard let url = URL(string: picks[pickIdx].url) else {
            buildPreload(track: track, picks: picks, startingAt: pickIdx + 1)
            return
        }
        let item = makeItem(url: url)
        let observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.preload?.item === item else { return }
                if item.status == .failed {
                    // The parked pick failed before playback — swap in the
                    // next format without disturbing the playing track.
                    Task { await self.client.invalidateStreams(for: track.trackId) }
                    self.discardPreload()
                    self.buildPreload(track: track, picks: picks, startingAt: pickIdx + 1)
                }
            }
        }
        guard player.canInsert(item, after: nil) else { return }
        player.insert(item, after: nil)
        preload = Preload(trackUID: track.id, picks: picks, pickIndex: pickIdx,
                          item: item, statusObservation: observation)
    }

    private func discardPreload() {
        guard let p = preload else { return }
        p.statusObservation.invalidate()
        if player.items().contains(p.item) {
            player.remove(p.item)
        }
        preload = nil
    }

    private func detachEngine() {
        statusObservation?.invalidate()
        statusObservation = nil
        preloadTask?.cancel()
        discardPreload()
        currentItem = nil
        player.removeAllItems()
    }

    private func stopPlayback() {
        loadGeneration += 1
        detachEngine()
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
        // Between an auto-advance and its end-notification the player's head
        // is briefly the preloaded item; skip until bookkeeping catches up.
        guard let item = player.currentItem, item === currentItem else { return }
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
    private func loadSpecs(from asset: AVAsset, format: AudioFormat) {
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
                       artworkPath: $0.artworkPath, showId: $0.showId)
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
                                        artworkPath: $0.artworkPath, showId: $0.showId)
            },
            index: index,
            position: currentTime))
    }

    // --- artwork --------------------------------------------------------------

    /// The cached cover image for the now-playing track, if it has loaded.
    /// Reused by themed now-playing chips and the album-art color extractor —
    /// reading the observed cache means views update when art arrives, with no
    /// extra fetch.
    var nowPlayingImage: NSImage? {
        current?.artworkPath.flatMap { artworkCache[$0] }
    }

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
            guard let self, !self.suspendedForVideo, self.current != nil else { return .noActionableNowPlayingItem }
            self.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, !self.suspendedForVideo, self.current != nil else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, !self.suspendedForVideo, self.current != nil else { return .noActionableNowPlayingItem }
            self.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, !self.suspendedForVideo, self.hasNext else { return .noActionableNowPlayingItem }
            self.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, !self.suspendedForVideo, self.hasPrevious else { return .noActionableNowPlayingItem }
            self.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, !self.suspendedForVideo,
                  let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self, !self.suspendedForVideo, self.current != nil else { return .noActionableNowPlayingItem }
            self.seek(by: -15)
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self, !self.suspendedForVideo, self.current != nil else { return .noActionableNowPlayingItem }
            self.seek(by: 30)
            return .success
        }
    }

    private func pushNowPlayingInfo() {
        // Video owns the system playback UI right now — don't clobber it.
        guard !suspendedForVideo else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard let track = current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        // Report the ACTUAL rate: 0 while buffering/stalled so the system
        // scrubber doesn't advance as if audio were playing. playbackState
        // still reflects intent (the user asked to play).
        let actuallyPlaying = player.timeControlStatus == .playing
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title ?? "Unknown track",
            MPMediaItemPropertyArtist: track.artist ?? "",
            MPMediaItemPropertyAlbumTitle: track.show ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: actuallyPlaying ? 1.0 : 0.0,
        ]
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }
}
