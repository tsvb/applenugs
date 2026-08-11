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

    /// The progress ring's stroke, and the breathing room between it and the
    /// cover it encircles. The ring is drawn INSIDE `leadingSlotSize` — the
    /// slot's footprint is load-bearing for `textBudget`, so the art shrinks
    /// to make room rather than the slot growing.
    static let ringLineWidth: CGFloat = 2
    static let ringGap: CGFloat = 1

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

    /// Side of the `ArtChip` that sits inside the progress ring: the slot
    /// less the ring's band on both sides. Clamped so a pathologically small
    /// slot yields zero rather than a negative frame.
    static func artChipSize(slot: CGFloat) -> CGFloat {
        max(slot - 2 * (ringLineWidth + ringGap), 0)
    }

    /// How much of the ring is filled, in 0...1.
    ///
    /// **Empty when the duration is unknown.** A full ring on a stream that
    /// reports no duration would read as "finished" — the same defect
    /// `11dae49` fixed on the four iOS scrub sliders.
    static func progressFraction(currentTime: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
}
