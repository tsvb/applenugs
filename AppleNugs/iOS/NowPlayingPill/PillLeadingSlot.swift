import SwiftUI

/// The pill's 32pt leading slot: the cover, wrapped in the progress ring.
///
/// This was five themed faces (Tape Room's reel, the Receiver's VU, Click
/// Wheel's disc, Shoebox's J-card spine, and a plain chip for Soundboard).
/// The ring changed that calculus — a ring wants one consistent shape to
/// encircle, and three of those faces are themselves circles, so the slot
/// would have carried two concentric rings. Theme identity lives on in the
/// full-screen player, the palette, the typography, the copy, and the macOS
/// miniplayer.
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
