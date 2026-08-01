import SwiftUI

/// The Receiver's miniplayer: a tuner faceplate.
///
/// Deliberately carries **no cover art** — a hi-fi tuner has none, and the L/R
/// VU meters are this theme's visual subject. This is the one variant that
/// departs from the miniplayer's usual art-plus-text shape.
struct MiniPlayerFaceplate: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var player: PlayerService { app.player }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            receivingLine
            titleBlock
            VUMeter(isPlaying: player.isPlaying)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            MiniPlayerScrubTrack(fillColor: theme.palette.accent)
            knurledTriad
        }
        .padding(10)
        .background {
            LinearGradient(colors: [theme.palette.raised, theme.palette.base],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var receivingLine: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(theme.palette.accent)
                .frame(width: 5, height: 5)
                .shadow(color: player.isPlaying ? theme.palette.accent : .clear, radius: 4)
            Text("RECEIVING")
                .font(theme.type.numeric(9).weight(.bold))
                .tracking(1.6)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(theme.palette.accent.opacity(player.isPlaying ? 1 : 0.5))
        .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((player.current?.title ?? "Unknown track").uppercased())
                .font(theme.type.numeric(13).weight(.bold))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let artist = player.current?.artist {
                Text(artist.uppercased())
                    .font(theme.type.numeric(9))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var knurledTriad: some View {
        HStack(spacing: 0) {
            KnurledButton(system: "backward.fill", size: 30, glow: false) {
                player.previous()
            }
            .disabled(!player.hasPrevious)
            .accessibilityLabel("Previous track")

            Spacer(minLength: 8)

            KnurledButton(system: player.isPlaying ? "pause.fill" : "play.fill",
                          size: 30,
                          glow: player.isPlaying) {
                player.togglePlayPause()
            }
            .disabled(player.current == nil)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityValue(player.isBuffering ? "Buffering" : "")

            Spacer(minLength: 8)

            KnurledButton(system: "forward.fill", size: 30, glow: false) {
                player.next()
            }
            .disabled(!player.hasNext)
            .accessibilityLabel("Next track")
        }
        .frame(maxWidth: .infinity)
    }
}
