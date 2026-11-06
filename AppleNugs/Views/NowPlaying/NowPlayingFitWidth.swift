import SwiftUI

extension View {
    /// Shrinks a rigid row (a transport row of fixed-size buttons) as a unit to
    /// fit the width it's offered, less `margin` on each side, instead of
    /// letting it overflow. Never grows it: where the row fits — every current
    /// iPhone, the macOS Now Playing window at its default size — the scale is
    /// exactly 1 and the row lays out as it always did. It bites in a narrow
    /// column such as the ~300pt player column beside the queue on iPhone Duo's
    /// upright inner display.
    ///
    /// Click Wheel's `controlPad` pattern, with the natural size MEASURED rather
    /// than hard-coded (SF Symbol advances aren't known up front): the row is
    /// measured at its ideal size before `scaleEffect`, which changes only the
    /// drawing, so the measurement doesn't depend on the scale; the available
    /// width is measured on the full-width container, whose width is the
    /// proposal and so doesn't depend on the scale either. No measure → scale →
    /// re-measure loop. The frame after `scaleEffect` is what gives the layout
    /// back the space.
    ///
    /// Until both are measured the scale is 1 (`NowPlayingFit` treats 0 as
    /// unconstrained). Measure only rigid content: nothing here reads
    /// `player.currentTime`, and the row must not either.
    func nowPlayingFitWidth(margin: CGFloat) -> some View {
        modifier(NowPlayingFitWidth(margin: margin))
    }
}

private struct NowPlayingFitWidth: ViewModifier {
    let margin: CGFloat

    @State private var natural: CGSize = .zero
    @State private var available: CGFloat = 0

    private var scale: CGFloat {
        NowPlayingFit.scale(available: CGSize(width: available - 2 * margin, height: .infinity),
                            natural: natural)
    }

    func body(content: Content) -> some View {
        let scale = scale
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
            .scaleEffect(scale)
            .frame(width: natural.width > 0 ? natural.width * scale : nil,
                   height: natural.height > 0 ? natural.height * scale : nil)
            // `minWidth: 0` matters: a flexible frame with only a max reports
            // max(child, proposal), so on the first (unscaled) pass a row wider
            // than its column would make the container report the ROW's width
            // and the scale would stay 1. With a 0 minimum it reports the
            // proposal whatever the child does.
            .frame(minWidth: 0, maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
    }
}
