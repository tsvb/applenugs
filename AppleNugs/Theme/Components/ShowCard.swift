import SwiftUI

/// A saved-show card: cover art (or the themed placeholder) over a title and
/// artist line. Reused by the Favorites view grid and the Home favorites strip.
struct ShowCard: View {
    @Environment(\.theme) private var theme
    let show: FavShow
    var width: CGFloat = 140

    private var plain: Bool { theme.caps.contains(.plainVoice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArt(url: show.imageURL.flatMap { URL(string: $0) })
                .frame(width: width)
            // Yeti (`.plainVoice`): the poster rule cut square — title heavy
            // 15, artist slush (the flat cover + keyline is `CoverArt`'s).
            Text(show.title)
                .font(plain ? theme.type.title(15) : theme.type.body(12))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(show.artistName)
                .font(plain ? theme.type.body(13) : theme.type.numeric(10))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}
