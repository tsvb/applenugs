import SwiftUI

/// An artist's photo clipped to a circle — Apple Music's shape for an artist,
/// apart from the square show covers — filling the width it's given. The
/// monogram stands in while the photo loads, when there is none, and when it
/// fails, so a list with no network still reads as artists, not holes.
///
/// Photos come from the v1 catalog's `avatarImage` (`Catalog.artistAvatars`).
/// Used by `ArtistTile` (Home, Favorites), the Artists list, the artist page
/// header and search results.
struct ArtistPortrait: View {
    @Environment(\.theme) private var theme

    let url: URL?
    let name: String

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            monogram(side)
                        }
                    }
                } else {
                    monogram(side)
                }
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(theme.palette.hairline, lineWidth: 1) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func monogram(_ side: CGFloat) -> some View {
        MonogramTile(text: name, size: side)
    }
}
