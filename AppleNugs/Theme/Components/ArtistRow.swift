import SwiftUI

/// One row in the artist list. Always a monogram tile + name (artists carry no
/// art); Shoebox adds an index-letter tab on the leading edge.
struct ArtistRow: View {
    @Environment(\.theme) private var theme
    let entry: ArtistEntry

    var body: some View {
        HStack(spacing: 10) {
            if theme.caps.contains(.indexLetterTab) {
                Text(entry.name.first.map { String($0).uppercased() } ?? "·")
                    .font(theme.type.numeric(11))
                    .foregroundStyle(theme.palette.textIdle)
                    .frame(width: 12, alignment: .center)
            }
            MonogramTile(text: entry.name, size: 28)
            Text(entry.name)
                .font(theme.type.body(14))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
