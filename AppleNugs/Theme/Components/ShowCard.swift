import SwiftUI

/// A saved-show card: cover art (or the themed placeholder) over a title and
/// artist line. Reused by the Favorites view grid and the Home favorites strip.
struct ShowCard: View {
    @Environment(\.theme) private var theme
    let show: FavShow
    var width: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArt(url: show.imageURL.flatMap { URL(string: $0) })
                .frame(width: width)
            Text(show.title)
                .font(theme.type.body(12))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(show.artistName)
                .font(theme.type.numeric(10))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}
