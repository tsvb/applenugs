import Foundation

/// Layout policy for the iOS now-playing pill.
///
/// Deliberately SwiftUI-free so it compiles straight into the host-free
/// `AppleNugsTests` bundle (the same trick `TapeGeometry` uses). Every number
/// here comes from a real measurement of `tabViewBottomAccessory` on iOS 27,
/// iPhone 17 Pro: 360x48pt expanded, 284x48pt inline. The system owns that
/// height — there is no modifier to change it — so the pill has exactly one
/// row to work with and the whole fight is horizontal.
enum PillLayout {

    /// Which slot the pill is occupying. Mirrors SwiftUI's
    /// `TabViewBottomAccessoryPlacement` without importing SwiftUI.
    enum Slot: Equatable {
        case expanded
        case inline
    }

    /// One transport affordance in the pill's trailing cluster.
    /// `Hashable` because `PillTransportControls` drives a `ForEach` off it.
    enum Control: Equatable, Hashable {
        case previous
        case back15
        case playPause
        case forward30
        case next
    }

    // --- metrics ------------------------------------------------------------

    static let leadingSlotSize: CGFloat = 32
    static let controlWidth: CGFloat = 28
    static let controlSpacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 10
    static let slotTextGap: CGFloat = 8

    /// The visible seek track, and the invisible strip that actually catches
    /// the drag. 2.5pt is untappable; 20pt is comfortable without swallowing
    /// the container tap (which is gated behind a drag minimumDistance).
    static let seekEdgeHeight: CGFloat = 2.5
    static let seekHitHeight: CGFloat = 20

    // --- policy -------------------------------------------------------------

    /// `tabViewBottomAccessoryPlacement` is optional: it is nil wherever the
    /// pill renders outside a tab accessory. Treat that as the roomy case.
    static func slot(isInline: Bool?) -> Slot {
        isInline == true ? .inline : .expanded
    }

    static func controls(for slot: Slot) -> [Control] {
        switch slot {
        case .expanded: return [.previous, .back15, .playPause, .forward30, .next]
        case .inline:   return [.playPause, .next]
        }
    }

    static func showsArtistLine(for slot: Slot) -> Bool {
        slot == .expanded
    }

    /// Points left for the title/artist column after padding, the control
    /// cluster, and the optional leading slot have taken their share.
    static func textBudget(width: CGFloat, slot: Slot, hasLeadingSlot: Bool) -> CGFloat {
        let set = controls(for: slot)
        let controlsWidth = CGFloat(set.count) * controlWidth
            + CGFloat(max(set.count - 1, 0)) * controlSpacing
        let leading = hasLeadingSlot ? leadingSlotSize + slotTextGap : 0
        return max(width - horizontalPadding * 2 - controlsWidth - leading - slotTextGap, 0)
    }

    /// Width, measured from the pill's trailing edge, occupied by the
    /// transport-control cluster plus (when it renders) the chevron's lane.
    /// `PillSeekEdge` subtracts this from its trailing side so its invisible
    /// hit strip stops before the buttons instead of riding above them —
    /// mirrors the same arithmetic `NowPlayingPill.trailingPadding` uses for
    /// the chevron lane, plus the control cluster's own width.
    static func controlsTrailingInset(for slot: Slot, includesChevron: Bool) -> CGFloat {
        let set = controls(for: slot)
        let controlsWidth = CGFloat(set.count) * controlWidth
            + CGFloat(max(set.count - 1, 0)) * controlSpacing
        let chevronLane = includesChevron ? controlWidth + controlSpacing : 0
        return horizontalPadding + chevronLane + controlsWidth
    }
}
