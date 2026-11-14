import SwiftUI

/// The artist page header: the artist's name as a large title, the counts under
/// it as plain type, and Follow as a frost-outlined button. No LCD pill and no
/// bars (the stage-c row-sticker table: this site gets nothing).
struct CrateHeader: View {
    let artist: ArtistEntry
    let albumCount: Int
    let videoCount: Int
    let showCount: Int

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    /// The surfaces sheet's artist page: `.large-title`, then `.crate-head`
    /// (counts left, Follow right). The counts row is as tall as the 30pt
    /// button whether or not any counts have arrived, so paging in the
    /// catalog never moves the list below it.
    var body: some View {
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
                followButton
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
    private var followButton: some View {
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
