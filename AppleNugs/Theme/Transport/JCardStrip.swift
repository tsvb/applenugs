import SwiftUI

/// Shoebox's signature now-playing block: a cassette J-card spine — cover chip
/// with a cream keyline, a hairline divider, the title in liner-note serif and
/// the metadata typed out in tracked small caps.
struct JCardStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var player: PlayerService { app.player }

    var body: some View {
        if let track = player.current {
            HStack(spacing: 10) {
                ArtChip(image: player.nowPlayingImage,
                        fallbackText: track.artist ?? track.title ?? "?",
                        size: 42)
                Rectangle()
                    .fill(theme.palette.hairline)
                    .frame(width: 1, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title ?? "Unknown track")
                        .font(theme.type.title(15))
                        .lineLimit(1)
                    Text(NowPlayingMeta.line(track).uppercased())
                        .font(theme.type.numeric(9))
                        .tracking(0.9)
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                }
            }
        } else {
            Text(theme.copy.nowPlaying)
                .font(theme.type.title(13))
                .italic()
                .foregroundStyle(theme.palette.textIdle)
        }
    }
}
