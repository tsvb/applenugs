import Foundation

/// Which shape the iOS full-screen player takes (`NowPlayingArrangement`):
/// alone, beside its queue via the SDK's fold-aware `ArrangementView`, or
/// beside its queue in explicit columns. Pure Foundation so the host-free
/// tests can cover it.
///
/// - Compact width (every iPhone, iPhone Duo's outer display, Duo Split View
///   halves) → `.single`.
/// - Regular width, wider than tall (Duo inner display unfolded flat) →
///   `.arrangement`, where `ArrangementView` `.split.axes(.horizontal)` splits
///   it 50/50 — or `.columns` when that API isn't available (pre-27.1).
/// - Regular width, at least as tall as wide (Duo inner display UPRIGHT,
///   which the arrangement refuses to split) → `.columns`: the player takes the
///   larger share and the queue a narrower column.
/// - Any regular canvas too narrow for both minimums → `.single`, so an
///   unexpected size never yields a cramped split.
enum NowPlayingColumns {

    enum Layout: Equatable, Sendable {
        case single
        case arrangement
        case columns(queueWidth: CGFloat)
    }

    /// The narrowest player column. Every player is made to fit this: the
    /// Standard transport row and The Receiver's knurled row scale as a unit
    /// below their natural widths, Click Wheel's pad already does.
    static let minPlayerWidth: CGFloat = 300
    /// The queue column's range. Below the minimum, track titles in Up Next
    /// truncate to a few words; above the maximum the extra width is better
    /// spent on the player's artwork.
    static let minQueueWidth: CGFloat = 220
    static let maxQueueWidth: CGFloat = 260

    static func layout(size: CGSize, regular: Bool, supportsArrangement: Bool) -> Layout {
        guard regular, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return .single }
        if size.width > size.height, supportsArrangement { return .arrangement }
        guard let queue = queueWidth(forWidth: size.width) else { return .single }
        return .columns(queueWidth: queue)
    }

    /// The queue column's width for a canvas this wide: whatever is left after
    /// the player's minimum, clamped to the queue's range — so the player gets
    /// every point the queue doesn't need. Nil when both minimums don't fit.
    static func queueWidth(forWidth width: CGFloat) -> CGFloat? {
        guard width.isFinite, width >= minPlayerWidth + minQueueWidth else { return nil }
        return min(max(width - minPlayerWidth, minQueueWidth), maxQueueWidth)
    }
}
