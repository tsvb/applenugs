import Foundation

/// Scroll-direction policy for the now-playing pill's duck on iPhone Duo.
///
/// Where the tab bar is laid out vertically, the system's
/// `.tabBarMinimizeBehavior(.onScrollDown)` never gets the pill out of the
/// content's way, so the shell mounts the pill itself and ducks it below the
/// bottom edge while the user scrolls down. This decides WHEN, from successive
/// scroll samples; the view layer decides how it looks, and owns the idle timer
/// that brings the pill back once scrolling stops.
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
        // Content that doesn't scroll never ducks, and the top always shows
        // (including the rubber-band overscroll above it). A non-scrolling
        // `old` carries no motion either: it is either `Sample.inactive` (the
        // gate just switched on — playback started, or the Duo folded — over
        // a list already scrolled 500pt down, which must not read as 500pt of
        // travel) or content that has only now grown tall enough to scroll.
        guard new.maxOffset > 0, new.offset > topZone, old.maxOffset > 0 else {
            return .shown
        }

        // Clamp each sample to its own scrollable range, so the rubber band
        // past the bottom — and its spring back — is not mistaken for travel,
        // and neither is the content growing under a resting offset (a page
        // of results arriving at the bottom).
        let delta = clamp(new.offset, new.maxOffset) - clamp(old.offset, old.maxOffset)
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
}
