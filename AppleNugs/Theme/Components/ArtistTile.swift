import SwiftUI

/// An artist as a tile: the photo in a circle (Apple Music's shape for an
/// artist, so it reads apart from square show covers), the name centered below,
/// on a raised shelf. Home's crate (iOS), Home's favorites shelf and the
/// Favorites page use it.
///
/// Names are never cut off for ~98% of the catalog: up to three lines,
/// shrinking to 85% before truncating (median name 14 characters, 1 in 10 past
/// 27, the longest 62). Two lines are always reserved, and the tile stretches
/// to its row, so a row of short and long names lines up.
struct ArtistTile: View {
    @Environment(\.theme) private var theme

    let name: String
    /// The photo (`Catalog.artistAvatars`); nil shows the monogram.
    let photo: URL?

    /// Grid columns that seat these tiles: three across a portrait phone,
    /// five across the flat Duo's Home column.
    static let column = GridItem.Size.adaptive(minimum: 92, maximum: 132)
    static let spacing: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 8) {
            ArtistPortrait(url: photo, name: name)
            ZStack(alignment: .top) {
                // Holds two lines' height at the current Dynamic Type size.
                Text(" ").lineLimit(2, reservesSpace: true).hidden()
                Text(name)
                    .foregroundStyle(theme.palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            .font(theme.type.body(13))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { shape.fill(theme.palette.raised) }
        .contentShape(shape)
    }
}
