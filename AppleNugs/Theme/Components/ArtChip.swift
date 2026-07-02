import SwiftUI

/// A small now-playing cover chip: the cached cover image when available, a
/// MonogramTile otherwise, with a thin theme keyline.
struct ArtChip: View {
    @Environment(\.theme) private var theme
    let image: PlatformImage?
    let fallbackText: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                            .strokeBorder(theme.palette.textPrimary.opacity(0.15), lineWidth: 1)
                    }
            } else {
                MonogramTile(text: fallbackText, size: size)
            }
        }
    }
}
