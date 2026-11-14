import Foundation

/// Layout policy for the iOS now-playing pill.
///
/// Deliberately SwiftUI-free so it compiles straight into the host-free
/// `AppleNugsTests` bundle (the same trick `NowPlayingFit` uses). Every number
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

    /// The narrowest title/artist column the pill will accept before it starts
    /// shedding transport controls. Below this the title reads "Aw…".
    static let minTextWidth: CGFloat = 90

    /// The control set for a slot at a measured width.
    ///
    /// `controls(for:)` alone is not enough: on iPhone Duo's outer display the
    /// tab bar is laid out vertically, so the accessory is ~290pt wide while
    /// its placement still reads `.expanded`, and five controls would leave
    /// the text 34pt. This sheds controls until the text column reaches
    /// `minTextWidth` — the skip intervals first (together, so the cluster
    /// stays symmetric), then previous. Play/pause and next are the floor and
    /// are never shed.
    ///
    /// `trailingReserve` is any extra trailing lane the caller keeps clear
    /// (the chevron's 32pt), on top of the padding `textBudget` already counts.
    ///
    /// A width that is zero, negative or non-finite means the pill has not
    /// been measured yet; that returns the slot's full set rather than
    /// mistaking "unmeasured" for "no room".
    static func controls(slot: Slot, width: CGFloat, hasLeadingSlot: Bool,
                         trailingReserve: CGFloat) -> [Control] {
        let full = controls(for: slot)
        guard width.isFinite, width > 0 else { return full }

        let withoutSkips = full.filter { $0 != .back15 && $0 != .forward30 }
        let floor = withoutSkips.filter { $0 != .previous }

        for candidate in [full, withoutSkips] {
            let budget = textBudget(width: width, controls: candidate,
                                    hasLeadingSlot: hasLeadingSlot) - trailingReserve
            if budget >= minTextWidth { return candidate }
        }
        return floor
    }

    /// Points left for the title/artist column after padding, the control
    /// cluster, and the optional leading slot have taken their share.
    static func textBudget(width: CGFloat, slot: Slot, hasLeadingSlot: Bool) -> CGFloat {
        textBudget(width: width, controls: controls(for: slot), hasLeadingSlot: hasLeadingSlot)
    }

    /// Same arithmetic as above, for an explicit control set.
    static func textBudget(width: CGFloat, controls set: [Control], hasLeadingSlot: Bool) -> CGFloat {
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
