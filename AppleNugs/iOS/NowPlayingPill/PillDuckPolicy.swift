import Foundation

/// Scroll-direction policy for the now-playing pill's duck on iPhone Duo.
///
/// Where the tab bar is laid out vertically, the system's
/// `.tabBarMinimizeBehavior(.onScrollDown)` never gets the pill out of the
/// content's way, so the shell mounts the pill itself, on its own shelf, and
/// tucks it into the shelf (which folds shut) while the user scrolls down. This
/// decides WHEN, from successive scroll samples, and which samples to believe
/// (`Gate`); the view layer decides how it looks, and owns the idle timer that
/// brings the pill back once scrolling stops.
///
/// The shelf makes the policy part of a feedback loop: folding it grows every
/// scroll view's visible area, which shrinks the scrollable range — at the
/// bottom of a page that alone looks like a scroll up, and opening it again
/// looks like a scroll down. Three rules break the loop: deltas are measured
/// inside the range both samples share, so a range change is never travel;
/// content that can't scroll holds the pill where it is; and `Gate` drops
/// every sample that isn't the user's finger or fling, and every sample while
/// the shelf is still moving.
///
/// Deliberately SwiftUI-free so it compiles straight into the host-free
/// `AppleNugsTests` bundle (same arrangement as `PillLayout`).
enum PillDuckPolicy {

    enum Visibility: Equatable {
        case shown
        case ducked
    }

    /// One scroll position, normalized so `offset == 0` is the true top of the
    /// content (insets already accounted for) and `maxOffset` is the furthest
    /// the content can scroll. `maxOffset <= 0` means the content fits and
    /// does not scroll at all.
    struct Sample: Equatable {
        var offset: CGFloat
        var maxOffset: CGFloat

        /// A constant every scroll view reports while the duck is inactive, so
        /// `onScrollGeometryChange`'s action fires at most once.
        static let inactive = Sample(offset: 0, maxOffset: 0)

        init(offset: CGFloat, maxOffset: CGFloat) {
            self.offset = offset
            self.maxOffset = maxOffset
        }

        /// Builds a sample from raw `ScrollGeometry`. `contentOffset` starts
        /// NEGATIVE under a navigation bar (it is measured from the content's
        /// origin, which sits below the top inset), so the top inset is added
        /// back to put the resting position at 0.
        ///
        /// `frameHeight` must be `visibleRect.height` — the scroll view's full
        /// frame — NOT `containerSize.height`: measured on iPhone Duo's outer
        /// display, a ScrollView reports its container with the insets already
        /// taken out (visible 678, container 524 = 678 − 82 − 72) while a List
        /// reports them included (visible = container = 542, bottom inset 34).
        /// Against the frame, UIKit's own arithmetic holds for both.
        init(contentOffsetY: CGFloat, insetTop: CGFloat, insetBottom: CGFloat,
             contentHeight: CGFloat, frameHeight: CGFloat) {
            offset = contentOffsetY + insetTop
            maxOffset = contentHeight + insetTop + insetBottom - frameHeight
        }
    }

    /// `travel` is progress toward flipping, always >= 0: downward points
    /// accumulated while shown, upward points accumulated while ducked.
    struct State: Equatable {
        var visibility: Visibility = .shown
        var travel: CGFloat = 0

        static let shown = State()
    }

    /// Downward travel, uninterrupted by any upward movement, before the pill
    /// ducks. Big enough that a finger settling on the glass doesn't flap it.
    static let duckTravel: CGFloat = 24

    /// Upward travel, uninterrupted by any downward movement, before a ducked
    /// pill comes back. Smaller than `duckTravel` on purpose: getting playback
    /// back should be easier than sending it away.
    static let showTravel: CGFloat = 12

    /// Within this distance of the top the pill is always shown.
    static let topZone: CGFloat = 8

