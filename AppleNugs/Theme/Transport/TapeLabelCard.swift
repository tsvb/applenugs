import SwiftUI

/// Tape Room's signature now-playing block: a cover chip + title/meta, with a
/// thin amber "tape counter" under-rule that fills as the track plays.
struct TapeLabelCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var player: PlayerService { app.player }

    var body: some View {
        if let track = player.current {
            HStack(spacing: 10) {
                ArtChip(image: player.nowPlayingImage,
                        fallbackText: track.artist ?? track.title ?? "?",
                        size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title ?? "Unknown track")
                        .font(theme.type.title(14))
                        .lineLimit(1)
                    Text(NowPlayingMeta.line(track))
                        .font(theme.type.numeric(10))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                    underRule
                }
            }
        } else {
            Text(theme.copy.nowPlaying)
                .font(.callout)
                .foregroundStyle(theme.palette.textIdle)
        }
    }

    private var underRule: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.palette.hairline)
                Capsule().fill(theme.palette.accent)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 2)
    }

    private var progress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return min(max(CGFloat(player.currentTime / player.duration), 0), 1)
    }
}
