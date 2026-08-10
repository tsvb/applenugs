import SwiftUI

/// The pill's trailing control cluster. Which buttons exist is `PillLayout`'s
/// decision, not this view's — at `.inline` the system hands us 76pt less and
/// the skip intervals are what give way.
///
/// Reads no `currentTime`: every control depends on discrete player state only.
struct PillTransportControls: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    let slot: PillLayout.Slot

    private var player: PlayerService { app.player }

    var body: some View {
        HStack(spacing: PillLayout.controlSpacing) {
            ForEach(PillLayout.controls(for: slot), id: \.self) { control in
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
                if player.isBuffering {
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
