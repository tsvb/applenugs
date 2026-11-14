#if os(macOS)
import AppKit
#else
import AVFAudio
import UIKit
#endif
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

    /// Offline library, injected by AppModel. When a track has a local file,
    /// it becomes the (only) initial pick; stream resolution is the fallback.
    var downloads: DownloadStore?
    /// True while the current picks are the local file — lets the failure
    /// path fall back to network resolution instead of giving up.
    private var usingLocalPick = false
    /// Latched when the current track's download failed to play, so the
    /// stream fallback never hands playback back to the same broken file.
    private var localPickFailed = false

    // --- listening stats ------------------------------------------------------

    /// All-time listening tallies, injected by AppModel. Optional so the player
    /// still works standalone (and under the UITest harness, where nothing is
    /// injected and nothing is credited).
    @ObservationIgnored var listening: ListeningStatsStore?

    /// The per-track accumulator.
    ///
    /// `@ObservationIgnored` is LOAD-BEARING, not tidiness: this is mutated from
    /// the ~4Hz tick, and `@Observable` notifies on every set without comparing
    /// values, so leaving it tracked would wake observers four times a second
    /// for state no view ever reads.
    @ObservationIgnored private var credit = ListeningCredit()

    /// The artist the accumulator's seconds belong to.
    ///
    /// Held separately because a track change flushes the FINISHED track's
    /// earnings AFTER `index` has already moved on — `current?.artist` is the
    /// wrong answer by then.
    @ObservationIgnored private var creditedArtist: String?

    /// Playhead position at the previous sample (tick or settle), so the
    /// policy gets a delta.
    @ObservationIgnored private var lastCreditPosition: Double = 0

    /// When that sample was taken (monotonic `systemUptime`). A settle credits
    /// at most the real time since — see `ListeningCredit.span`.
    @ObservationIgnored private var lastCreditSampleAt = ProcessInfo.processInfo.systemUptime

    private let player = AVQueuePlayer()
    /// The ~4Hz `tick()` observer. Installed only while the app is in the
    /// foreground — see `appDidEnterBackground()`.
    private var timeObserver: Any?
    /// While backgrounded, instead: a once-a-minute observer that only keeps
    /// the saved resume position roughly current.
    private var backgroundPersistObserver: Any?
    private var inBackground = false
    #if DEBUG
    /// Shown in the DEBUG Network Probe: `tick()` calls made while backgrounded
    /// (should stay 0), and how many background periods that covers.
    @ObservationIgnored private(set) var debugBackgroundTicks = 0
    @ObservationIgnored private(set) var debugBackgroundEntries = 0
    #endif
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
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

    /// Set by the video player: asks it to step aside (pause and hand Now
    /// Playing back) when the listener deliberately starts audio while a video
    /// owns playback. Deliberate starts are the public transport entry points
    /// (see `takePlaybackFromVideo`); automatic ones — a resolve or retry
    /// finishing, a removed track's slot refilling — never call it, and
    /// `startPlayback()` refuses them while suspended, so audio can't start
    /// underneath a playing video.
    var yieldExternalOwner: (@MainActor () -> Void)?

    /// True only between an audio-session interruption pausing playback and
    /// that interruption ending — the gate that keeps `.shouldResume` from
    /// restarting audio the user paused themselves (iOS only; inert on macOS).
    private var pausedByInterruption = false
    /// When the `timeControlStatus` KVO last saw playback stop on its own
    /// (not via pause()) — lets an interruption that the KVO beat to the main
    /// queue still count as having paused us.
    @ObservationIgnored private var externalPauseAt: Date?

    /// Cover art for the system Now Playing widget, keyed by image path.
    private var artworkCache: [String: PlatformImage] = [:]
    private var artworkTask: Task<Void, Never>?
    private var nowPlayingArtwork: MPMediaItemArtwork?

    /// Streams resolved for the current track. Normally ONE pick (the client
    /// resolves a tier at a time and stops at the first usable one); a list
    /// only when no tier had a format the player trusts. On AVPlayerItem
    /// failure `currentItemFailed` backs off and moves on — the next pick, or
    /// a fresh resolve that skips every tier seen failing (`failedTiers`).
    private var picks: [StreamPick] = []
    private var pickIndex = 0
    /// Tiers whose stream failed in AVPlayer for the current track, and how
    /// many network failures it has had — both reset on every track change.
    private var failedTiers: Set<Int> = []
    private var streamFailures = 0
    /// The pending backed-off retry, if any.
    private var retryTask: Task<Void, Never>?

    /// Bumped on every track change so stale async loads can no-op.
    private var loadGeneration = 0

    init(client: NugsClient) {
        self.client = client
        let saved = UserDefaults.standard.object(forKey: Self.volumeKey) as? Float
        volume = saved ?? 1.0
        player.volume = volume

        installTickObserver()
        registerRemoteCommands()
        restorePersistedState()
        // One observer for every item we ever enqueue (only ours exist in
        // this process); the handler filters by identity. Registered once
        // because with gapless transitions items end while a *different*
        // item is already playing.
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil, queue: .main) { [weak self] note in
            // Send only the ended item's identity across the actor hop — a
            // `Notification` (and the `AVPlayerItem` it carries) isn't Sendable,
            // and `itemDidEnd` only needs identity to match the current item.
            let endedID = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                self?.itemDidEnd(endedID)
            }
        }
        #if os(macOS)
        let terminateNotification = NSApplication.willTerminateNotification
        #else
        // Best-effort only on iOS — the scene-phase observer in the app entry
        // is the reliable persistence trigger there.
        let terminateNotification = UIApplication.willTerminateNotification
        #endif
        terminationObserver = NotificationCenter.default.addObserver(
            forName: terminateNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persistNow() }
        }
        #if os(iOS)
        // Phone call / Siri / another app taking the session: pause, and
        // resume only when (a) the system says the interruption ended
        // resumably AND (b) it was this interruption that paused us.
        // `.shouldResume` alone only reflects the interrupting app's
        // deactivation mode — acting on it unconditionally would restart
        // audio the user had explicitly paused (or play under a video).
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init) ?? []
            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .began:
                    // Best-effort "were we playing": the system pauses the
                    // player before delivering the notification, and tick()
                    // may already have observed that — check both signals.
                    // The timeControlStatus KVO sees that system pause too,
                    // and usually lands FIRST (it flips isPlaying off), so a
                    // flip in the last 2 s counts as "was playing". A
                    // timestamp, not a flag: an old headphone-unplug pause
                    // must not make a later call resume audio the user left
                    // stopped.
                    let flippedJustNow = self.externalPauseAt
                        .map { Date().timeIntervalSince($0) < 2 } ?? false
                    let wasPlaying = self.isPlaying || self.player.rate != 0 || flippedJustNow
                    if wasPlaying && !self.suspendedForVideo {
                        self.pausedByInterruption = true
                        self.pause()
                    }
                case .ended:
                    if self.pausedByInterruption, !self.suspendedForVideo,
                       options.contains(.shouldResume) {
                        self.resume()
                    }
                    self.pausedByInterruption = false
                default:
                    break
                }
            }
        }
        #endif
        // The periodic time observer is silent while the timebase is stalled, so
        // track buffering via timeControlStatus: it flips to
        // .waitingToPlayAtSpecifiedRate on a stall and back to .playing on
        // recovery, which the periodic tick would miss.
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let status = player.timeControlStatus
                    var changed = false
                    let buffering = status == .waitingToPlayAtSpecifiedRate
                    if buffering != self.isBuffering {
                        self.isBuffering = buffering
                        changed = true
                    }
                    // tick()'s play/pause rule, with tick()'s head-item guard.
                    // This is what notices an external flip (a headphone
                    // unplug, a route change) while backgrounded, when no tick
                    // runs — and pushes it to the lock screen.
                    if let item = player.currentItem, item === self.currentItem {
                        let playing = status != .paused
                        if playing != self.isPlaying {
                            if !playing { self.externalPauseAt = Date() }
                            // Listening stats: an external pause ends a span
                            // (settle what was heard), an external resume starts
                            // one (see rebaseListening).
                            if playing { self.rebaseListening() } else { self.settleListening() }
                            self.isPlaying = playing
                            changed = true
                        }
                    }
                    if changed { self.pushNowPlayingInfo() }
                }
            }
        }
    }

    // --- foreground / background --------------------------------------------------

    /// The app went to the background (iOS scene phase; screen locked, or
    /// another app in front). Nothing on screen reads the ~4Hz snapshot there,
    /// so the tick observer comes off — music playing behind a locked screen
    /// costs no main-thread wake-ups beyond what playback itself needs:
    ///   - lock screen / Control Center extrapolate from one (elapsed, rate)
    ///     sample; every push reads the elapsed time LIVE from the player
    ///     (`livePosition`) and duration is discovered at `.readyToPlay`, so
    ///     neither depends on the tick;
    ///   - track ends arrive as `didPlayToEndTime`, and AVQueuePlayer prepares
    ///     the parked successor on its own timebase (~6–9 s before the end,
    ///     measured — `scripts/sealed-footprint`), so gapless auto-advance
    ///     needs nothing from us between the notifications;
    ///   - external play/pause flips arrive via the `timeControlStatus` KVO;
    ///   - remote commands are callbacks.
    /// What the tick also did — keep the saved resume position current — moves
    /// to a once-a-minute observer, plus a save on every pause and track change.
    /// Idempotent.
    func appDidEnterBackground() {
        guard !inBackground else { return }
        inBackground = true
        #if DEBUG
        debugBackgroundEntries += 1
        #endif
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        backgroundPersistObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 60, preferredTimescale: 1), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.backgroundWake() }
        }
        commitListening()
        persistState()
    }

    /// Back in front (scene phase `.active`): reinstate the tick and refresh
    /// the snapshot at once so nothing shows the position from when the app
    /// left. Idempotent — `.active` also arrives at launch.
    func appWillEnterForeground() {
        guard inBackground else { return }
        inBackground = false
        if let backgroundPersistObserver { player.removeTimeObserver(backgroundPersistObserver) }
        backgroundPersistObserver = nil
        // Before the tick returns: its first delta would span the whole
        // background stretch, and the tick's 1s clamp would discard it.
        settleListening()
        installTickObserver()
        tick()
    }

    private func installTickObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Where playback actually is, read from the player rather than the
    /// tick-fed `currentTime` (stale while backgrounded). A pending resume
    /// seek wins: until the item is ready the player still reports 0.
    private var livePosition: Double {
        if let pendingSeekPosition { return pendingSeekPosition }
        guard let item = currentItem, player.currentItem === item else { return currentTime }
        let t = player.currentTime().seconds
        return t.isFinite ? max(0, t) : currentTime
    }

    /// The once-a-minute background wake — the ONLY periodic work while
    /// backgrounded. Listening stats ride it rather than adding a wake of their
    /// own: settle the minute just played, commit if due (so a long locked-screen
    /// listen writes listening.json at most once a minute), then the resume save.
    private func backgroundWake() {
        settleListening()
        if credit.isCommitDue { flushListening() }
        persistIfMoved()
    }

    private func persistIfMoved() {
        if abs(livePosition - lastSavedPosition) >= 5 { persistState() }
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
            // Settle while the head is still this track: once it advances,
            // its playhead can no longer be read.
            settleListening()
            takePlaybackFromVideo()
            player.advanceToNextItem()
            adoptPreload(p)
            isPlaying = startPlayback()
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

    /// The single choke point for starting the AVQueuePlayer: on iOS the
    /// audio session must be (re)activated before playback so background
    /// audio and Now Playing ownership are granted to this app. Returns
    /// whether playback actually started, so callers keep `isPlaying` (and
    /// therefore Control Center) honest when activation fails — e.g. during
    /// an ongoing call.
    @discardableResult
    private func startPlayback() -> Bool {
        // A video owns playback: an automatic start (a stream resolve or retry
        // landing after the video took over) must not play underneath it. The
        // item stays loaded, so the video's hand-back can resume it. Deliberate
        // starts called `takePlaybackFromVideo()` first and are never blocked.
        guard !suspendedForVideo else { return false }
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            playbackError = "Audio session unavailable: \(error.localizedDescription)"
            return false
        }
        #endif
        player.play()
        return true
    }

    func togglePlayPause() {
        guard player.currentItem != nil else {
            // A restored (or finished) queue with nothing loaded yet —
            // (re)start the current track; pendingSeekPosition resumes
            // where the last session left off.
            if current != nil {
                takePlaybackFromVideo()
                startCurrent()
            }
            return
        }
        if player.timeControlStatus == .paused {
            takePlaybackFromVideo()
            rebaseListening()
            isPlaying = startPlayback()
        } else {
            player.pause()
            isPlaying = false
            commitListening()
            persistState()  // as in pause()
        }
        pushNowPlayingInfo()
    }

    func resume() {
        takePlaybackFromVideo()
        guard player.currentItem != nil else {
            if current != nil { startCurrent() }
            return
        }
        if !isPlaying { rebaseListening() }
        isPlaying = startPlayback()
        pushNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        commitListening()
        pushNowPlayingInfo()
        // A paused position is the one to resume from — and while backgrounded
        // no tick is around to save it.
        persistState()
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
        // Video now owns playback — a pending interruption-resume must not
        // fire underneath it once the interruption ends.
        pausedByInterruption = false
        // Ask the engine too, not just `isPlaying`: the flag can trail the
        // player (a head item we haven't adopted yet), and a stale false must
        // neither leave audio running under the video nor forget to resume it.
        let wasPlaying = isPlaying || player.rate != 0
        if wasPlaying { pause() }
        player.pause()
        return wasPlaying
    }

    /// The listener deliberately started audio: if a video owns playback, ask
    /// it to pause and hand playback back (without resuming us — we're about
    /// to start). Clears the suspension so the start goes through.
    private func takePlaybackFromVideo() {
        guard suspendedForVideo else { return }
        yieldExternalOwner?()
        // The video's hand-back clears this; make sure even without a hook.
        suspendedForVideo = false
    }

    /// Counterpart to `pauseForExternalAudio`: the external (video) owner has
    /// relinquished. Clears the suspension — so audio owns Now Playing and the
    /// remote commands again — and optionally resumes playback.
    func endExternalPlayback(resume: Bool) {
        suspendedForVideo = false
        if resume { self.resume() }
    }

    func seek(to seconds: Double) {
        // Credit what was listened to up to here, then move the baseline with
        // the playhead — a scrub forward (say from the lock screen, where no
        // tick clamps it) must earn nothing it skipped.
        settleListening()
        lastCreditPosition = max(0, seconds)
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, seconds)
        // The target, not `livePosition`: the player may still report the
        // pre-seek time until the seek lands.
        pushNowPlayingInfo(elapsed: currentTime)
    }

    /// Relative seek, shared by the skip buttons, keyboard, and Control Center.
    /// No-op until a duration is known.
    func seek(by delta: Double) {
        guard duration > 0 else { return }
        // livePosition, not currentTime: the lock screen's skip buttons fire
        // while backgrounded, where the tick-fed currentTime is stale.
        seek(to: min(max(livePosition + delta, 0), duration))
    }

    // --- playback engine --------------------------------------------------------

    /// `deliberate`: the listener chose this track (play, enqueue or play-next
    /// into an idle queue, jump, next, previous), so audio takes playback back
    /// from a video. The one automatic caller — a track ending with no
    /// successor preloaded — passes false and stays silent under a video.
    private func startAt(_ i: Int, deliberate: Bool = true) {
        if deliberate { takePlaybackFromVideo() }
        pendingSeekPosition = nil
        index = i
        ended = false
        startCurrent()
        persistState()
    }

    private func startCurrent() {
        rotateListening()
        loadGeneration += 1
        let generation = loadGeneration
        detachEngine()
        currentTime = pendingSeekPosition ?? 0
        duration = 0
        bufferedAhead = 0
        nowPick = nil
        specs = nil
        playbackError = nil
        failedTiers = []
        streamFailures = 0
        localPickFailed = false

        guard let track = current else {
            loadArtwork(for: nil)
            pushNowPlayingInfo()
            return
        }
        loadArtwork(for: track)
        pushNowPlayingInfo()

        // Downloaded tracks play from disk with no network round-trip; the
        // failure path in loadCurrentPick falls back to stream resolution.
        // A download past its offline window (`.needsVerification`) streams
        // instead. If the resolve refreshed the access token, the client
        // rechecked the subscription on the way; when that renewed the
        // window, resolveNetworkStreams switches back to the download.
        if case .available(let local) = downloads?.localPlayback(trackId: track.trackId) {
            playLocal(local)
            return
        }
        usingLocalPick = false
        resolveNetworkStreams(for: track, generation: generation)
    }

    private func playLocal(_ pick: StreamPick) {
        usingLocalPick = true
        picks = [pick]
        pickIndex = 0
        loadCurrentPick()
    }

    /// True when the track has a download that's only waiting on a trip
    /// online — so a network failure reads "Go online to keep listening
    /// offline" instead of a raw transport error.
    private func downloadNeedsVerification(_ track: QueueTrack) -> Bool {
        downloads?.localPlayback(trackId: track.trackId) == .needsVerification
    }

    private func resolveNetworkStreams(for track: QueueTrack, generation: Int,
                                       skipping: Set<Int> = []) {
        Task {
            do {
                let resolved = try await client.resolveStreams(trackId: track.trackId,
                                                               skipping: skipping)
                guard generation == loadGeneration else { return }
                // If the resolve's token refresh rechecked the subscription
                // and renewed the window, a download that was waiting on it
                // plays after all (skipped when we're here because the local
                // file itself failed).
                if skipping.isEmpty, !localPickFailed,
                   case .available(let local) = downloads?.localPlayback(trackId: track.trackId) {
                    playLocal(local)
                    return
                }
                guard !resolved.isEmpty else {
                    if downloadNeedsVerification(track) {
                        playbackError = OfflineAccessPolicy.expiredMessage
                    } else if skipping.isEmpty {
                        playbackError = "nugs has no stream for this track."
                    } else {
                        playbackError = "Every available stream format failed to play."
                        isPlaying = false
                    }
                    return
                }
                picks = resolved
                pickIndex = 0
                loadCurrentPick()
            } catch {
                guard generation == loadGeneration else { return }
                playbackError = downloadNeedsVerification(track)
                    ? OfflineAccessPolicy.expiredMessage : error.localizedDescription
            }
        }
    }

    private func loadCurrentPick() {
        guard pickIndex < picks.count else {
            // A dead local file (corrupt, half-written) shouldn't strand the
            // track — fall back to streaming as if it weren't downloaded.
            if usingLocalPick, let track = current {
                usingLocalPick = false
                localPickFailed = true
                resolveNetworkStreams(for: track, generation: loadGeneration)
                return
            }
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
        isPlaying = startPlayback()
        loadSpecs(from: item.asset, format: pick.format)
        schedulePreload()
        pushNowPlayingInfo()
    }

    /// The asset carries the app's CDN headers (`NugsIdentity.current`: the
    /// honest UA, no Referer — the Phase B probe showed the CDN serves
    /// without one).
    /// A `yeti-local://` pick is a sealed download: its asset decrypts through
    /// its own resource loader and needs no headers.
    private func makeItem(url: URL) -> AVPlayerItem {
        if url.scheme == SealedFile.urlScheme, let asset = downloads?.makeAsset(for: url) {
            return AVPlayerItem(asset: asset)
        }
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": NugsIdentity.current.cdnHeaders,
        ])
        return AVPlayerItem(asset: asset)
    }

    private func observeCurrent(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            // KVO fires on an arbitrary AVFoundation queue, so hop to main. The
            // inner closure captures `self` weakly itself (rather than closing
            // over the outer closure's capture, which `@Sendable` checking flags)
            // and `assumeIsolated` supplies the main-actor isolation it lands on.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, item === self.currentItem else { return }
                    switch item.status {
                    case .failed:
                        self.currentItemFailed()
                    case .readyToPlay:
                        self.discoverDuration(of: item)
                        self.applyPendingSeek()
                    default:
                        break
                    }
                }
            }
        }
    }

    /// The head item failed: a signed URL rejected, or a format AVPlayer can't
    /// decode here — the two look the same, so the track's cached tier answers
    /// are dropped either way. A local file falls straight back to streaming
    /// (no network was involved). Otherwise wait per `PlaybackRetryPolicy`
    /// (0.5s, 1s, 2s, then give up), and move on: the next pick if a
    /// last-resort list still has one, else a fresh resolve that skips every
    /// tier that has failed for this track — re-asking it would hand back the
    /// same failing stream.
    private func currentItemFailed() {
        guard let track = current else { return }
        if usingLocalPick {
            pickIndex += 1
            loadCurrentPick()
            return
        }
        if picks.indices.contains(pickIndex) { failedTiers.insert(picks[pickIndex].platformId) }
        streamFailures += 1
        guard let delay = PlaybackRetryPolicy.delay(afterFailure: streamFailures) else {
            Task { await client.invalidateStreams(for: track.trackId) }
            playbackError = "Every available stream format failed to play."
            isPlaying = false
            return
        }
        let generation = loadGeneration
        let skipping = failedTiers
        let nextIndex = pickIndex + 1
        retryTask?.cancel()
        retryTask = Task {
            await client.invalidateStreams(for: track.trackId)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, generation == loadGeneration else { return }
            if nextIndex < picks.count {
                pickIndex = nextIndex
                loadCurrentPick()
            } else {
                resolveNetworkStreams(for: track, generation: generation, skipping: skipping)
            }
        }
    }

    /// Duration as soon as the item knows it, for the lock screen's scrubber —
    /// not left to tick(), which doesn't run in the background. Same source
    /// (`item.duration`) as tick, so the two never disagree.
    private func discoverDuration(of item: AVPlayerItem) {
        let d = item.duration.seconds
        let known = d.isFinite ? d : 0
        guard known != duration else { return }
        duration = known
        pushNowPlayingInfo()
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
    private func itemDidEnd(_ itemID: ObjectIdentifier?) {
        guard let itemID, let currentItem, itemID == ObjectIdentifier(currentItem) else { return }
        // It played to its end. Settle there explicitly: on a gapless hand-off
        // the player's head is already the successor (and at a queue's end it
        // has none), so the playhead can no longer be read for this track.
        settleListening(at: duration > 0 ? duration : nil)
        if let p = preload, queue.indices.contains(index + 1),
           queue[index + 1].id == p.trackUID {
            // AVQueuePlayer has already advanced into the preloaded item —
            // the gapless transition. Adopt it and keep the chain going.
            adoptPreload(p)
        } else if hasNext {
            // No preload ready (resolution in flight, or it failed) — fall
            // back to a full load and accept the small gap.
            startAt(index + 1, deliberate: false)
        } else {
            ended = true  // queue finished — next enqueue/play-next restarts playback
            commitListening()
            isPlaying = false
            // The player has dropped the item, so livePosition falls back to
            // currentTime — stale if this happened while backgrounded.
            if duration > 0 { currentTime = duration }
            pushNowPlayingInfo()
            persistState()
        }
    }

    /// The preloaded item just became the player's head (auto-advance or
    /// manual skip) — promote all the bookkeeping loadCurrentPick would
    /// have set up.
    private func adoptPreload(_ p: Preload) {
        loadGeneration += 1   // invalidate in-flight loads for the old track
        retryTask?.cancel()
        retryTask = nil
        failedTiers = []
        streamFailures = 0
        p.statusObservation.invalidate()
        statusObservation?.invalidate()
        preload = nil

        index += 1
        // Clear BEFORE rotating: rotateListening anchors the new visit at
        // pendingSeekPosition, and a restored track's unapplied resume offset
        // is not where its successor starts.
        pendingSeekPosition = nil
        rotateListening()
        ended = false
        currentItem = p.item
        picks = p.picks
        pickIndex = p.pickIndex
        nowPick = p.pick
        // Keep the local/network flag honest across gapless transitions so
        // a failing local file still falls back to streaming.
        usingLocalPick = p.pick.isLocalDownload
        localPickFailed = false
        playbackError = nil
        currentTime = 0
        specs = nil

        observeCurrent(p.item)  // re-observe with current-track semantics
        // Usually already known: AVQueuePlayer readied the item before handing
        // over. Read it here because the status KVO only reports CHANGES — an
        // item that's already ready never fires it — and in the background no
        // tick would discover it either. Read AFTER observing, so an item that
        // turns ready in between is caught by one or the other.
        let adoptedDuration = p.item.duration.seconds
        duration = adoptedDuration.isFinite ? adoptedDuration : 0
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
            // A downloaded next track preloads from disk — offline gapless
            // works and no cellular data is spent on an owned file.
            // One that's waiting on a subscription check resolves a stream like
            // any other track — and if that renewed the window (via a token
            // refresh's subscription recheck), takes the download after all.
            let picks: [StreamPick]
            if case .available(let local) = downloads?.localPlayback(trackId: track.trackId) {
                picks = [local]
            } else {
                let resolved = try? await client.resolveStreams(trackId: track.trackId)
                if case .available(let local) = downloads?.localPlayback(trackId: track.trackId) {
                    picks = [local]
                } else {
                    guard let resolved, !resolved.isEmpty else { return }
                    picks = resolved
                }
            }
            guard !Task.isCancelled, generation == loadGeneration,
                  queue.indices.contains(index + 1), queue[index + 1].id == track.id
            else { return }
            buildPreload(track: track, picks: picks, startingAt: 0)
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
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
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
        retryTask?.cancel()
        retryTask = nil
        discardPreload()
        currentItem = nil
        player.removeAllItems()
    }

    private func stopPlayback() {
        rotateListening()
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
        #if DEBUG
        if inBackground { debugBackgroundTicks += 1 }
        #endif
        // Between an auto-advance and its end-notification the player's head
        // is briefly the preloaded item; skip until bookkeeping catches up.
        guard let item = player.currentItem, item === currentItem else { return }
        let t = player.currentTime()
        let newTime = t.seconds.isFinite ? max(0, t.seconds) : 0
        let d = item.duration.seconds
        let newDuration = d.isFinite ? d : 0
        let newIsPlaying = player.timeControlStatus != .paused
        let newBuffered = item.loadedTimeRanges
            .map(\.timeRangeValue)
            .filter { $0.start <= t && t <= $0.end }
            .map { ($0.end - t).seconds }
            .max() ?? 0

        // @Observable notifies on every set (it never compares values), so
        // write only what changed — a paused session stops waking observers
        // 4x/sec, and stable values never invalidate views.
        if currentTime != newTime { currentTime = newTime }
        let pushWorthy = duration != newDuration || isPlaying != newIsPlaying
        if duration != newDuration { duration = newDuration }
        if isPlaying != newIsPlaying { isPlaying = newIsPlaying }
        if bufferedAhead != newBuffered { bufferedAhead = newBuffered }

        // Keep the on-disk position roughly current without writing 4x/sec.
        if abs(newTime - lastSavedPosition) >= 5 {
            persistState()
        }

        // The system Now Playing clock extrapolates from one (elapsed, rate)
        // sample — 4Hz XPC re-pushes buy nothing. Every real state change
        // (play/pause/seek/track) pushes explicitly at its own site; the tick
        // only needs to cover what it alone observes: duration discovery and
        // external play/pause flips (e.g. a headphone unplug).
        if pushWorthy { pushNowPlayingInfo() }

        // Listening stats. The pure policy holds the accumulator; the store only
        // hears about it at a commit boundary, never at 4Hz — see ListeningCredit
        // and the design spec's risk #3. A seek, a stall, or a wake produces one
        // huge delta and the policy clamps it; that is why the raw delta is
        // handed over rather than pre-filtered here.
        let creditDelta = newTime - lastCreditPosition
        lastCreditPosition = newTime
        lastCreditSampleAt = ProcessInfo.processInfo.systemUptime
        credit.tick(delta: creditDelta, isPlaying: newIsPlaying, duration: newDuration)
        if credit.isCommitDue { flushListening() }  // just sampled — no settle
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
            // Anchor listening there too: the offset was heard last session.
            lastCreditPosition = saved.position
        }
        pushNowPlayingInfo()
    }

    /// The app-termination hook, and a listening-stats commit boundary. (iOS
    /// backgrounding — where willTerminate is not guaranteed to fire — goes
    /// through `appDidEnterBackground()`, which is a commit boundary too.)
    private func persistNow() {
        commitListening()
        persistState()
    }

    #if DEBUG
    /// UITest-only: park a queue without resolving streams or starting
    /// playback, so transport UI renders under the `-UITestSeedQueue` flag.
    func seedUITestQueue(_ tracks: [QueueTrack], at index: Int = 0) {
        guard AppModel.isUITestRun else { return }
        queue = tracks
        self.index = min(max(0, index), max(0, tracks.count - 1))
        ended = false
    }
    #endif

    // --- listening stats commit boundaries ------------------------------------

    /// Settle, then hand the accumulated batch to the store.
    ///
    /// Idempotent: a second call with nothing accumulated is a no-op, which is
    /// what makes it safe to call from several boundaries that can overlap.
    /// The settle is what makes every commit boundary correct while the iOS app
    /// is backgrounded, where no tick has been accumulating.
    private func commitListening() {
        settleListening()
        flushListening()
    }

    /// Fold the span since the last sample — the tick's job in the foreground,
    /// and the only feed while backgrounded (the tick is off there).
    ///
    /// `position` overrides `creditPosition` for callers that know better (a
    /// track that just ended). Credit is capped at the real time since the last
    /// sample, so even a wrong position can never credit more than actually
    /// passed — and a stale one (the usual way to be wrong) only under-counts.
    /// Cheap and idempotent: settling twice in a row folds a ~0 span.
    private func settleListening(at position: Double? = nil) {
        // No trustworthy position (the player's head isn't our item: a gapless
        // hand-off in flight, or the queue just ended): skip the sample and
        // leave the baseline alone. Falling back to the tick-fed currentTime
        // here — stale while backgrounded — would pull the baseline down and
        // let the NEXT settle re-credit the gap, up to a whole track.
        guard let at = position ?? creditPosition else { return }
        let now = ProcessInfo.processInfo.systemUptime
        credit.span(delta: at - lastCreditPosition,
                    wallSeconds: now - lastCreditSampleAt,
                    duration: duration)
        lastCreditPosition = at
        lastCreditSampleAt = now
    }

    /// Where the playhead is, for crediting — or nil when that can't be read.
    /// Unlike `livePosition` it never falls back to `currentTime`.
    private var creditPosition: Double? {
        if let pendingSeekPosition { return pendingSeekPosition }
        guard let item = currentItem, player.currentItem === item else { return nil }
        let t = player.currentTime().seconds
        return t.isFinite ? max(0, t) : nil
    }

    /// Paused → playing: move the baseline to here and now, crediting nothing.
    /// Paused time can't have earned anything, and anchoring fresh means a
    /// settle that read a pre-seek position mid-seek (the player reports the
    /// old time until a seek lands) can't later credit the skipped distance
    /// across a paused span the wall-clock cap doesn't see as idle.
    private func rebaseListening() {
        if let at = creditPosition { lastCreditPosition = at }
        lastCreditSampleAt = ProcessInfo.processInfo.systemUptime
    }

    /// Hand over what's accumulated, without sampling first.
    private func flushListening() {
        let batch = credit.flush()
        guard !batch.isEmpty else { return }
        listening?.credit(artistName: creditedArtist,
                          seconds: batch.seconds,
                          completedPlay: batch.completedPlay)
    }

    /// Flush what the finished track earned, then re-arm the accumulator for
    /// whatever `current` now is.
    ///
    /// Call this AFTER `index` has moved — `commitListening()` uses the
    /// remembered `creditedArtist`, so the order is correct by construction.
    private func rotateListening() {
        commitListening()
        credit.startTrack()
        creditedArtist = current?.artist
        // A restored track resumes mid-way: that offset was never listened to.
        lastCreditPosition = pendingSeekPosition ?? 0
        lastCreditSampleAt = ProcessInfo.processInfo.systemUptime
    }

    private func persistState() {
        guard !queue.isEmpty else {
            stateStore.clear()
            lastSavedPosition = 0
            return
        }
        let position = livePosition
        lastSavedPosition = position
        stateStore.save(PersistedPlayback(
            tracks: queue.map {
                PersistedPlayback.Track(trackId: $0.trackId, title: $0.title,
                                        artist: $0.artist, show: $0.show,
                                        artworkPath: $0.artworkPath, showId: $0.showId)
            },
            index: index,
            position: position))
    }

    // --- artwork --------------------------------------------------------------

    /// The cached cover image for the now-playing track, if it has loaded.
    /// Reused by the now-playing chips and art tiles — reading the observed
    /// cache means views update when art arrives, with no extra fetch.
    var nowPlayingImage: PlatformImage? {
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
                  let image = PlatformImage(data: data),
                  !Task.isCancelled
            else { return }
            // Tiny bounded cache — one show's worth of art is one entry.
            // Evict a single entry, not the whole cache: flushing everything
            // forces a re-fetch of art the queue is about to need again.
            if artworkCache.count > 8, let victim = artworkCache.keys.first(where: { $0 != path }) {
                artworkCache.removeValue(forKey: victim)
            }
            artworkCache[path] = image
            guard current?.artworkPath == path else { return }
            setNowPlayingArtwork(image)
        }
    }

    private func setNowPlayingArtwork(_ image: PlatformImage) {
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

    /// `elapsed` defaults to where the player actually is (`livePosition`), not
    /// the tick-fed `currentTime` — while backgrounded there is no tick, and
    /// the system extrapolates from whatever this sample says.
    private func pushNowPlayingInfo(elapsed: Double? = nil) {
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
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed ?? livePosition,
            MPNowPlayingInfoPropertyPlaybackRate: actuallyPlaying ? 1.0 : 0.0,
        ]
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }
}
