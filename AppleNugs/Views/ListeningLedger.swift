import SwiftUI

/// The Home listening ledger: total hours, distinct artists, and a top-five
/// artist leaderboard, set as type rather than as cards.
///
/// Deliberately container-free — no fill, no border, no rounded rect, no shadow.
/// Rows sit on the page background and are separated by a hairline rule. It
/// lives inline on Home and has no destination of its own, which is why it is
/// capped at five rows and two totals.
///
/// It never reads the player's live position tick — the ~4Hz clock the
/// dashboard's leaf views exist to isolate. It reads `app.listening.stats`,
/// which changes only at a commit boundary (roughly twice a minute), so it
/// stays outside that leaf-isolation rule rather than becoming a new case of
/// it. Do not add a live-position readout here; the plan's self-audit greps
/// this file for that symbol by name and expects no hits, comments included.
///
/// Every string it renders comes from `LedgerSummary`, so the formatting is
/// pinned by tests rather than by this body. Do not format here.
///
/// Shared across macOS and iOS — nothing platform-specific.
struct ListeningLedger: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    /// Folded key → catalog entry, for the rows that resolve. A row that does
    /// not resolve renders as plain text rather than as a dead tap target.
    ///
    /// Resolution is the ASYNC `app.artist(named:)`, never the synchronous
    /// `cachedArtist(named:)`: the sync fast path would make the same name
    /// clickable on one launch and not the next.
    @State private var resolved: [String: ArtistEntry] = [:]

    var body: some View {
        let tallies = Self.tallies(from: app.listening.stats)
        let rows = LedgerSummary.top(tallies)
        let totals = LedgerSummary.totals(tallies)

        VStack(alignment: .leading, spacing: 12) {
            Text("LISTENING")
                .font(theme.type.numeric(10))
                .tracking(1.8)
                .foregroundStyle(theme.palette.textSecondary)

            VStack(spacing: 0) {
                totalRow(label: "Hours", value: totals.hoursText)
                hairline
                totalRow(label: "Artists", value: totals.artistCountText)
                ForEach(rows) { row in
                    hairline
                    leaderRow(row)
                }
            }
        }
        .task(id: rows.map(\.key).joined(separator: "|")) {
            await resolveNames(rows)
        }
    }

    // --- rows ---------------------------------------------------------------

    /// Row separation is a rule, not a box. 1pt, `theme.palette.hairline`.
    private var hairline: some View {
        Rectangle()
            .fill(theme.palette.hairline)
            .frame(height: 1)
    }

    private func totalRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(theme.type.body(14))
                .foregroundStyle(theme.palette.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(theme.type.numeric(14))
                .foregroundStyle(theme.palette.textPrimary)
        }
        .padding(.vertical, 9)
    }

    /// Tappable only when the stored display name resolved against the catalog.
    /// An unresolved name renders as plain text — never a dead tap target.
    @ViewBuilder
    private func leaderRow(_ row: LedgerSummary.Row) -> some View {
        if let entry = resolved[row.key] {
            NavigationLink(value: Route.artist(entry)) {
                leaderRowBody(row)
            }
            .buttonStyle(.plain)
        } else {
            leaderRowBody(row)
        }
    }

    private func leaderRowBody(_ row: LedgerSummary.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(row.rank)")
                .font(theme.type.numeric(12))
                .foregroundStyle(theme.palette.textIdle)
                .frame(width: 16, alignment: .leading)
            Text(row.displayName)
                .font(theme.type.body(14))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(row.playsText) · \(row.hoursText)")
                .font(theme.type.numeric(12))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // --- resolution ---------------------------------------------------------

    private func resolveNames(_ rows: [LedgerSummary.Row]) async {
        var found: [String: ArtistEntry] = [:]
        for row in rows {
            if let entry = try? await app.artist(named: row.displayName) {
                found[row.key] = entry
            }
        }
        resolved = found
    }
}

extension ListeningLedger {
    /// The one mapping from the stored table to the pure policy's input.
    /// `LedgerSummary` deliberately takes loose primitives so it stays
    /// Foundation-only and host-free — the `SignalReadout` idiom.
    static func tallies(from stats: ListeningStats) -> [LedgerSummary.Tally] {
        stats.artists.map { key, tally in
            LedgerSummary.Tally(key: key, displayName: tally.displayName,
                                plays: tally.plays, seconds: tally.seconds)
        }
    }
}
