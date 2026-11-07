import SwiftUI

/// The compact miniplayer for Soundboard (`.standard`) and Shoebox (`.jCard`),
/// and Yeti (`.standard` + `.blisterPack`).
///
/// One view, not two: their differences are token reads — a J-card spine rule,
/// tracked small caps, an outline play button instead of a filled one — in the
/// same spirit as `DashboardPanel.sectionHeader` branching on
/// `.condensedHeaders`. Yeti's are capability reads: the art in a small blister
/// bubble with the title beside it (foil sweep on a new track) and the venue
/// on its own line below (`.blisterPack`), and the play sticker as the triad's
/// middle button (`.stickers`).
struct MiniPlayerStandard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    private var player: PlayerService { app.player }
    private var isJCard: Bool { theme.transport == .jCard }
    private var pack: Bool { theme.caps.contains(.blisterPack) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pack {
                packInfo
            } else {
                infoRow
            }
            MiniPlayerScrubTrack()
            if theme.caps.contains(.stickers) {
                MiniPlayerTransportTriad(style: .sticker, glyphSize: 18, playDiameter: 46)
            } else {
                MiniPlayerTransportTriad(style: isJCard ? .outline : .filled)
            }
        }
        .padding(10)
        .background(Color.clear.artWash(theme.washStyle, color: artColor))
    }

    /// Yeti's info block, as drawn in the first sheet's `.mini`: a 100pt small
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

    private var infoRow: some View {
        HStack(spacing: 10) {
            ArtChip(image: player.nowPlayingImage,
                    fallbackText: player.current?.artist ?? player.current?.title ?? "?",
                    size: 56)
                .accessibilityHidden(true)

            if isJCard {
                Rectangle()
                    .fill(theme.palette.hairline)
                    .frame(width: 1, height: 40)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? "Unknown track")
                    .font(theme.type.title(15))
                    .lineLimit(1)
                    .truncationMode(.tail)
                meta(fields: [.artist])
                meta(fields: [.show])
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One field of the meta line. Nothing renders when the field is absent, so
    /// the block keeps the height it had when these were `if let` Texts.
    @ViewBuilder
    private func meta(fields: [NowPlayingMetaLine.Field]) -> some View {
        let line = NowPlayingMetaText(track: player.current, fields: fields,
                                      casing: isJCard ? .upper : .asIs)
        if isJCard {
            line
                .font(theme.type.numeric(9))
                .tracking(0.9)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            line
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
