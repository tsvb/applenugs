import SwiftUI

/// The Dashboard inspector's compact miniplayer.
///
/// The art in a small blister bubble with the title beside it (foil sweep on a
/// new track), the venue on its own line below, and the play sticker as the
/// triad's middle button.
struct MiniPlayerStandard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var player: PlayerService { app.player }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            packInfo
            MiniPlayerScrubTrack()
            MiniPlayerTransportTriad()
        }
        .padding(10)
    }

    /// The info block, as drawn in the first sheet's `.mini`: a 100pt small
    /// bubble (no card — the bubble alone is the Mac miniplayer's pack), the
    /// title beside it with the one-shot foil sweep, the artist under it, and
    /// the venue on a full-width line below — which also gives a long venue
    /// the column's whole width.
    private var packInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                BlisterBubble(metrics: .small) {
                    PackArt(image: player.nowPlayingImage,
                            monogram: player.current?.artist ?? player.current?.title ?? "?")
                }
                .frame(width: Self.bubbleSide, height: Self.bubbleSide)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(player.current?.title ?? "Unknown track")
                        .font(theme.type.title(24))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foilSweep(identity: player.current?.trackId, isPlaying: player.isPlaying)
                    NowPlayingMetaText(track: player.current, fields: [.artist])
                        .font(theme.type.body(14).weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            NowPlayingMetaText(track: player.current, fields: [.show])
                .font(theme.type.body(12))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// The sheet's `.mini` bubble: 100pt in a 340pt inspector column.
    private static let bubbleSide: CGFloat = 100
}
