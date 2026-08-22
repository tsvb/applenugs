import Foundation

/// The Home listening ledger's rows and totals, as pure data.
///
/// Takes loose primitives rather than the `ListeningStats` table — the
/// `SignalReadout` idiom, and for the same reason: it stays Foundation-only and
/// compiles straight into the host-free `AppleNugsTests` target. The view does
/// the one-line mapping from the stored dictionary.
///
/// Every string the ledger shows is produced here, so the formatting is pinned
/// by tests rather than by a view body nobody can assert against.
enum LedgerSummary {

    /// One artist's totals, already folded. `key` is the stored dictionary key;
    /// it is used only for identity and the final tie-break, and is never shown.
    struct Tally: Equatable {
        var key: String
        var displayName: String
        var plays: Int
        var seconds: Double
    }

    struct Row: Identifiable, Equatable {
        let rank: Int
        let key: String
        let displayName: String
        let playsText: String
        let hoursText: String

        var id: String { key }
    }

    struct Totals: Equatable {
        let hoursText: String
        let artistCountText: String
        let artistCount: Int
    }

    /// The ledger lives inline on Home, so it is capped at what fits there.
    static let topCount = 5

    /// The section renders nothing at all until at least one play is credited.
    /// Seconds alone are not enough: a few stray partial listens are not a
    /// ledger, and Home already has a hero and a crate.
    static func isEmpty(_ tallies: [Tally]) -> Bool {
        !tallies.contains { $0.plays > 0 }
    }

    /// Two totals rows only. A `Plays` total was considered and cut — every
    /// leaderboard row already carries a play count.
    static func totals(_ tallies: [Tally]) -> Totals {
        let seconds = tallies
            .map(\.seconds)
            .filter { $0.isFinite && $0 > 0 }
            .reduce(0, +)
        return Totals(hoursText: totalHoursText(seconds: seconds),
                      artistCountText: String(tallies.count),
                      artistCount: tallies.count)
    }

    /// Top artists by seconds. Ties break by plays, then by name, then by key,
    /// so the order never flickers between renders.
    static func top(_ tallies: [Tally]) -> [Row] {
        tallies
            .sorted { a, b in
                if a.seconds != b.seconds { return a.seconds > b.seconds }
                if a.plays != b.plays { return a.plays > b.plays }
                let byName = a.displayName.localizedStandardCompare(b.displayName)
                if byName != .orderedSame { return byName == .orderedAscending }
                return a.key < b.key
            }
            .prefix(topCount)
            .enumerated()
            .map { offset, tally in
                Row(rank: offset + 1,
                    key: tally.key,
                    displayName: tally.displayName,
                    playsText: playsText(tally.plays),
                    hoursText: hoursText(seconds: tally.seconds))
            }
    }

    /// The Hours total: whole hours once there is one, `"<1"` below that. No
    /// decimals — this is a ledger, not a stopwatch, and the row label already
    /// says "Hours".
    static func totalHoursText(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0" }
        let hours = seconds / 3600
        return hours >= 1 ? String(Int(hours)) : "<1"
    }

    /// A leaderboard row's duration: whole hours once there is one, else whole
    /// minutes, so a short-but-frequent artist never reads "0h".
    static func hoursText(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0m" }
        let hours = Int(seconds / 3600)
        if hours > 0 { return "\(hours)h" }
        return "\(max(1, Int(seconds / 60)))m"
    }

    static func playsText(_ plays: Int) -> String {
        plays == 1 ? "1 play" : "\(plays) plays"
    }
}
