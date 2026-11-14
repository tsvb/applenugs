import Foundation

/// When Yeti's one flourish — the foil band crossing the now-playing title —
/// should run. Pure Foundation so the four rules are pinned host-free in
/// `AppleNugsTests`; the `foilSweep(identity:isPlaying:)` modifier holds one
/// of these and runs the band when `observe` says so.
///
/// The whole state is the identity that last swept. The rule: **fire when
/// playback is running for an identity that isn't the one that last swept**,
/// then remember it. That single rule gives every behavior the design asks for:
///
/// - a new track while playing fires once;
/// - pause → resume does not (same identity, already swept), so a three-hour
///   show with ten pauses sees it once per track;
/// - a launch-restored queue (current set, NOT playing) fires nothing until
///   its first play, then fires;
/// - the same track coming back later (re-queued, or skipped away from and
///   back to) fires again only if a DIFFERENT track swept in between. A track
///   that was current but never played doesn't count as "in between", and
///   neither does an empty queue (`nil` never overwrites the memory).
///
/// The identity is the catalog track id (`QueueTrack.trackId`), not the
/// per-entry `QueueTrack.id` UUID: keyed on the UUID, re-queueing a track
/// would always look new. It reads **no playback time** — identity and
/// `isPlaying` only — so it can never put the sweep on the 4 Hz tick.
struct FoilSweepTrigger: Equatable, Sendable {
    /// The identity the band last crossed (or was marked as seen), if any.
    private(set) var lastSwept: String?

    init(lastSwept: String? = nil) {
        self.lastSwept = lastSwept
    }

    /// Feed the latest playback state (on every identity or `isPlaying`
    /// change). Returns `true` exactly when the sweep should run now.
    mutating func observe(identity: String?, isPlaying: Bool) -> Bool {
        guard isPlaying, let identity, identity != lastSwept else { return false }
        lastSwept = identity
        return true
    }

    /// The title's view appeared. A track that is ALREADY playing when the
    /// view shows up (opening the player mid-song, the Duo rebuilding the
    /// player on rotation) is marked as seen without a sweep — the band marks
    /// a track change, not a screen opening. A track that is loaded but not
    /// playing is left unmarked, so a launch-restored queue still sweeps on
    /// its first play.
    mutating func appear(identity: String?, isPlaying: Bool) {
        _ = observe(identity: identity, isPlaying: isPlaying)
    }
}
