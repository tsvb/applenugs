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
        // The ring is drawn inside the 32pt footprint and the art shrinks to
        // make room, so the slot's width — which `PillLayout.textBudget`
        // subtracts — is unchanged.
        ArtChip(image: app.player.nowPlayingImage,
                fallbackText: app.player.current?.artist
                    ?? app.player.current?.title ?? "?",
                size: PillLayout.artChipSize(slot: size))
            .frame(width: size, height: size)
            .overlay { PillProgressRing() }
            .accessibilityHidden(true)   // the pill's label already says what's playing
    }
}
