import Foundation

/// Column policy for iPhone Home.
///
/// Deliberately SwiftUI-free so it compiles straight into the host-free
/// `AppleNugsTests` bundle (the `PillLayout` trick).
///
/// Home is one column on a phone. On a wide canvas — the iPhone Duo's inner
/// display (~870pt of Home content flat, ~629pt upright; regular iPhones are
/// portrait-locked by `OrientationGate`, so they never get here) — one column
/// stretches the hero into a long strip of bare card stock and leaves little
/// else above the fold. There, Home splits instead:
/// the hero keeps its designed upright blister pack in a leading column, and
/// favorites, the nice list and the crate stack beside it.
///
/// Switched on MEASURED width, never size class — the project's Duo rule (the
/// pill sheds controls by measured width for the same reason). iOS only: the
/// Mac has its own flat resume card (Tim's ruling 4) and stays one column.
enum HomeColumns: Equatable {
    /// Today's Home: everything in one column.
    case single
    /// The hero in a leading column of `leading` points; everything else in
    /// the trailing column, `gutter` points away.
    case split(leading: CGFloat)

    /// The narrowest Home that splits. Portrait iPhones (≈ 335–400pt) and the
    /// Duo's folded outer display stay one column.
    static let minSplitWidth: CGFloat = 560

    /// Between the two columns.
    static let gutter: CGFloat = 24

    /// The leading column: about a third of the width, held between the
    /// width where the hero's 186pt bubble still sits in bare card stock
    /// (280) and the width past which the pack would start to read as a
    /// stretched card again (320). Upright Duo → 280 + 325; flat → 313 + 533.
    static let leadingFraction: CGFloat = 0.36
    static let leadingRange: ClosedRange<CGFloat> = 280...320

    /// The columns for Home at a measured content `width`.
    ///
    /// Only splits when there is a hero to put in the leading column; with
    /// nothing loaded there is nothing to pin beside the rest, so Home stays
    /// one column. A width that is zero, negative or non-finite means Home has
    /// not been measured yet; that answers `.single` — today's Home — rather
    /// than guessing.
    static func columns(width: CGFloat, hasHero: Bool) -> HomeColumns {
        guard hasHero, width.isFinite, width >= minSplitWidth else { return .single }
        let leading = min(max(width * leadingFraction, leadingRange.lowerBound),
                          leadingRange.upperBound)
        return .split(leading: leading)
    }
}
