import SwiftUI

/// The Mac transport bar's now-playing block, token-styled. Yeti
/// (`.plainVoice`) draws its own variant with an art chip.
struct StandardNowPlaying: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var player: PlayerService { app.player }

    var body: some View {
        if let track = player.current, theme.caps.contains(.plainVoice) {
            plainBlock(track)
        } else if let track = player.current {
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

    /// Yeti's block (`.plainVoice`), as drawn in the surfaces page's Mac
    /// transport bar: a flat 42pt art chip (no bubble — that is the
    /// miniplayer's), the title, the meta line, and the queue position said
    /// plainly ("3 of 24") in lamp-off gray under them.
    private func plainBlock(_ track: QueueTrack) -> some View {
        HStack(spacing: 10) {
            ArtChip(image: player.nowPlayingImage,
                    fallbackText: track.artist ?? track.title ?? "?",
                    size: 42)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title ?? "Unknown track")
                    .font(theme.type.title(15))
                    .lineLimit(1)
                NowPlayingMetaText(track: track)
                    .font(theme.type.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
                Text("\(player.index + 1) of \(player.queue.count)")
                    .font(theme.type.numeric(11))
                    .foregroundStyle(theme.palette.textIdle)
                    .lineLimit(1)
            }
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
