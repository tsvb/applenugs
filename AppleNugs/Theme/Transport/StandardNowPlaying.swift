import SwiftUI

/// The original now-playing block, token-styled. Used by Soundboard and as the
/// fallback for The Receiver until its faceplate ships.
struct StandardNowPlaying: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var player: PlayerService { app.player }

    var body: some View {
        if let track = player.current {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(player.index + 1)/\(player.queue.count)")
                        .font(theme.type.numeric(10))
                        .foregroundStyle(theme.palette.textSecondary)
                    Text(track.title ?? "Unknown track")
                        .font(theme.type.title(14))
                        .lineLimit(1)
                }
                Text(NowPlayingMeta.line(track))
                    .font(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Text(theme.copy.nowPlaying)
                .font(.callout)
                .foregroundStyle(theme.palette.textIdle)
        }
    }
}

/// Shared helper for the "artist · show" subtitle.
enum NowPlayingMeta {
    static func line(_ track: QueueTrack) -> String {
        [track.artist, track.show].compactMap { $0 }.joined(separator: " · ")
    }
}
