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
/// Under `.plainVoice` (Yeti) it is "the nice list": a sentence-case section
/// header, one totals line ("112 hours listened · 9 artists"), and rows of a
/// checked box, the name (which truncates first) and plays / hours in two
/// right-aligned columns. Same data, same gate, same resolution; only the
/// setting changes, and the split numbers still come from `LedgerSummary`.
///
/// Shared across macOS and iOS; the nice list's columns are a little wider on
/// the Mac (the sheet's `.ledger-wide`).
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

        Group {
            if theme.caps.contains(.plainVoice) {
                niceList(rows: rows, totals: totals)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(theme.copy.ledgerTitle)
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
        linked(row) { leaderRowBody(row) }
    }

    /// Wraps a row in a `NavigationLink` only when its name resolved.
    @ViewBuilder
    private func linked<Content: View>(_ row: LedgerSummary.Row,
                                       @ViewBuilder content: () -> Content) -> some View {
        if let entry = resolved[row.key] {
            NavigationLink(value: Route.artist(entry)) {
                content()
            }
            .buttonStyle(.plain)
        } else {
            content()
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

    // --- the nice list (`.plainVoice`) -----------------------------------------

    /// `.nice li { grid-template-columns: 22px 1fr 62px 40px }`, and the Mac's
    /// `.nice.ledger-wide` (72/48). Minimum widths, so the columns line up at
    /// the default text size and grow rather than clip at larger ones.
    #if os(macOS)
    private static let playsColumn: CGFloat = 72
    private static let hoursColumn: CGFloat = 48
    private static let rowPadding: CGFloat = 9
    #else
    private static let playsColumn: CGFloat = 62
    private static let hoursColumn: CGFloat = 40
    private static let rowPadding: CGFloat = 11
    #endif

    private func niceList(rows: [LedgerSummary.Row], totals: LedgerSummary.Totals) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // `.sec h3`: heavy 22, sentence case.
            Text(theme.copy.ledgerTitle)
                .font(theme.type.section(22))
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 6)

            // `.totals`: two figures, 22pt apart.
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                figureText(totals.hours, valueSize: 17)
                figureText(totals.artists, valueSize: 17)
            }
            .font(theme.type.body(14))
            .foregroundStyle(theme.palette.textSecondary)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    hairline
                    linked(row) { niceRow(row) }
                }
                if !rows.isEmpty { hairline }
            }
        }
    }

    private func niceRow(_ row: LedgerSummary.Row) -> some View {
        HStack(spacing: 12) {
            CheckedBox()
            Text(row.displayName)
                .font(theme.type.title(16))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The numbers outrank the name, so a long name truncates first.
            Group {
                figureText(row.plays, valueSize: 14)
                    .frame(minWidth: Self.playsColumn, alignment: .trailing)
                figureText(row.hours, valueSize: 14)
                    .frame(minWidth: Self.hoursColumn, alignment: .trailing)
            }
            .font(theme.type.body(14))
            .foregroundStyle(theme.palette.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.vertical, Self.rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "**41** plays": the value in snow at weight 600 (800 and a larger size
    /// on the totals line), the unit in the surrounding slush.
    private func figureText(_ figure: LedgerSummary.Figure, valueSize: CGFloat) -> Text {
        let weight: Font.Weight = valueSize > 14 ? .heavy : .semibold
        let value = Text(figure.value)
            .font(theme.type.body(valueSize).weight(weight))
            .foregroundStyle(theme.palette.textPrimary)
        return Text("\(value) \(figure.unit)")
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

/// `.box`: a 22pt rounded square outlined in slush, holding a check in snow.
/// Every row on the nice list is checked — being on it is the point.
private struct CheckedBox: View {
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(theme.palette.textSecondary, lineWidth: 1.5)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(theme.palette.textPrimary)
            }
            .accessibilityHidden(true)
    }
}
