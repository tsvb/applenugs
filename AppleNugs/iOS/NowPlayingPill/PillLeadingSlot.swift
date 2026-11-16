import SwiftUI

/// The pill's 32pt leading slot: the cover, wrapped in the progress ring.
///
/// One uniform `ArtChip`, clipped to a circle: a ring wants one consistent
/// shape to encircle, and the circle keeps the ring's 1pt gap at every angle
/// (a rounded square's corners would put the arc on the cover).
///
/// Nothing in THIS view observes `player.currentTime`; the ring is a separate
/// leaf so the 4Hz playback tick stops there. See `PillProgressRing`.
struct PillLeadingSlot: View {
    @Environment(AppModel.self) private var app

    private var size: CGFloat { PillLayout.leadingSlotSize }

    var body: some View {
        // `artChipSize` is the diameter of the inscribed circle that fits
        // inside the ring's inner edge — correct by construction only
        // because the chip below is clipped to a circle. A rounded-square
        // chip at that same size would still reach past the ring at its
        // corners; the circular clip is what holds the 1pt `ringGap` at
        // every angle, not just on the 12/3/6/9 o'clock axes. The slot's
        // outer footprint — what `PillLayout.textBudget` subtracts — stays
        // 32pt regardless.
        ArtChip(image: app.player.nowPlayingImage,
                fallbackText: app.player.current?.artist
                    ?? app.player.current?.title ?? "?",
                size: PillLayout.artChipSize(slot: size))
            .clipShape(Circle())
            .frame(width: size, height: size)
            .overlay { PillProgressRing() }
            .accessibilityHidden(true)   // the pill's label already says what's playing
    }
}
