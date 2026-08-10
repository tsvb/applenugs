import SwiftUI

/// The pill's bottom edge, doubling as the seek track.
///
/// **A leaf view.** The ~4Hz `currentTime` dependency registers here and
/// nowhere else in the pill, so the capsule's body, the themed slot and the
/// control cluster do not re-evaluate on every playback tick. The pill is on
/// screen constantly — hoisting this read would re-diff the whole tab shell
/// four times a second.
///
/// The drag has a `minimumDistance` so a plain tap falls through to the pill's
/// container tap (which opens the full-screen player). While dragging, the
/// thumb holds the dragged value so the ticks cannot yank it back — the same
/// trick `TransportBar.seekBlock` and `MiniPlayerScrubTrack` use.
struct PillSeekEdge: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var player: PlayerService { app.player }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                // Invisible catcher: 2.5pt is untappable.
                Color.clear
                    .contentShape(Rectangle())

                theme.palette.textPrimary.opacity(0.16)
                    .frame(height: PillLayout.seekEdgeHeight)

                theme.palette.accent
                    .frame(width: geo.size.width * fraction,
                           height: PillLayout.seekEdgeHeight)
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard player.duration > 0 else { return }
                        if !scrubbing {
                            scrubbing = true
                            scrubValue = player.currentTime
                        }
                        let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                        scrubValue = ratio * player.duration
                    }
                    .onEnded { _ in
                        guard scrubbing else { return }
                        player.seek(to: scrubValue)
                        scrubbing = false
                    }
            )
        }
        .frame(height: PillLayout.seekHitHeight)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(TransportBar.format(seconds: position))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.seek(by: 30)
            case .decrement: player.seek(by: -15)
            @unknown default: break
            }
        }
    }

    private var position: Double {
        scrubbing ? scrubValue : player.currentTime
    }

    private var fraction: Double {
        guard player.duration > 0 else { return 0 }
        return min(max(position / player.duration, 0), 1)
    }
}
