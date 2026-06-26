import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// A manual quality cap applied to the current item. `.auto` lets HLS ABR pick
/// freely; `.capped` ceilings the resolution/bitrate without swapping playlists.
enum VideoQuality: Hashable {
    case auto
    case capped(height: Int)

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .capped(let h): return "\(h)p"
        }
    }
}

/// The video playback context — a *second*, single-item `AVPlayer` distinct
/// from the audio queue's `AVQueuePlayer`. Starting a video pauses the audio
/// `PlayerService` (remembering whether it was playing) and claims the system
/// Now Playing / remote-command center; `stop()` relinquishes both and resumes
/// audio if it had been playing. Only one of audio/video owns Now Playing at a
/// time — the arbiter rule.
@MainActor
@Observable
final class VideoPlayerService {

    // --- published state ----------------------------------------------------

    private(set) var current: VideoDetail?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isLive = false
    private(set) var atLiveEdge = false
    private(set) var loadError: String?
    private(set) var availableQualities: [VideoQuality] = [.auto]

    var selectedQuality: VideoQuality = .auto {
        didSet {
            guard selectedQuality != oldValue else { return }
            applyQuality()
            UserDefaults.standard.set(qualityCode(selectedQuality), forKey: Self.qualityKey)
        }
    }

    /// The AVPlayer drawn by `VideoPlayerSurface`. Public so the surface can
    /// bind it; all transport goes through this service.
    let player = AVPlayer()

    // --- collaborators ------------------------------------------------------

    private let audio: PlayerService
    private let client: NugsClient
    private let progress: VideoProgressStore

    // --- internals ----------------------------------------------------------

    private static let qualityKey = "videoQuality"

    private var item: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    /// Whether the audio service was playing when this video took over, so
    /// `stop()` can resume it. The arbiter's one piece of remembered state.
    private var resumeAudioOnStop = false

    /// True while this service owns the system Now Playing / remote commands.
    private var ownsNowPlaying = false

    /// Opaque target tokens returned by `addTarget(handler:)`, kept so the exact
    /// closures registered on claim can be removed on relinquish — passing
    /// `self` to `removeTarget` would not match closure-registered handlers.
    private var remoteCommandTargets: [Any] = []

    /// Bumped on each `play` so stale async loads/observers no-op.
    private var loadGeneration = 0

    /// Last position written to disk, to throttle recording to ~5 s.
    private var lastRecordedPosition: Double = 0

    /// A start seek deferred until the item is `.readyToPlay` — a VOD resume
    /// position, or the live-edge sentinel. Seeking right after
    /// `replaceCurrentItem` (status `.unknown`, empty seekable range) is
    /// dropped, which would resume at 0; we apply it from the status observer.
    private var pendingResumeSeek: Double?
    private var pendingLiveEdgeSeek = false

    init(audio: PlayerService, client: NugsClient, progress: VideoProgressStore) {
        self.audio = audio
        self.client = client
        self.progress = progress
        if let code = UserDefaults.standard.string(forKey: Self.qualityKey) {
            selectedQuality = Self.quality(from: code)
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // --- playback -----------------------------------------------------------

    func play(_ video: VideoDetail) async {
        loadGeneration += 1
        let generation = loadGeneration
        tearDownItem()
        current = video
        isLive = video.isLive
        atLiveEdge = video.isLive
        currentTime = 0
        duration = 0
        loadError = nil
        availableQualities = [.auto]
        lastRecordedPosition = 0

        let resolved: NugsClient.VideoStream?
        do {
            resolved = try await client.resolveVideoStream(
                containerId: video.id, sku: video.videoSku, isLive: video.isLive)
        } catch {
            guard generation == loadGeneration else { return }
            loadError = error.localizedDescription
            return
        }
        guard generation == loadGeneration else { return }
        guard let resolved, let url = URL(string: resolved.url), !resolved.url.isEmpty else {
            // A missing SKU (e.g. a live item whose container detail didn't
            // carry it) can't resolve at all; distinguish that from a real
            // entitlement gap so the message isn't misleading.
            loadError = video.videoSku == 0
                ? "Couldn’t find a playable stream for this video."
                : "This video isn’t included in your plan."
            return
        }

        // Same header contract the audio engine uses for the nugs CDN.
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Referer": NugsConstants.playerReferer,
                "User-Agent": NugsConstants.mobileUserAgent,
            ],
        ])
        let newItem = AVPlayerItem(asset: asset)
        item = newItem
        observe(newItem)
        player.replaceCurrentItem(with: newItem)
        applyQuality()
        loadVariants(from: asset, generation: generation)

        // Arbiter: take over the system Now Playing / remote commands from
        // audio. No-op if we already own them, so a re-entrant play() can't
        // re-capture audio's now-paused state and strand it.
        claimArbiterIfNeeded()

