import SwiftUI

/// Yeti's lossless badge: "Lossless" over "24/96" in night ink on a disc of
/// sticker stock, tilted like a price sticker slapped on the box. Replaces the
/// format badge under `.stickers`. Translated from the design sheet's
/// `.sticker` (62pt, −11°) and `.sticker.tiny` (smaller, −9°).
///
/// What it says comes from the pure `PriceStickerLabel`; a `nil` label means
/// hidden. **Hidden or shown, it holds one fixed frame per size**, so a row it
/// sits in never reflows when a known lossy pick hides it, or when the spec line
/// appears. Its presence belongs to the host, gated on `player.current` — never
/// on `nowPick`/`specs` (see `PriceStickerLabel`); `init(player:size:)` does it
/// right.
struct PriceSticker: View {
    /// The design's five diameters.
    enum Size: CGFloat, CaseIterable, Sendable {
        case s62 = 62, s44 = 44, s40 = 40, s36 = 36, s32 = 32

        var diameter: CGFloat { rawValue }

        /// (title, spec) point sizes and the gap between them, from the sheet:
        /// 62 → 10/15 (gap 2); the tiny stickers 7.5/11 (gap 1), shrunk where
        /// "Lossless" would otherwise crowd the disc's edge.
        fileprivate var type: (title: CGFloat, spec: CGFloat, gap: CGFloat) {
            switch self {
            case .s62: return (10, 15, 2)
            case .s44, .s40: return (7.5, 11, 1)
            case .s36: return (6.5, 10, 1)
            case .s32: return (6, 9, 0.5)
            }
        }

        fileprivate var tilt: Angle { self == .s62 ? .degrees(-11) : .degrees(-9) }
    }

    @Environment(\.theme) private var theme

    let label: PriceStickerLabel?
    var size: Size = .s62

    var body: some View {
        ZStack {
            if let label {
                sticker(label)
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
        .frame(width: size.diameter, height: size.diameter)
    }

    private func sticker(_ label: PriceStickerLabel) -> some View {
        let ink = theme.stickerInk
        let type = size.type
        return ZStack {
            StickerStock(shape: Circle(), lift: .price)
            // `inset 0 0 0 2px rgba(15,20,36,.07)`: the faint printed rim.
            Circle().strokeBorder(ink.opacity(0.07), lineWidth: 2)
            VStack(spacing: type.gap) {
                Text(label.title)
                    .font(.system(size: type.title, weight: .heavy, design: .rounded))
                if let spec = label.spec {
                    // The sizes are set for five characters ("24/96"); a longer
                    // line ("24/192") shrinks in proportion so it stays on the
                    // disc. The disc never grows and the text never truncates.
                    Text(spec)
                        .font(.system(size: type.spec * min(1, 5 / CGFloat(max(spec.count, 1))),
                                      weight: .black, design: .rounded))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
        }
        .rotationEffect(size.tilt)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.accessibilityLabel)
    }
}

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
