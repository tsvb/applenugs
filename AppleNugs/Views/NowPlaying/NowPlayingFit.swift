import Foundation

/// Uniform scale-to-fit for now-playing parts whose proportions ARE the theme
/// (Click Wheel's satellite cluster around the wheel): they shrink as a whole
/// rather than reflow. Pure Foundation so the host-free tests can cover it.
enum NowPlayingFit {

    /// The largest scale in `0...1` at which `natural` fits inside `available`.
    ///
    /// An axis only constrains when both its available and natural values are
    /// finite and positive. Anything else — an unmeasured 0, a negative, NaN,
    /// or `.infinity` (deliberately unconstrained) — leaves that axis out, so
    /// a first layout pass that hasn't measured yet never shrinks anything.
    /// The result never exceeds 1: parts don't grow past their natural size.
    static func scale(available: CGSize, natural: CGSize) -> CGFloat {
        let fit = min(1,
                      ratio(available.width, natural.width),
                      ratio(available.height, natural.height))
        return fit.isFinite ? max(0, fit) : 1
    }

    private static func ratio(_ available: CGFloat, _ natural: CGFloat) -> CGFloat {
        guard available.isFinite, natural.isFinite, available > 0, natural > 0 else { return 1 }
        return available / natural
    }
}