        // Defer the start seek to `.readyToPlay` (see `applyPendingStartSeek`);
        // issuing it now, before the item is ready, would be dropped.
        if video.isLive {
            pendingLiveEdgeSeek = true
        } else if let saved = progress.progress(for: video.id), saved.positionSeconds > 1 {
            pendingResumeSeek = saved.positionSeconds
            currentTime = saved.positionSeconds   // reflect the resume point immediately
        }
        player.play()
        isPlaying = true
        pushNowPlayingInfo()
    }

    func togglePlayPause() {
        guard item != nil else { return }
        if player.timeControlStatus == .paused {
            // Replaying after the arbiter was relinquished (e.g. the video had
            // played to its end) must re-take Now Playing from audio.
            claimArbiterIfNeeded()
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
            recordProgress(force: true)
        }
        pushNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        if isLive { atLiveEdge = false }
        pushNowPlayingInfo()
    }

    func seek(by delta: Double) {
        guard duration > 0 || isLive else { return }
        let target = currentTime + delta
        if isLive {
            seek(to: max(0, target))
        } else {
            seek(to: min(max(target, 0), duration))
        }
    }

    func seekToLiveEdge() {
        guard let item, let range = item.seekableTimeRanges.last?.timeRangeValue else {
            // Seekable range not populated yet — don't seek to the buffer head
            // and over-claim the live edge; tick() snaps atLiveEdge once it is.
            return
        }
        player.seek(to: range.start + range.duration, toleranceBefore: .zero, toleranceAfter: .zero)
        atLiveEdge = true
        pushNowPlayingInfo()
    }

    /// Take over system Now Playing + remote commands from audio, unless we
    /// already own them. Captures whether audio was playing so it can be resumed
    /// on relinquish; guarding on `ownsNowPlaying` stops a re-entrant claim from
    /// overwriting that captured state and stranding audio paused.
    private func claimArbiterIfNeeded() {
        guard !ownsNowPlaying else { return }
        resumeAudioOnStop = audio.pauseForExternalAudio()
        claimNowPlaying()
    }

    /// Hand system Now Playing + remote commands back to audio (resuming it if
    /// it had been playing). Idempotent — called from both stop() and the
    /// natural-end handler, so audio's media integration is restored whether the
    /// video is dismissed or simply finishes on screen.
    private func relinquishArbiter() {
        guard ownsNowPlaying else { return }
        relinquishNowPlaying()
        audio.endExternalPlayback(resume: resumeAudioOnStop)
        resumeAudioOnStop = false
    }

    func stop() {
        recordProgress(force: true)
        loadGeneration += 1
        tearDownItem()
        current = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        isLive = false
        atLiveEdge = false
        loadError = nil
        relinquishArbiter()
    }

    // --- quality ------------------------------------------------------------

    /// Parse the master playlist's advertised variants once to populate the
    /// quality menu. We only *cap* — never swap playlists.
    private func loadVariants(from asset: AVURLAsset, generation: Int) {
        Task {
            let heights = await Self.variantHeights(from: asset)
            guard generation == loadGeneration else { return }
            var menu: [VideoQuality] = [.auto]
            menu.append(contentsOf: heights.sorted(by: >).map { .capped(height: $0) })
            availableQualities = menu
            applyQuality()
        }
    }

    private nonisolated static func variantHeights(from asset: AVURLAsset) async -> [Int] {
        guard let variants = try? await asset.load(.variants) else { return [] }
        var seen = Set<Int>()
        for v in variants {
            if let size = v.videoAttributes?.presentationSize {
                let h = Int(size.height.rounded())
                if h > 0 { seen.insert(h) }
            }
        }
        return Array(seen)
    }

    private func applyQuality() {
        guard let item else { return }
        switch selectedQuality {
        case .auto:
            item.preferredMaximumResolution = .zero
            item.preferredPeakBitRate = 0
        case .capped(let h):
            // Cap by resolution; width derived from a 16:9 assumption is fine
            // because AVFoundation matches the largest variant at-or-below it.
            item.preferredMaximumResolution = CGSize(width: h * 16 / 9, height: h)
            item.preferredPeakBitRate = 0
        }
    }

    private func qualityCode(_ q: VideoQuality) -> String {
        switch q {
        case .auto: return "auto"
        case .capped(let h): return String(h)
        }
    }

    private static func quality(from code: String) -> VideoQuality {
        if code == "auto" { return .auto }
        if let h = Int(code), h > 0 { return .capped(height: h) }
        return .auto
    }

    // --- engine plumbing ----------------------------------------------------

    private func observe(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, item === self.item else { return }
                switch item.status {
                case .failed:
                    self.loadError = item.error?.localizedDescription
                        ?? "This video failed to play."
                    // Nothing played — drop the deferred seek and don't leave
                    // currentTime pinned at the resume point (it would falsely
                    // highlight a "current" chapter for a video that never ran).
                    self.pendingResumeSeek = nil
                    self.pendingLiveEdgeSeek = false
                    self.currentTime = 0
                case .readyToPlay:
                    self.applyPendingStartSeek()
                default:
                    break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let video = self.current else { return }
                self.isPlaying = false
                if !self.isLive { self.progress.markFinished(video.id) }
                // The video is done — relinquish the arbiter even though the view
                // stays on screen, so audio's Now Playing / media keys aren't
                // left dead until the user navigates away.
                self.relinquishArbiter()
            }
        }
    }

    /// Apply a start seek (resume position / live edge) once the item is ready.
    /// Called from the status observer at `.readyToPlay`.
    private func applyPendingStartSeek() {
        if let pos = pendingResumeSeek {
            pendingResumeSeek = nil
            seek(to: pos)
        } else if pendingLiveEdgeSeek {
            pendingLiveEdgeSeek = false
            seekToLiveEdge()
        }
    }

    private func tearDownItem() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        pendingResumeSeek = nil
        pendingLiveEdgeSeek = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        item = nil
    }

    /// ~2x/sec snapshot: time/duration, live-edge tracking, throttled recording.
    private func tick() {
        guard let item, item === self.item else { return }
        let t = player.currentTime().seconds
        currentTime = t.isFinite ? max(0, t) : 0
        let d = item.duration.seconds
        duration = d.isFinite ? d : 0
        isPlaying = player.timeControlStatus != .paused

        if isLive, let end = item.seekableTimeRanges.last?.timeRangeValue {
            let edge = (end.start + end.duration).seconds
            if edge.isFinite { atLiveEdge = (edge - currentTime) < 8 }
        }

        if abs(currentTime - lastRecordedPosition) >= 5 {
            recordProgress(force: false)
        }
        pushNowPlayingInfo()
    }

    /// Persist resume position. Never for livestreams. Past ~95 % we treat the
    /// video as finished and clear it instead.
    private func recordProgress(force: Bool) {
        guard let video = current, !isLive, duration > 0 else { return }
        if !force && abs(currentTime - lastRecordedPosition) < 5 { return }
        lastRecordedPosition = currentTime
        if currentTime / duration >= 0.95 {
            progress.markFinished(video.id)
            return
        }
        progress.record(VideoProgress(
            id: video.id, videoSku: video.videoSku, title: video.title,
            artistName: video.artistName, imageURL: video.imageURL?.absoluteString,
            positionSeconds: currentTime, durationSeconds: duration, updatedAt: Date()))
    }

    // --- system media (arbiter-owned) ---------------------------------------

    /// Take over Now Playing + the remote command center from audio. Audio's
    /// own handlers stay registered but its handlers return early once it is
    /// paused; ours are the ones acting while a video owns playback. We retain
    /// each `addTarget` token so relinquish can remove exactly these closures.
    private func claimNowPlaying() {
        guard !ownsNowPlaying else { return }
        ownsNowPlaying = true
        let center = MPRemoteCommandCenter.shared()
        remoteCommandTargets = [
            center.togglePlayPauseCommand.addTarget(handler: remoteToggle),
            center.playCommand.addTarget(handler: remotePlay),
            center.pauseCommand.addTarget(handler: remotePause),
            center.changePlaybackPositionCommand.addTarget(handler: remoteSeek),
        ]
    }

    private func relinquishNowPlaying() {
        guard ownsNowPlaying else { return }
        ownsNowPlaying = false
        let center = MPRemoteCommandCenter.shared()
        // Tokens align with the commands they were registered on, in order.
        let commands: [MPRemoteCommand] = [
            center.togglePlayPauseCommand,
            center.playCommand,
            center.pauseCommand,
            center.changePlaybackPositionCommand,
        ]
        for (command, token) in zip(commands, remoteCommandTargets) {
            command.removeTarget(token)
        }
        remoteCommandTargets = []
        // Audio's pushNowPlayingInfo (via resume/pause in stop()) restores its
        // own info; clear ours so a brief gap shows nothing rather than stale.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func remoteToggle(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard ownsNowPlaying, current != nil else { return .noActionableNowPlayingItem }
        togglePlayPause(); return .success
    }
    private func remotePlay(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard ownsNowPlaying, current != nil else { return .noActionableNowPlayingItem }
        if !isPlaying { togglePlayPause() }; return .success
    }
    private func remotePause(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard ownsNowPlaying, current != nil else { return .noActionableNowPlayingItem }
        if isPlaying { togglePlayPause() }; return .success
    }
    private func remoteSeek(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard ownsNowPlaying, let event = event as? MPChangePlaybackPositionCommandEvent
        else { return .commandFailed }
        seek(to: event.positionTime); return .success
    }

    private func pushNowPlayingInfo() {
        guard ownsNowPlaying, let video = current else { return }
        let center = MPNowPlayingInfoCenter.default()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: video.artistName,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if !isLive {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }
}
