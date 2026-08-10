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
///
/// The **visible** track spans the pill's full width — trimming it would
/// make it lie about how much of the show is left. The **hit** region does
/// not: at `PillLayout.seekHitHeight` (20pt) tall against an ~32pt-tall pill,
/// a full-width strip sits on top of most of the transport buttons' vertical
/// extent, so a tap aimed at play/pause and landing a few points low would
/// hit this catcher instead (measured — see the branch's final review).
/// `hitTrailingInset` pulls the catcher's trailing edge in to stop before
/// that cluster; the decorative track layers get `.allowsHitTesting(false)`
/// so they can't reintroduce the same shadow now that they're wider than the
/// catcher. A drag that begins inside the narrower catcher can still be
/// carried by finger past its edge — SwiftUI keeps delivering move events to
/// the gesture that started — so seeking to the very end still works.
struct PillSeekEdge: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    /// How far the invisible hit strip is pulled in from the trailing edge,
    /// so it stops before the transport-control cluster. See the type doc.
    let hitTrailingInset: CGFloat

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var player: PlayerService { app.player }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                // Invisible catcher: 2.5pt is untappable, so this enlarged
                // frame is what actually governs where a touch can land.
                // Narrower than the track (see `hitTrailingInset`) so it
                // doesn't shadow the transport buttons.
                Color.clear
                    .frame(width: max(geo.size.width - hitTrailingInset, 0))
                    .contentShape(Rectangle())

                theme.palette.textPrimary.opacity(0.16)
                    .frame(height: PillLayout.seekEdgeHeight)
                    .allowsHitTesting(false)

                theme.palette.accent
                    .frame(width: geo.size.width * fraction,
                           height: PillLayout.seekEdgeHeight)
                    .allowsHitTesting(false)
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
