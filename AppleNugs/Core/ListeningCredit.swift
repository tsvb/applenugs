import Foundation

/// The credit policy for listening stats: what one playback tick is worth, and
/// when a track visit has earned a "play".
///
/// This type also HOLDS the per-track accumulator, and that placement is
/// load-bearing. `PlayerService` keeps one of these as an `@ObservationIgnored`
/// property and feeds it from the ~4Hz tick (and, while the iOS app is
/// backgrounded and the tick is off, from playhead spans settled at commit
/// boundaries and the once-a-minute background wake); the store is only told about a
/// batch at a commit boundary — roughly twice a minute, never four times a
/// second. `@Observable` notifies on every set without comparing values, so if
/// ticking seconds landed in the store's observed counters the Home ledger
/// would re-diff at tick rate — precisely the failure mode the dashboard's
/// leaf-view isolation rule exists to prevent.
///
/// Deliberately Foundation-only (no SwiftUI, no AVFoundation, no Observation)
/// and taking loose primitives, so it compiles straight into the host-free
/// `AppleNugsTests` target.
struct ListeningCredit: Equatable {

    /// What one commit hands to the store.
    struct Batch: Equatable {
        var seconds: Double
        var completedPlay: Bool

        /// Nothing to hand over — the caller should skip the store call entirely.
        var isEmpty: Bool { seconds <= 0 && !completedPlay }
    }

    /// A tick contributes at most one second. A normal tick is 0.25s; a seek, a
    /// wake-from-sleep, and a stall each produce one large jump, and the clamp
    /// caps all of them without the policy having to detect any of them.
    static let maxTickSeconds: Double = 1

    /// The ceiling on the play threshold, and the flat threshold for a stream
    /// that reports no duration.
    static let playSecondsCap: Double = 240

    /// How much uncommitted listening forces a commit.
    static let commitIntervalSeconds: Double = 30

    /// Listened seconds on the current track visit. Reset only by `startTrack()`.
    private(set) var trackSeconds: Double = 0

    /// Seconds not yet handed to the store.
    private(set) var uncommittedSeconds: Double = 0

    /// True once this visit has earned its play — the latch that stops one visit
    /// earning two.
    private(set) var playCredited = false

    /// True when an earned play has not yet been handed to the store.
    private(set) var uncommittedPlay = false

    /// Listened seconds that earn a play: half the track, capped at four
    /// minutes. A duration-less stream (livestream, webcast) takes the flat cap
    /// — the same treatment the pill's progress ring and all six scrub sliders
    /// already give `duration <= 0`.
    static func playThreshold(duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return playSecondsCap }
        return min(0.5 * duration, playSecondsCap)
    }

    /// Fold one playback tick.
    ///
    /// `delta` is playhead movement since the previous tick, which is why it can
    /// be negative (a backward seek) or huge (a forward seek, a stall, a wake):
    /// both are handled by the clamp, not by special cases. Paused time
    /// contributes nothing because the accumulator only runs while playing.
    mutating func tick(delta: Double, isPlaying: Bool, duration: Double) {
        guard isPlaying, delta.isFinite else { return }
        add(min(max(delta, 0), Self.maxTickSeconds), duration: duration)
    }

    /// Fold a span with no ticks inside it — the iOS app backgrounded, where
    /// the tick is off (see `PlayerService.appDidEnterBackground()`).
    ///
    /// `delta` is playhead movement since the last sample and `wallSeconds` the
    /// real time that passed meanwhile. A playhead being listened to can't move
    /// faster than real time, so the wall clock is the clamp here — what the
    /// 1s cap is for a tick: a forward seek inside the span earns at most the
    /// time that actually passed. There is no `isPlaying` gate because none is
    /// needed: a paused or stalled playhead doesn't move, so its delta is 0.
    mutating func span(delta: Double, wallSeconds: Double, duration: Double) {
        guard delta.isFinite, wallSeconds.isFinite else { return }
        add(min(max(delta, 0), max(wallSeconds, 0)), duration: duration)
    }

    /// The accumulator and the play latch, shared by both entry points so a
    /// visit that mixes ticks and spans still earns exactly one play.
    private mutating func add(_ credited: Double, duration: Double) {
        guard credited > 0 else { return }

        trackSeconds += credited
        uncommittedSeconds += credited

        if !playCredited, trackSeconds >= Self.playThreshold(duration: duration) {
            playCredited = true
            uncommittedPlay = true
        }
    }

    /// True when the caller should commit. An earned play commits immediately so
    /// the ledger updates when it lands; otherwise a commit is due every 30s.
    var isCommitDue: Bool {
        uncommittedPlay || uncommittedSeconds >= Self.commitIntervalSeconds
    }

    /// Hand over everything accumulated since the last commit. Idempotent: a
    /// second call with nothing accumulated returns an empty batch.
    mutating func flush() -> Batch {
        let batch = Batch(seconds: uncommittedSeconds, completedPlay: uncommittedPlay)
        uncommittedSeconds = 0
        uncommittedPlay = false
        return batch
    }

    /// Begin a new track visit.
    ///
    /// Call this only AFTER flushing, or the finished track's uncommitted
    /// seconds are lost.
    mutating func startTrack() {
        trackSeconds = 0
        uncommittedSeconds = 0
        uncommittedPlay = false
        playCredited = false
    }
}