    static func step(_ state: State, from old: Sample, to new: Sample) -> State {
        // Content that can't scroll — now, or a frame ago — carries no motion,
        // and the pill stays where it is. A non-scrolling `old` is either
        // `Sample.inactive` (the gate just switched on — playback started, or
        // the Duo folded — over a list already scrolled 500pt down, which must
        // not read as 500pt of travel) or content that has only now grown tall
        // enough to scroll. A non-scrolling `new` can be the shelf's own doing:
        // folding it takes the whole range away from a barely-scrollable page,
        // and popping the pill back for that would open the shelf and give the
        // range back, under the same finger. The idle return brings it home.
        guard new.maxOffset > 0, old.maxOffset > 0 else {
            return State(visibility: state.visibility, travel: 0)
        }

        // Measure both samples inside the range they share, so the rubber band
        // past the bottom — and its spring back — is not mistaken for travel,
        // and neither is the range changing under a resting offset: a page of
        // results arriving at the bottom, or the shelf folding or opening
        // (which moves the range, and may make the system pull the offset in
        // after it).
        let range = min(old.maxOffset, new.maxOffset)
        let from = clamp(old.offset, range)
        let to = clamp(new.offset, range)

        // The top always shows: the rubber band above it, a shown pill (the
        // zone resets its travel, so only motion past the zone counts), or a
        // ducked one the user has brought up into it.
        if new.offset <= topZone,
           new.offset <= 0 || state.visibility == .shown || to < from {
            return .shown
        }

        let delta = to - from
        guard delta != 0 else { return state }

        switch state.visibility {
        case .shown:
            let travel = delta > 0 ? state.travel + delta : 0
            return travel >= duckTravel
                ? State(visibility: .ducked, travel: 0)
                : State(visibility: .shown, travel: travel)
        case .ducked:
            let travel = delta < 0 ? state.travel - delta : 0
            return travel >= showTravel
                ? .shown
                : State(visibility: .ducked, travel: travel)
        }
    }

    private static func clamp(_ offset: CGFloat, _ maxOffset: CGFloat) -> CGFloat {
        min(max(offset, 0), max(maxOffset, 0))
    }

    // --- which samples to believe -------------------------------------------

    /// What is moving the content, from the scroll view's phase.
    enum Drive: Equatable {
        /// Nothing: the idle return may run.
        case idle
        /// A finger on the glass, or the fling it left behind.
        case user
        /// A programmatic or system scroll (`scrollTo`, a tap on the status
        /// bar). Not a gesture, so not a reason to move the pill.
        case system
    }

    /// How long after the pill ducks or returns its samples are dropped: the
    /// shelf folds 70ms + 300ms after a duck and opens in 260ms, and every
    /// scroll view's bottom margin moves with it. Covers both, with room for
    /// the system to pull an out-of-range offset back in behind them.
    static let settleWindow: TimeInterval = 0.5

    /// The feedback guard. `PillDuck` keeps one, tells it the latest scroll
    /// phase and every transition, and asks it before stepping the policy.
    /// Times are any monotonic clock in seconds.
    struct Gate: Equatable {
        var drive: Drive = .idle
        /// Samples before this instant belong to the shelf, not the user.
        var settlesAt: TimeInterval = -.infinity

        /// Whether a scroll sample taken at `now` may move the pill.
        func admits(at now: TimeInterval) -> Bool {
            drive == .user && now >= settlesAt
        }

        /// The pill just ducked or came back: the shelf starts moving.
        mutating func transitioned(at now: TimeInterval) {
            settlesAt = now + PillDuckPolicy.settleWindow
        }
    }
}

/// The shelf the pill sits on where it is mounted by hand (iPhone Duo's
/// vertical tab bar): an opaque band across the bottom of the tab content that
/// the content stops at. Heights are from the screen's PHYSICAL bottom edge —
/// the band runs down through the home-indicator area — per
/// `docs/design/yeti-theme/yeti-pill-shelf.html`.
enum PillShelfGeometry {
    /// Open: the 48pt pill, 14pt under it, 14pt over it to the lip.
    static let openHeight: CGFloat = 76
    /// Closed: a 16pt lip holding the hang slot, sitting ABOVE the
    /// home-indicator band. (The mockup drew it 16pt from the physical edge,
    /// but on the device the home indicator then lands on the slot, hiding it
    /// and putting its tap target in the system's edge-gesture zone.)
    static let closedLip: CGFloat = 16
    /// The band never counts for more than this, so a keyboard (or any tall
    /// bottom inset) can't push the closed lip up past the open shelf.
    static let maxIndicatorBand: CGFloat = 40

    static func height(ducked: Bool, bottomSafeArea: CGFloat) -> CGFloat {
        guard ducked else { return openHeight }
        let band = min(max(0, bottomSafeArea), maxIndicatorBand)
        return min(openHeight, band + closedLip)
    }

    /// The bottom margin content needs ON TOP of its own bottom safe area to
    /// come to rest at the shelf's lip. Never negative: a bottom inset taller
    /// than the shelf (a keyboard) already clears it.
    static func contentClearance(ducked: Bool, bottomSafeArea: CGFloat) -> CGFloat {
        max(0, height(ducked: ducked, bottomSafeArea: bottomSafeArea) - max(0, bottomSafeArea))
    }
}
