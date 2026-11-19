import SwiftUI

// The player-reading half of the price sticker, kept apart from the view so an
// offscreen render can compile `PriceSticker` without `PlayerService`.

extension PriceSticker {
    /// The sticker for whatever `player` has loaded, with the presence rule
    /// applied (hidden only when nothing is current, or the pick is known lossy).
    @MainActor
    init(player: PlayerService, size: Size = .s62) {
        self.init(label: PriceStickerLabel(player: player), size: size)
    }
}

extension PriceStickerLabel {
    /// Reads the player the one correct way. `nil` (hidden) when nothing is
    /// current. A current track with no pick yet — `startCurrent()` nils
    /// `nowPick` and `specs` on every track change — reads "Lossless" rather
    /// than blinking off. Depth falls back to the format's implied depth until
    /// the decoder reports one; the rate has no such fallback, so the spec line
    /// waits for `specs`.
    @MainActor
    init?(player: PlayerService) {
        guard player.current != nil else { return nil }
        let pick = player.nowPick
        // A decoder reports 0 bits for some streams; treat it like nil here.
        let reportedDepth = player.specs?.bitDepth.flatMap { $0 > 0 ? $0 : nil }
        self.init(pickKnown: pick != nil,
                  isLossless: pick?.format.isLossless ?? false,
                  bitDepth: reportedDepth ?? pick?.format.impliedBitDepth,
                  sampleRate: player.specs?.sampleRate)
    }
}
