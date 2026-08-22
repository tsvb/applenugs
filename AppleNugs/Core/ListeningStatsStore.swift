import Foundation
import Observation

/// Persists all-time listening tallies as JSON in Application Support, beside
/// session.json / favorites.json / nowplaying.json — the FavoritesStore idiom.
///
/// `@Observable` so the Home ledger updates when a commit lands. It is only ever
/// written at a COMMIT BOUNDARY (roughly twice a minute), never from the
/// player's ~4Hz tick: `PlayerService` owns the accumulator (see
/// `ListeningCredit`) and hands over a batch. Do not add a per-tick entry point,
/// and do not move the accumulator in here — `@Observable` notifies on every set
/// without comparing values, so ticking seconds in `stats` would make the Home
/// ledger re-diff four times a second.
@MainActor
@Observable
final class ListeningStatsStore {

    private(set) var stats: ListeningStats = .empty

    /// Cheap gate for the Home ledger's presence.
    ///
    /// `HomeView` reads THIS, never `stats`. Reading `stats` from Home's body
    /// subscribes the whole body to the table, so every commit — twice a minute
    /// during playback, plus every track change and every pause — would
    /// invalidate the greeting, the resume hero, the favorites strip and the
    /// crate grid, not just the ledger. This flips at most once per install.
    /// Same class of hazard as the `artColor` read HomeView guards behind
    /// `#if os(macOS)` for exactly the same reason.
    private(set) var hasAnyPlay = false

    /// Latched when `listening.json` exists but could not be read cleanly.
    ///
    /// While set, `save()` refuses to write. These are rolling aggregates with
    /// no event log, so a file we failed to parse is the ONLY copy of that
    /// history: overwriting it with whatever we managed to salvage would
    /// destroy it permanently. Better to keep serving the salvaged table
    /// read-only and leave the file on disk for a human.
    @ObservationIgnored private var loadFailed = false

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleNugs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("listening.json")
        load()
    }

    /// The seam.
    ///
    /// Deliberately neutral — no `QueueTrack`, no player types — so
    /// `VideoPlayerService` can become a second call site later without
    /// reshaping anything (webcasts and concert films do not count today). And
    /// deliberately coarse: callers batch seconds and hand them over at commit
    /// boundaries rather than streaming them. A nil or blank `artistName` is
    /// dropped silently.
    func credit(artistName: String?, seconds: Double, completedPlay: Bool) {
        var updated = stats
        updated.credit(artistName: artistName, seconds: seconds,
                       completedPlay: completedPlay, now: Date())
        guard updated != stats else { return }
        stats = updated
        refreshHasAnyPlay()
        save()
    }

    /// Wipe every tally.
    ///
    /// Load-bearing rather than a nicety: these are rolling aggregates with no
    /// event log behind them, so a reset is the only remedy for polluted data.
    func reset() {
        // A deliberate wipe is exactly the human intervention a failed load was
        // waiting for: the user is telling us the unreadable file no longer
        // matters. Clearing the latch first keeps the escape hatch working —
        // otherwise `save()` would refuse and Reset would silently do nothing.
        loadFailed = false
        stats = .empty
        refreshHasAnyPlay()
        save()
    }

    // --- persistence --------------------------------------------------------

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return }

        // Strict first — a clean file is overwhelmingly the common case.
        if let decoded = try? Self.decoder.decode(ListeningStats.self, from: data) {
            stats = decoded
            refreshHasAnyPlay()
            return
        }

        // Something in the file no longer fits the current shape — a truncated
        // write, a hand-edit, or (the realistic one) a future schema change
        // that added a non-optional field to `ArtistTally`. Salvage every tally
        // that still decodes and latch `loadFailed` so we never write back over
        // the ones that didn't.
        //
        // `FavoritesStore` carries the same tolerance for the same reason, and
        // documents the failure mode: without it, one bad element resets the
        // collection to empty and the next write overwrites the file with that
        // empty state. It is worse here — favorites can be re-added by hand,
        // all-time totals cannot be reconstructed at all.
        loadFailed = true
        if let salvaged = try? Self.decoder.decode(SalvagedStats.self, from: data) {
            stats = ListeningStats(artists: salvaged.artists,
                                   version: ListeningStats.currentVersion)
            refreshHasAnyPlay()
        }
    }

    private func refreshHasAnyPlay() {
        // @Observable notifies on every set without comparing, so only write
        // when it actually changes.
        let any = stats.artists.values.contains { $0.plays > 0 }
        if hasAnyPlay != any { hasAnyPlay = any }
    }

    /// Per-element-tolerant view of the file, used only on the salvage path.
    ///
    /// A tally that no longer decodes drops itself instead of taking the whole
    /// table down with it.
    private struct SalvagedStats: Decodable {
        var artists: [String: ArtistTally]

        private struct LossyTally: Decodable {
            let value: ArtistTally?
            init(from decoder: Decoder) throws { value = try? ArtistTally(from: decoder) }
        }

        private enum CodingKeys: String, CodingKey { case artists }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try c.decode([String: LossyTally].self, forKey: .artists)
            artists = raw.compactMapValues(\.value)
        }
    }

    /// The ONLY write path — reset routes through it too — and it is suppressed
    /// under `-UITEST`.
    ///
    /// A `-UITestSeedQueue` launch parks stub tracks. Without this guard,
    /// touching the transport from a seeded launch would fold fictional artists
    /// into the real all-time totals, and "Reset Listening Stats" would erase
    /// the real ones outright. That is the same hazard class `PlaybackStateStore`
    /// guards, which has already cost a real resume queue once. Reads are
    /// deliberately left live.
    ///
    /// `AppModel.isUITestRun` only exists in DEBUG, hence the surrounding `#if`.
    private func save() {
        #if DEBUG
        guard !AppModel.isUITestRun else { return }
        #endif
        guard !loadFailed else { return }
        guard let data = try? Self.encoder.encode(stats) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: fileURL.path)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
