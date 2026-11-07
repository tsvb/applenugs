import SwiftUI

/// The pill's trailing control cluster. Which buttons exist is `PillLayout`'s
/// decision, not this view's — the caller passes the set it computed from the
/// slot and the measured width, so a narrow accessory (`.inline`, or iPhone
/// Duo's outer display) sheds the skip intervals rather than the title.
///
/// Reads no `currentTime`: every control depends on discrete player state only.
struct PillTransportControls: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    let controls: [PillLayout.Control]

    /// How the play/pause control draws. The pill always uses `.glyph`; the
    /// expanded panel passes `.sticker` under `.stickers` (Yeti's play sticker,
    /// which is wider than the pill's control slot, so it keeps its own frame).
    enum PlayControl: Equatable {
        case glyph
        case sticker(PlaySticker.Size)
    }
    var playControl: PlayControl = .glyph

    private var player: PlayerService { app.player }

    var body: some View {
        HStack(spacing: PillLayout.controlSpacing) {
            ForEach(controls, id: \.self) { control in
                button(for: control)
            }
        }
        .foregroundStyle(theme.palette.textPrimary)
    }

    @ViewBuilder
    private func button(for control: PillLayout.Control) -> some View {
        switch control {
        case .previous:
            HapticButton(.transportStep) { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .frame(width: PillLayout.controlWidth)
            }
            .buttonStyle(.plain)
            .disabled(!player.hasPrevious)
            .accessibilityLabel("Previous track")

        case .back15:
            HapticButton(.transportStep) { player.seek(by: -15) } label: {
                Image(systemName: "gobackward.15")
                    .frame(width: PillLayout.controlWidth)
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)
            .accessibilityLabel("Back 15 seconds")

        case .playPause:
            HapticButton(.transportToggle) { player.togglePlayPause() } label: {
                if case .sticker(let size) = playControl {
                    // The spinner sits inside the sticker's own disc, so the
                    // control never changes size while buffering.
                    PlaySticker(isPlaying: player.isPlaying,
                                isBuffering: player.isBuffering,
                                size: size)
                } else if player.isBuffering {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: PillLayout.controlWidth)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: PillLayout.controlWidth)
                }
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityValue(player.isBuffering ? "Buffering" : "")

        case .forward30:
            HapticButton(.transportStep) { player.seek(by: 30) } label: {
                Image(systemName: "goforward.30")
                    .frame(width: PillLayout.controlWidth)
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)
            .accessibilityLabel("Forward 30 seconds")

        case .next:
            HapticButton(.transportStep) { player.next() } label: {
                Image(systemName: "forward.fill")
                    .frame(width: PillLayout.controlWidth)
            }
            .buttonStyle(.plain)
            .disabled(!player.hasNext)
            .accessibilityLabel("Next track")
        }
    }
}
