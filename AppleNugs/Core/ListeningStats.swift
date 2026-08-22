import Foundation

/// One artist's all-time tally.
///
/// `displayName` is the spelling last seen in the player and is what the ledger
/// renders; the dictionary key it is filed under is the folded form and is
/// never shown.
struct ArtistTally: Codable, Equatable {
    var displayName: String
    var plays: Int
    var seconds: Double
    var firstPlayedAt: Date
    var lastPlayedAt: Date
}

/// The whole listening table: rolling aggregates, artists only, all-time.
///
/// There is no event log behind this — nothing here can be re-derived after the
/// fact, and a change to the counting rule can only ever apply going forward.
/// That trade was made deliberately (see
/// `docs/superpowers/specs/2026-08-21-listening-stats-design.md`); the reset in
/// the account menu is the only remedy for polluted data, which is why it is
/// load-bearing rather than a nicety.
///
/// Deliberately Foundation-only so it compiles straight into the host-free
/// `AppleNugsTests` target.
struct ListeningStats: Codable, Equatable {
    var artists: [String: ArtistTally]
    var version: Int

    static let currentVersion = 1
    static let empty = ListeningStats(artists: [:], version: currentVersion)

    /// The dictionary key for a display name.
    ///
    /// `QueueTrack.artist` is a display name, not an id — no artist id exists
    /// anywhere in the playback path — so the key has to be derived from the
    /// name. The rule is `DeepLinkMatch.normalize`, the one the venue matcher
    /// already uses: apostrophes (ASCII and U+2019) deleted outright, every
    /// other non-alphanumeric run collapsed to one space, lowercased and
    /// diacritic-folded. Do NOT write a second folding rule.
    ///
    /// Returns nil for a name that folds to nothing, which is how blank and
    /// punctuation-only artist names get dropped.
    static func key(for displayName: String) -> String? {
        let folded = DeepLinkMatch.normalize(displayName)
        return folded.isEmpty ? nil : folded
    }

    /// Fold one commit into the table.
    ///
    /// Pure: the caller supplies `now`, so timestamps are testable. A nil,
    /// blank, or unfoldable name is dropped silently — the seam is deliberately
    /// forgiving because `QueueTrack.artist` is optional.
    ///
    /// Non-finite and negative seconds contribute zero. That guard is not
    /// theoretical: a NaN would fail to encode and leave `listening.json`
    /// undecodable on the next launch.
    mutating func credit(artistName: String?,
                         seconds: Double,
                         completedPlay: Bool,
                         now: Date) {
        guard let artistName else { return }
        let trimmed = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = Self.key(for: trimmed) else { return }

        let addedSeconds = (seconds.isFinite && seconds > 0) ? seconds : 0
        guard addedSeconds > 0 || completedPlay else { return }

        if var existing = artists[key] {
            existing.displayName = trimmed
            existing.plays += completedPlay ? 1 : 0
            existing.seconds += addedSeconds
            existing.lastPlayedAt = now
            artists[key] = existing
        } else {
            artists[key] = ArtistTally(displayName: trimmed,
                                       plays: completedPlay ? 1 : 0,
                                       seconds: addedSeconds,
                                       firstPlayedAt: now,
                                       lastPlayedAt: now)
        }
    }
}
