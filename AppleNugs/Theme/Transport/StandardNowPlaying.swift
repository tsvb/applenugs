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
                NowPlayingMetaText(track: track)
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
///
/// The segmentation lives in `NowPlayingMetaLine` (pure, unit-tested) so the
/// artist and the show can be individually linkable; this stays as the plain-string
/// accessor for callers that only want text.
enum NowPlayingMeta {
    static func line(_ track: QueueTrack) -> String {
        NowPlayingMetaLine.text(artist: track.artist, show: track.show)
    }

    /// The runs, for `NowPlayingMetaText`.
    static func segments(_ track: QueueTrack?,
                         fields: [NowPlayingMetaLine.Field] = [.artist, .show],
                         mode: NowPlayingMetaLine.Mode = .joined,
                         casing: NowPlayingMetaLine.Casing = .asIs) -> [NowPlayingMetaLine.Segment] {
        guard let track else { return [] }
        return NowPlayingMetaLine.segments(artist: track.artist, show: track.show,
                                           showId: track.showId,
                                           fields: fields, mode: mode, casing: casing)
    }
}
