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

    /// A number and its unit, kept apart so a ledger can set them in two
    /// weights (`.plainVoice`'s "**41** plays", "**62** h", "**112** hours
    /// listened"). Read together they say exactly what the joined string says.
    struct Figure: Equatable {
        let value: String
        let unit: String
    }

    struct Row: Identifiable, Equatable {
        let rank: Int
        let key: String
        let displayName: String
        let playsText: String
        let hoursText: String
        /// The same two numbers, split for the column layout ("41" "plays",
        /// "62" "h"; under an hour, "41" "m").
        let plays: Figure
        let hours: Figure

        var id: String { key }
    }

    struct Totals: Equatable {
        let hoursText: String
        let artistCountText: String
        let artistCount: Int
        /// The one-line totals ("**112** hours listened · **9** artists").
        let hours: Figure
        let artists: Figure
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
                      artistCount: tallies.count,
                      hours: totalHoursFigure(seconds: seconds),
                      artists: artistsFigure(tallies.count))
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
                    hoursText: hoursText(seconds: tally.seconds),
                    plays: playsFigure(tally.plays),
                    hours: hoursFigure(seconds: tally.seconds))
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

    // --- split figures (`.plainVoice`'s columns and totals line) -------------

    /// The totals line's hours: the same number as `totalHoursText`, with the
    /// unit spelled out. "1 hour listened", and "<1 hour listened" below one —
    /// less than one hour is still singular.
    static func totalHoursFigure(seconds: Double) -> Figure {
        let value = totalHoursText(seconds: seconds)
        let unit = (value == "1" || value == "<1") ? "hour listened" : "hours listened"
        return Figure(value: value, unit: unit)
    }

    static func artistsFigure(_ count: Int) -> Figure {
        Figure(value: String(count), unit: count == 1 ? "artist" : "artists")
    }

    /// A row's plays column: "41" "plays", "1" "play".
    static func playsFigure(_ plays: Int) -> Figure {
        Figure(value: String(plays), unit: plays == 1 ? "play" : "plays")
    }

    /// A row's hours column: the same rule as `hoursText` (whole hours once
    /// there is one, else whole minutes), split into "62" "h" / "41" "m".
    static func hoursFigure(seconds: Double) -> Figure {
        guard seconds.isFinite, seconds > 0 else { return Figure(value: "0", unit: "m") }
        let hours = Int(seconds / 3600)
        if hours > 0 { return Figure(value: String(hours), unit: "h") }
        return Figure(value: String(max(1, Int(seconds / 60))), unit: "m")
    }
}
