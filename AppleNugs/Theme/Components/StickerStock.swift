import SwiftUI

// Yeti's sticker stock: the sale-yellow paper every sticker is printed on
// (price, play, row, label), with night ink (`palette.stickerInk`) on top. Pink
// is never printed on it. Translated from the design sheet's `.stock` rule:
//
//     radial-gradient(circle at 34% 30%, #FBF1A6, #F2E27A 55%, #E3D267)
//
// The three stops are `Palette`'s `stickerHighlight` / `stickerSale` /
// `stickerEdge`; the gradient is built statically (no environment), so it
// reads them from `Theme.yeti`.

/// The sale-yellow radial fill in `shape`, under an optional drop-shadow lift.
/// The gradient is laid out from the view's own size, so one stock serves a
/// 16pt row disc and a 19pt-tall label tag alike.
struct StickerStock<S: InsettableShape>: View {
    let shape: S
    var lift: StickerLift = .none

    static var highlight: Color { Theme.yeti.palette.stickerHighlight }
    static var sale: Color { Theme.yeti.palette.stickerSale }
    static var edge: Color { Theme.yeti.palette.stickerEdge }

    var body: some View {
        GeometryReader { geo in
            shape.fill(Self.gradient(in: geo.size))
        }
        .stickerLift(lift, in: shape)
    }

    /// CSS `circle at 34% 30%` with no size keyword is `farthest-corner`: the
    /// gradient reaches 100% at the bounding box's farthest corner, which from
    /// (34%, 30%) is the bottom-trailing one.
    static func gradient(in size: CGSize) -> RadialGradient {
        let dx = size.width * 0.66, dy = size.height * 0.70
        return RadialGradient(
            stops: [.init(color: highlight, location: 0),
                    .init(color: sale, location: 0.55),
                    .init(color: edge, location: 1)],
            center: UnitPoint(x: 0.34, y: 0.30),
            startRadius: 0,
            endRadius: (dx * dx + dy * dy).squareRoot())
    }
}

/// A sticker's drop shadow: the design's two `box-shadow` layers, a hard 0-blur
/// lip plus a soft fall-off. Drawn as separate blurred fills of the sticker's
/// shape BEHIND it — stacking two `.shadow` modifiers would shadow the first
/// shadow's silhouette as well, and `.shadow` has no spread.
struct StickerLift: Sendable, Equatable {
    struct Layer: Sendable, Equatable {
        /// Black at this opacity.
        let opacity: Double
        /// CSS y offset.
        let y: CGFloat
        /// CSS blur length; a Gaussian of sigma `blur / 2`.
        let blur: CGFloat
        /// CSS spread: negative insets the shape before blurring.
        let spread: CGFloat
    }

    let layers: [Layer]

    static let none = StickerLift(layers: [])
    /// `.sticker`: 0 2px 0 rgba(0,0,0,.28), 0 6px 10px -4px rgba(0,0,0,.5)
    static let price = StickerLift(layers: [
        Layer(opacity: 0.28, y: 2, blur: 0, spread: 0),
        Layer(opacity: 0.5, y: 6, blur: 10, spread: -4),
    ])
    /// `.play-sticker`: 0 2px 0 rgba(0,0,0,.28), 0 8px 14px -6px rgba(0,0,0,.6)
    static let play = StickerLift(layers: [
        Layer(opacity: 0.28, y: 2, blur: 0, spread: 0),
        Layer(opacity: 0.6, y: 8, blur: 14, spread: -6),
    ])
    /// `.tag`: 0 1px 0 rgba(0,0,0,.3), 0 3px 6px -3px rgba(0,0,0,.5)
    static let tag = StickerLift(layers: [
        Layer(opacity: 0.3, y: 1, blur: 0, spread: 0),
        Layer(opacity: 0.5, y: 3, blur: 6, spread: -3),
    ])
}

extension View {
    /// Draws `lift`'s shadow layers as `shape` fills behind this view. Paints
    /// outside the frame only; the layout footprint is unchanged.
    func stickerLift<S: InsettableShape>(_ lift: StickerLift, in shape: S) -> some View {
        background {
            ZStack {
                ForEach(Array(lift.layers.enumerated()), id: \.offset) { _, layer in
                    shape
                        .inset(by: -layer.spread)
                        .fill(Color.black.opacity(layer.opacity))
                        .blur(radius: layer.blur / 2)
                        .offset(y: layer.y)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
