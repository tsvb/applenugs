import Foundation

/// Swipe-down-to-close policy for the iOS full-screen player
/// (`NowPlayingArrangement`): the player follows the finger down and closes
/// past a threshold, otherwise springs back. Pure Foundation so the host-free
/// tests can cover it.
///
/// A drag is judged ONCE, on its first sample (which arrives after the
/// gesture's minimum distance): downward and vertical-dominant → `.tracking`
/// for the rest of that drag, anything else → `.ignored` for the rest of it.
/// Latching keeps a horizontal scrub that later curls downward from yanking
/// the player, and keeps a tracked drag that drifts sideways from snapping
/// back mid-gesture.
///
/// The stateless `tracks` / `offset(for:)` / `shouldDismiss(translation:predictedEnd:)`
/// are the same rules applied to a single sample (as if it were the first).
enum NowPlayingDismissDrag {

    enum Phase: Equatable, Sendable {
        case undecided
        case tracking
        case ignored
    }

    /// How much the vertical component must exceed the horizontal one.
    static let verticalDominance: CGFloat = 1.5
    /// A release this far down closes the player.
    static let dismissDistance: CGFloat = 120
    /// A flick whose predicted end lands this far down closes it from a short drag.
    static let flickDistance: CGFloat = 300

    /// Downward and vertical-dominant. Zero, upward, horizontal, and any
    /// non-finite translation never track.
    static func tracks(translation: CGSize) -> Bool {
        let dx = translation.width, dy = translation.height
        guard dx.isFinite, dy.isFinite else { return false }
        return dy > 0 && dy > abs(dx) * verticalDominance
    }

    /// The latch: an undecided drag is decided by this sample; a decided one
    /// stays decided. A zero or non-finite sample leaves it undecided.
    static func phase(after current: Phase, translation: CGSize) -> Phase {
        guard current == .undecided else { return current }
        let dx = translation.width, dy = translation.height
        guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { return .undecided }
        return tracks(translation: translation) ? .tracking : .ignored
    }

    /// The player's vertical offset: 1:1 with the finger downward while
    /// tracking, never above its resting place, 0 otherwise.
    static func offset(for translation: CGSize, phase: Phase) -> CGFloat {
        guard phase == .tracking else { return 0 }
        let dy = translation.height
        return dy.isFinite ? max(0, dy) : 0
    }

    /// Single-sample form of `offset(for:phase:)`.
    static func offset(for translation: CGSize) -> CGFloat {
        offset(for: translation, phase: phase(after: .undecided, translation: translation))
    }

    /// Close on release when tracking AND either the drag went past
    /// `dismissDistance` (and isn't being flung back up) or the flick's
    /// predicted end lands past `flickDistance`.
    static func shouldDismiss(translation: CGSize, predictedEnd: CGSize, phase: Phase) -> Bool {
        guard phase == .tracking else { return false }
        let dy = translation.height, predicted = predictedEnd.height
        guard dy.isFinite, predicted.isFinite else { return false }
        if predicted >= flickDistance { return true }
        return dy >= dismissDistance && predicted >= dismissDistance
    }

    /// Single-sample form of `shouldDismiss(translation:predictedEnd:phase:)`.
    static func shouldDismiss(translation: CGSize, predictedEnd: CGSize) -> Bool {
        shouldDismiss(translation: translation, predictedEnd: predictedEnd,
                      phase: phase(after: .undecided, translation: translation))
    }
}
