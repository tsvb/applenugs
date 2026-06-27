import SwiftUI

/// Tiny row thumbnail. Videos are 16:9-ish (wider); albums/shows are square.
/// A miss/placeholder shows a kind glyph so empty rows still read.
struct CrateThumb: View {
    let url: URL?
    let kind: CrateKind

    @Environment(\.theme) private var theme

    private var isWide: Bool { kind == .video }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: isWide ? 40 : 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(theme.palette.raised)
            .overlay(
                Image(systemName: kind == .video ? "play.fill" : "music.note")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.palette.accent.opacity(0.7))
            )
    }
}

#Preview("CrateThumb") {
    HStack(spacing: 12) {
        CrateThumb(url: nil, kind: .video)
        CrateThumb(url: nil, kind: .album)
        CrateThumb(url: nil, kind: .show)
    }
    .padding()
}
