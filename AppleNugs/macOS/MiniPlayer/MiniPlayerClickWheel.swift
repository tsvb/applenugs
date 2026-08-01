import SwiftUI

/// Click Wheel's miniplayer: a track card over a compact dial.
///
/// An iPod's defining feature is the screen above the wheel, so unlike the
/// full-screen iOS `ClickWheelScreen` this compact form still leads with the
/// cover. Monochrome throughout — the art is the only pigment.
struct MiniPlayerClickWheel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var player: PlayerService { app.player }

    var body: some View {
        VStack(spacing: 10) {
            trackCard
            MiniPlayerScrubTrack(fillColor: theme.palette.textPrimary)
            wheel
        }
        .padding(10)
    }

    private var trackCard: some View {
        HStack(spacing: 10) {
            ArtChip(image: player.nowPlayingImage,
                    fallbackText: player.current?.artist ?? player.current?.title ?? "?",
                    size: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                if let artist = player.current?.artist {
                    Text(artist)
                        .font(theme.type.body(11))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(player.current?.title ?? "Unknown track")
                    .font(theme.type.title(14))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.palette.raised)
        }
    }

    private var wheel: some View {
        ZStack {
            Circle()
                .fill(theme.palette.raised)
                .overlay { Circle().strokeBorder(theme.palette.hairline, lineWidth: 1) }

            VStack {
                Text("MENU")
                    .font(theme.type.numeric(8).weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.vertical, 12)

            HStack {
                ringButton("backward.fill", label: "Previous track", help: "Previous (p)",
                           enabled: player.hasPrevious) { player.previous() }
                Spacer()
                ringButton("forward.fill", label: "Next track", help: "Next (n)",
                           enabled: player.hasNext) { player.next() }
            }
            .padding(.horizontal, 10)

            HapticButton(.transportToggle) {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(theme.palette.base)
                    if player.isBuffering {
                        ProgressView().controlSize(.small).tint(theme.palette.textPrimary)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.palette.textPrimary)
                    }
                }
                .frame(width: 54, height: 54)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)
            .help("Play / pause (space)")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityValue(player.isBuffering ? "Buffering" : "")
        }
        .frame(width: 150, height: 150)
    }

    private func ringButton(_ system: String,
                            label: String,
                            help: String,
                            enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        HapticButton(.transportStep, action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.palette.textPrimary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(label)
    }
}
