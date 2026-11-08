import SwiftUI

/// Player-style header: a reused EQ/VU strip, an LCD-style summary panel, and
/// the Follow control. The LCD line truncates if it overflows (a scrolling
/// marquee is a deferred enhancement).
///
/// Yeti (`.plainVoice`) drops the player costume — no LCD pill, no bars (the
/// spec's EqualizerBars table: this site gets nothing under `.stickers`): the
/// artist's name as a large title, the counts under it as plain type, and
/// Follow as a frost-outlined button.
struct CrateHeader: View {
    let artist: ArtistEntry
    let albumCount: Int
    let videoCount: Int
    let showCount: Int

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        if theme.caps.contains(.plainVoice) {
            yetiHeader
        } else {
            HStack(spacing: 12) {
                // `.stickers` first: Yeti never reaches this branch, but the
                // table is explicit — no bars here under `.stickers`.
                if !theme.caps.contains(.stickers) {
                    EqualizerBars(isPlaying: app.player.isPlaying)
                }
                lcd
                followButton
            }
        }
    }

    private var lcd: some View {
        Text(summary)
            .font(theme.type.numeric(12))
            .foregroundStyle(theme.palette.accent)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.palette.base.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.palette.hairline, lineWidth: 0.5))
            .accessibilityLabel(summary)
    }

    private var summary: String {
        let name = theme.caps.contains(.condensedHeaders) ? artist.name.uppercased() : artist.name
        var parts: [String] = []
        if videoCount > 0 { parts.append("\(videoCount) videos") }
        if showCount > 0 { parts.append("\(showCount) shows") }
        if albumCount > 0 { parts.append("\(albumCount) albums") }
        let tail = parts.joined(separator: " · ")
        return tail.isEmpty ? name : "\(name) — \(tail)"
    }

    private var followButton: some View {
        let fav = app.favorites.isArtistFavorited(artist.id)
        return Button {
            app.favorites.toggleArtist(id: artist.id, name: artist.name)
        } label: {
            Label(fav ? "Following" : "Follow", systemImage: fav ? "star.fill" : "star")
                .font(theme.type.body(12))
        }
        .buttonStyle(.bordered)
        .tint(fav ? theme.palette.accent : theme.palette.textSecondary)
        .help(fav ? "Unfollow artist" : "Follow artist")
    }

    // --- Yeti ---------------------------------------------------------------

    /// The surfaces sheet's artist page: `.large-title`, then `.crate-head`
    /// (counts left, Follow right). The counts row is as tall as the 30pt
    /// button whether or not any counts have arrived, so paging in the
    /// catalog never moves the list below it.
    private var yetiHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(artist.name)
                .font(theme.type.hero(34))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                countsLine
                    .frame(maxWidth: .infinity, alignment: .leading)
                yetiFollowButton
            }
        }
    }

    /// "**340** shows · **12** videos · **5** albums" — snow figures in slush
    /// type, in the sheet's order; a kind with nothing yet is left out.
    private var countsLine: some View {
        let parts = [(showCount, "show", "shows"),
                     (videoCount, "video", "videos"),
                     (albumCount, "album", "albums")]
            .filter { $0.0 > 0 }
        // Text interpolation, not `Text + Text` (deprecated), as in
        // `ListeningLedger.figureText`.
        var line = Text(verbatim: "")
        for (i, part) in parts.enumerated() {
            let figure = Text(verbatim: "\(part.0)")
                .fontWeight(.heavy)
                .foregroundStyle(theme.palette.textPrimary)
            let unit = part.0 == 1 ? part.1 : part.2
            line = i == 0 ? Text("\(figure) \(unit)") : Text("\(line) · \(figure) \(unit)")
        }
        return line
            .font(theme.type.body(14))
            .foregroundStyle(theme.palette.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// `.btn.quiet.sm`: a frost ring, "Following" with a check; unfollowed it
    /// reads "Follow" with a plus.
    private var yetiFollowButton: some View {
        let fav = app.favorites.isArtistFavorited(artist.id)
        return Button {
            app.favorites.toggleArtist(id: artist.id, name: artist.name)
        } label: {
            Label(fav ? "Following" : "Follow", systemImage: fav ? "checkmark" : "plus")
        }
        .buttonStyle(.yetiSecondary)
        .controlSize(.small)
        .fixedSize()
        .help(fav ? "Unfollow artist" : "Follow artist")
    }
}
