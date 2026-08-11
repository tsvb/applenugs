import SwiftUI

/// The pill's position indicator: a thin arc around the leading slot's cover.
///
/// **A leaf view, and the pill's only reader of `player.currentTime`.** The
/// playback clock ticks ~4Hz and the pill is on screen constantly, so this
/// read must register here and nowhere else. Hoisting it into
/// `PillLeadingSlot` or `NowPlayingPill`'s body would re-diff the whole tab
/// shell four times a second. This is the same rule the deleted
/// `PillSeekEdge` followed, and the reason the ring is its own type rather
/// than an inline `.overlay` closure.
///
/// It replaced the old seek edge — a 2.5pt visible track plus a 20pt
/// invisible hit strip for the drag. The ring costs zero horizontal width —
/// the scarce resource in a 360pt accessory —
/// and survives the `.inline` collapse, which is exactly when browsing
/// happens. It is decorative: scrubbing belongs to the expanded panel and the
/// full-screen player, which both have real sliders with numerals and a thumb.
struct PillProgressRing: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    var body: some View {
        // Empty, never full, when the stream reports no duration — see
        // `PillLayout.progressFraction`.
        let fraction = PillLayout.progressFraction(
            currentTime: app.player.currentTime,
            duration: app.player.duration)

        ZStack {
            Circle()
                .strokeBorder(theme.palette.textPrimary.opacity(0.16),
                              lineWidth: PillLayout.ringLineWidth)
            // A zero-length trim under a round cap can still render as a
            // visible dot at 12 o'clock (Core Graphics doesn't always
            // degenerate a zero-length subpath to nothing), which would put
            // an accent pip on a stream that reports no duration — exactly
            // what `progressFraction`'s "empty, never full" guarantee is
            // supposed to prevent. Skip the arc layer entirely at fraction 0
            // rather than trusting the trim to disappear on its own.
            if fraction > 0 {
                Circle()
                    // `strokeBorder` above insets by half the line width on
                    // its own; `stroke` does not, so inset to match or the
                    // two arcs sit on different radii.
                    .inset(by: PillLayout.ringLineWidth / 2)
                    .trim(from: 0, to: fraction)
                    .stroke(theme.effectiveAccent(art: artColor),
                            style: StrokeStyle(lineWidth: PillLayout.ringLineWidth,
                                               lineCap: .round))
                    // Trim starts at 3 o'clock; rotate so the arc grows
                    // clockwise from the top.
                    .rotationEffect(.degrees(-90))
            }
        }
        // Decorative. The pill's own label already says what is playing, the
        // ±15/+30 buttons remain in the control cluster, and both scrub
        // surfaces expose real sliders with an `accessibilityValue`.
        .accessibilityHidden(true)
    }
}
