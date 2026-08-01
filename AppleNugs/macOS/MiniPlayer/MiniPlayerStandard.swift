import SwiftUI

/// The compact miniplayer for Soundboard (`.standard`) and Shoebox (`.jCard`).
///
/// One view, not two: their differences are token reads — a J-card spine rule,
/// tracked small caps, an outline play button instead of a filled one — in the
/// same spirit as `DashboardPanel.sectionHeader` branching on
/// `.condensedHeaders`.
struct MiniPlayerStandard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    private var player: PlayerService { app.player }
    private var isJCard: Bool { theme.transport == .jCard }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow
            MiniPlayerScrubTrack()
            MiniPlayerTransportTriad(style: isJCard ? .outline : .filled)
        }
        .padding(10)
        .background(Color.clear.artWash(theme.washStyle, color: artColor))
    }

    private var infoRow: some View {
        HStack(spacing: 10) {
            ArtChip(image: player.nowPlayingImage,
                    fallbackText: player.current?.artist ?? player.current?.title ?? "?",
                    size: 56)

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
                if let artist = player.current?.artist {
                    meta(artist)
                }
                if let show = player.current?.show {
                    meta(show)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func meta(_ text: String) -> some View {
        if isJCard {
            Text(text.uppercased())
                .font(theme.type.numeric(9))
                .tracking(0.9)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
