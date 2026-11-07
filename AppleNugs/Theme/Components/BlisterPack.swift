import SwiftUI

// Yeti's one material: the cover sealed in a clear plastic bubble on a
// backing card, hung on a peg like a vintage action figure. Translated from
// the design sheets' `.card`, `.card::before` (the hang slot), `.bubble` (+
// `::before` specular arc, `::after` glare streaks, `.art` glaze),
// `.bubble.sm`, `.bubble.empty .hollow` and `.card.pack`.
//
// **Art must yield height** (CLAUDE.md, iPhone Duo layout rules): the bubble
// is square and takes what the proposal leaves after the content printed
// below it, so on a short canvas (the Duo's flat inner display, a 300pt
// upright column) the bubble shrinks first and the nameplate keeps its lines.
// It is never a rigid tile.
//
// The glass colors are palette-adjacent constants (Yeti-only, spec "Tokens");
// the card stock, keyline and the night showing through the hang slot come
// from the theme.

// MARK: - Pack

/// A backing card (card stock + punched hang slot) holding a `BlisterBubble`,
/// with optional content printed on the card below the bubble (the
/// now-playing nameplate and meta, the sign-in "Yeti"), and an optional
/// `PriceSticker` slapped on the bubble's corner.
///
/// Sizing: the card takes the proposed WIDTH. The bubble is square and gets
/// what the proposed HEIGHT leaves after `below` has its natural height
/// (`below` carries a raised layout priority), capped at `maxBubbleSide` if
/// given; a bubble narrower than the card sits centered. With no height
/// proposed (a scroll view) the bubble is as wide as the card's inner width.
///
///     BlisterPack(price: PriceStickerLabel(player: player)) {
///         PackArt(image: player.nowPlayingImage, monogram: track.artist ?? "?")
///     } below: {
///         Text(track.title).foilSweep(identity: track.trackId, isPlaying: player.isPlaying)
///     }
///
///     BlisterPack(emptyStyle: .small)   // connection failed, empty states
struct BlisterPack<Art: View, Below: View>: View {
    typealias Style = BlisterPackStyle

    private let style: Style
    private let price: PriceStickerLabel?
    private let priceSize: PriceSticker.Size?
    private let maxBubbleSide: CGFloat?
    private let belowAlignment: HorizontalAlignment
    private let art: Art?
    private let below: Below

    /// A pack holding `art` (use `PackArt` for cover-or-monogram).
    /// - `price`: the corner sticker's label; `nil` draws no sticker. Pass
    ///   `PriceStickerLabel(player:)` — it applies the presence rule.
    /// - `priceSize`: forces a sticker size; `nil` picks one from the bubble's
    ///   current side (62pt on a full-size bubble, smaller as it yields).
    /// - `maxBubbleSide`: caps the bubble (e.g. the old 280pt art cap).
    init(style: Style = .regular,
         price: PriceStickerLabel? = nil,
         priceSize: PriceSticker.Size? = nil,
         maxBubbleSide: CGFloat? = nil,
         belowAlignment: HorizontalAlignment = .leading,
         @ViewBuilder art: () -> Art,
         @ViewBuilder below: () -> Below) {
        self.style = style
        self.price = price
        self.priceSize = priceSize
        self.maxBubbleSide = maxBubbleSide
        self.belowAlignment = belowAlignment
        self.art = art()
        self.below = below()
    }

    var body: some View {
        let m = style.metrics
        VStack(alignment: belowAlignment, spacing: m.gap) {
            bubble
                // Only consulted when nothing is proposed (an unconstrained
                // ideal-size pass): the design's bubble size.
                .frame(idealWidth: m.idealBubble, idealHeight: m.idealBubble)
                .frame(maxWidth: maxBubbleSide, maxHeight: maxBubbleSide)
                // Keep the slot square. A max-only frame reports
                // max(child, proposal) up to its cap, so in a column narrower
                // than it is tall (the Duo's 300pt upright column) a capped
                // slot stood 320pt tall around a 208pt bubble, padding the
                // card with dead space. Fitting a square first proposes the
                // frame the bubble's own side.
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
            below
                .frame(maxWidth: .infinity,
                       alignment: Alignment(horizontal: belowAlignment, vertical: .center))
                // The bubble yields first: below is offered its natural
                // height before the bubble takes the rest.
                .layoutPriority(1)
        }
        .padding(m.cardPadding)
        .frame(maxWidth: .infinity)
        .background { BlisterCard() }
    }

    @ViewBuilder private var bubble: some View {
        let m = style.metrics
        Group {
            if let art {
                BlisterBubble(metrics: m.bubble) { art }
            } else {
                BlisterBubble<EmptyView>(emptyMetrics: m.bubble)
            }
        }
        .overlay {
            if let price {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    let size = priceSize ?? Self.autoPriceSize(bubbleSide: side)
                    let d = size.diameter
                    // From the sheet: a 62pt sticker centered 21pt in from the
                    // bubble's trailing edge and 33pt up from its bottom, so it
                    // rides over the edge onto the card. Scaled with the sticker.
                    PriceSticker(label: price, size: size)
                        .position(x: geo.size.width - d * (21.0 / 62.0),
                                  y: geo.size.height - d * (33.0 / 62.0))
                }
            }
        }
    }

    /// The corner sticker's size for a bubble of `side` points: the sheet's
    /// 62pt on a full bubble, stepping down as the bubble yields so the
    /// sticker never swamps the art.
    static func autoPriceSize(bubbleSide side: CGFloat) -> PriceSticker.Size {
        switch side {
        case 190...: return .s62
        case 140..<190: return .s44
        case 110..<140: return .s36
        default: return .s32
        }
    }
}

extension BlisterPack where Below == EmptyView {
    /// A pack with nothing printed below the bubble.
    init(style: Style = .regular,
         price: PriceStickerLabel? = nil,
         priceSize: PriceSticker.Size? = nil,
         maxBubbleSide: CGFloat? = nil,
         @ViewBuilder art: () -> Art) {
        self.init(style: style, price: price, priceSize: priceSize,
                  maxBubbleSide: maxBubbleSide, art: art, below: { EmptyView() })
    }
}

extension BlisterPack where Art == EmptyView {
    /// The EMPTY pack — the backing card whose bubble holds nothing yet — with
    /// content printed below (sign-in's "Yeti" nameplate). Never animated,
    /// never holds a glyph.
    init(emptyStyle style: Style = .regular,
         maxBubbleSide: CGFloat? = nil,
         belowAlignment: HorizontalAlignment = .leading,
         @ViewBuilder below: () -> Below) {
        self.style = style
        self.price = nil
        self.priceSize = nil
        self.maxBubbleSide = maxBubbleSide
        self.belowAlignment = belowAlignment
        self.art = nil
        self.below = below()
    }
}

extension BlisterPack where Art == EmptyView, Below == EmptyView {
    /// The EMPTY pack on its own (connection failed, empty states).
    init(emptyStyle style: Style = .regular, maxBubbleSide: CGFloat? = nil) {
        self.init(emptyStyle: style, maxBubbleSide: maxBubbleSide, below: { EmptyView() })
    }
}

/// The three pack sizes the sheets draw.
enum BlisterPackStyle: Sendable {
    /// The now-playing card: 34/26/20 card padding around a full bubble.
    case regular
    /// The iPhone Home hero (`.hero-card`): a full bubble on a tighter card,
    /// 32/18/16, with the name panel 16pt below.
    case hero
    /// `.card.pack.sm`: 30/16/16 padding around a `.bubble.sm`.
    case small

    struct Metrics {
        let bubble: BlisterBubbleMetrics
        let cardPadding: EdgeInsets
        /// Bubble to printed content (`.np .name { margin-top: 18px }`).
        let gap: CGFloat
        /// The bubble's side when nothing is proposed.
        let idealBubble: CGFloat
    }

    var metrics: Metrics {
        switch self {
        case .regular:
            // `.np .card { padding: 34px 26px 20px }` in a 350pt card.
            return Metrics(bubble: .regular,
                           cardPadding: EdgeInsets(top: 34, leading: 26, bottom: 20, trailing: 26),
                           gap: 18, idealBubble: 298)
        case .hero:
            // `.hero-card { padding: 32px 18px 16px }`, `.hero-card .bubble
            // { width: 186px }`, `.hero-card .name { margin-top: 16px }`.
            return Metrics(bubble: .regular,
                           cardPadding: EdgeInsets(top: 32, leading: 18, bottom: 16, trailing: 18),
                           gap: 16, idealBubble: 186)
        case .small:
            // `.card.pack.sm { width: 156px; padding: 30px 16px 16px }`.
            return Metrics(bubble: .small,
                           cardPadding: EdgeInsets(top: 30, leading: 16, bottom: 16, trailing: 16),
                           gap: 14, idealBubble: 124)
        }
    }
}

// MARK: - Card

/// The backing card: `labelPaper` stock, a 1pt frost keyline, a soft drop
/// shadow, and the punched hang slot at the top showing the night behind.
/// Fills the frame it is given.
struct BlisterCard: View {
    @Environment(\.theme) private var theme

    /// `.card { border-radius: 22px }`
    static let cornerRadius: CGFloat = 22
    /// `0 18px 30px -22px rgba(0,0,0,.8)`
    static let lift = StickerLift(layers: [
        .init(opacity: 0.8, y: 18, blur: 30, spread: -22),
    ])

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        shape
            .fill(theme.palette.labelPaper ?? theme.palette.raised)
            // `inset 0 0 0 1px var(--frost)`
            .overlay { shape.strokeBorder(theme.palette.hairline, lineWidth: 1) }
            .overlay(alignment: .top) {
                HangSlot().padding(.top, 13)
            }
            .stickerLift(Self.lift, in: shape)
            .accessibilityHidden(true)
    }
}

/// `.card::before`: a 46×12 capsule punched through the card, showing the
/// night (`palette.base`), with a dark inner lip at the top and a faint light
/// catch on the card just below it.
private struct HangSlot: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = Capsule()
        shape
            .fill(theme.palette.base)
            // `inset 0 2px 3px rgba(0,0,0,.6)`
            .overlay { InnerShadow(shape: shape, color: .black.opacity(0.6), x: 0, y: 2, blur: 3) }
            // `0 1px 0 rgba(233,238,247,.08)`: the card's edge catching light.
            .background {
                OuterShadow(shape: shape, color: BlisterGlass.snow.opacity(0.08), y: 1, blur: 0, spread: 0)
            }
            .frame(width: 46, height: 12)
    }
}

// MARK: - Bubble

/// One bubble's measurements: the sheet's `.bubble` and `.bubble.sm`.
struct BlisterBubbleMetrics: Sendable {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let artRadius: CGFloat
    /// `inset 0 0 0 Npx rgba(233,238,247,.34)`
    let rim: CGFloat
    /// `inset 0 Npx 0 rgba(255,255,255,a)`
    let topCatch: CGFloat
    let topCatchOpacity: Double
    /// `inset -x -y blur rgba(4,7,16,.5)`: the shade pooling bottom-trailing.
    let shade: (x: CGFloat, y: CGFloat, blur: CGFloat)
    /// `inset x y blur rgba(233,238,247,.10)`: the glow along the top-leading.
    let glow: (x: CGFloat, y: CGFloat, blur: CGFloat)
    /// `0 0 0 Npx` rings: the faint 0.035 halo and the 0.15 outer edge.
    let haloInner: CGFloat
    let haloOuter: CGFloat
    /// `0 y blur spread rgba(0,0,0,.75)`
    let drop: StickerLift.Layer

    static let regular = BlisterBubbleMetrics(
        cornerRadius: 30, padding: 14, artRadius: 18,
        rim: 1.5, topCatch: 2, topCatchOpacity: 0.32,
        shade: (-12, -16, 26), glow: (10, 12, 20),
        haloInner: 7, haloOuter: 8,
        drop: .init(opacity: 0.75, y: 22, blur: 28, spread: -16))

    static let small = BlisterBubbleMetrics(
        cornerRadius: 18, padding: 7, artRadius: 11,
        rim: 1, topCatch: 1.5, topCatchOpacity: 0.3,
        shade: (-6, -8, 14), glow: (5, 6, 10),
        haloInner: 4, haloOuter: 5,
        drop: .init(opacity: 0.75, y: 12, blur: 16, spread: -10))
}

/// The clear plastic bubble: layered glass gradient, inset rim, top catch
/// light, shade and glow, two outer halo rings and a drop shadow, with the
/// art (or the empty hollow) inside and the specular arc and glare streaks
/// over it. Always square; fills the largest square its proposal allows.
/// Usable without a card (the Mac miniplayer's small bubble).
struct BlisterBubble<Art: View>: View {
    private let metrics: BlisterBubbleMetrics
    private let art: Art?

    init(metrics: BlisterBubbleMetrics = .regular, @ViewBuilder art: () -> Art) {
        self.metrics = metrics
        self.art = art()
    }

    var body: some View {
        let m = metrics
        let shape = RoundedRectangle(cornerRadius: m.cornerRadius, style: .continuous)
        let artShape = RoundedRectangle(cornerRadius: m.artRadius, style: .continuous)

        Group {
            if let art {
                // `.bubble .art`: clipped, `saturate(.82) brightness(.94)`,
                // under a cool 160° glaze.
                Color.clear
                    .overlay { art }
                    .saturation(0.82)
                    .colorMultiply(Color(white: 0.94))
                    .overlay {
                        GeometryReader { geo in
                            let p = CSSGradient.points(degrees: 160, in: geo.size)
                            LinearGradient(colors: [BlisterGlass.glazeTop.opacity(0.10),
                                                    BlisterGlass.glazeBottom.opacity(0.18)],
                                           startPoint: p.start, endPoint: p.end)
                        }
                    }
                    .clipShape(artShape)
            } else {
                BlisterHollow(cornerRadius: m.artRadius)
            }
        }
        .padding(m.padding)
        .background { glass(shape) }
        .overlay { sheen(shape) }
        .background { outside(shape) }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Under the art: the glass fill and its inset shadows.
    private func glass(_ shape: RoundedRectangle) -> some View {
        let m = metrics
        return ZStack {
            GeometryReader { geo in
                let p = CSSGradient.points(degrees: 155, in: geo.size)
                shape.fill(LinearGradient(
                    stops: [.init(color: BlisterGlass.glass.opacity(0.17), location: 0),
                            .init(color: BlisterGlass.glass.opacity(0.04), location: 0.42),
                            .init(color: BlisterGlass.glass.opacity(0.09), location: 1)],
                    startPoint: p.start, endPoint: p.end))
            }
            InnerShadow(shape: shape, color: BlisterGlass.shade.opacity(0.5),
                        x: m.shade.x, y: m.shade.y, blur: m.shade.blur)
            InnerShadow(shape: shape, color: BlisterGlass.snow.opacity(0.10),
                        x: m.glow.x, y: m.glow.y, blur: m.glow.blur)
            InnerShadow(shape: shape, color: Color.white.opacity(m.topCatchOpacity),
                        x: 0, y: m.topCatch, blur: 0)
            shape.strokeBorder(BlisterGlass.snow.opacity(0.34), lineWidth: m.rim)
        }
        .allowsHitTesting(false)
    }

    /// Over the art: `::before`, the specular arc, and `::after`, two glare
    /// streaks across the whole bubble.
    private func sheen(_ shape: RoundedRectangle) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                let p = CSSGradient.points(degrees: 118, in: geo.size)
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(0), location: 0.58),
                            .init(color: .white.opacity(0.16), location: 0.61),
                            .init(color: .white.opacity(0), location: 0.64),
                            .init(color: .white.opacity(0), location: 0.70),
                            .init(color: .white.opacity(0.07), location: 0.72),
                            .init(color: .white.opacity(0), location: 0.75)],
                    startPoint: p.start, endPoint: p.end))
                // top 7%, left 7%, 46% × 20%, rotated −20°, closest-side fade.
                Ellipse()
                    .fill(EllipticalGradient(colors: [.white.opacity(0.42), .white.opacity(0)]))
                    .frame(width: w * 0.46, height: h * 0.20)
                    .rotationEffect(.degrees(-20))
                    .offset(x: w * 0.07, y: h * 0.07)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Outside the bubble: the drop shadow and the two halo rings. Clipped
    /// to OUTSIDE the shape, as CSS outer shadows are — the glass is
    /// translucent, so a shadow painted under it would darken it.
    private func outside(_ shape: RoundedRectangle) -> some View {
        let m = metrics
        return ZStack {
            OuterShadow(shape: shape, color: .black.opacity(m.drop.opacity),
                        y: m.drop.y, blur: m.drop.blur, spread: m.drop.spread)
            shape.inset(by: -m.haloOuter)
                .strokeBorder(BlisterGlass.snow.opacity(0.15), lineWidth: m.haloOuter)
            shape.inset(by: -m.haloInner)
                .strokeBorder(BlisterGlass.snow.opacity(0.035), lineWidth: m.haloInner)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension BlisterBubble where Art == EmptyView {
    /// The empty bubble: holds the hollow and nothing else.
    init(emptyMetrics metrics: BlisterBubbleMetrics = .regular) {
        self.metrics = metrics
        self.art = nil
    }
}

/// `.bubble.empty .hollow`: where the art would sit — a faint cool light
/// pooled a little above center and a barely-there keyline.
struct BlisterHollow: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // radial-gradient(70% 60% at 50% 38%, snow .06, snow 0 72%): an
            // ellipse with radii 70%×60% of the box, centered at (50%, 38%).
            Ellipse()
                .fill(EllipticalGradient(
                    stops: [.init(color: BlisterGlass.snow.opacity(0.06), location: 0),
                            .init(color: BlisterGlass.snow.opacity(0), location: 0.72)],
                    center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                .frame(width: w * 1.4, height: h * 1.2)
                .position(x: w * 0.5, y: h * 0.38)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(BlisterGlass.snow.opacity(0.05), lineWidth: 1) }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Art

/// What goes in a now-playing bubble: the cover filling the art square, or —
/// with no cover — the initials monogram, which scales with the box it is
/// given exactly like real artwork (never a rigid tile; see the iPhone Duo
/// layout rules).
struct PackArt: View {
    let image: PlatformImage?
    /// The text the monogram's initials come from (artist, else title).
    let monogram: String

    var body: some View {
        if let image {
            Color.clear
                .overlay {
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipped()
        } else {
            GeometryReader { geo in
                MonogramTile(text: monogram, size: min(geo.size.width, geo.size.height))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - Glass constants and drawing helpers

/// Palette-adjacent colors for the plastic (Yeti-only; spec "Tokens").
enum BlisterGlass {
    /// rgba(233,238,247,·): snow, as light on plastic.
    static var snow: Color { Color(hex: 0xE9EEF7) }
    /// rgba(225,233,250,·): the bubble's glass tint.
    static var glass: Color { Color(hex: 0xE1E9FA) }
    /// rgba(4,7,16,·): the shade pooling in the plastic.
    static var shade: Color { Color(hex: 0x040710) }
    /// rgba(190,210,255,·) → rgba(15,20,36,·): the glaze over the art.
    static var glazeTop: Color { Color(hex: 0xBED2FF) }
    static var glazeBottom: Color { Color(hex: 0x0F1424) }
}

/// CSS `linear-gradient(<angle>deg, …)` endpoints for a box: the gradient
/// line runs through the center at `degrees` (0 = up, 90 = right), long
/// enough that the corners land on 0% and 100%.
enum CSSGradient {
    static func points(degrees: Double, in size: CGSize) -> (start: UnitPoint, end: UnitPoint) {
        guard size.width > 0, size.height > 0 else { return (.top, .bottom) }
        let theta = degrees * .pi / 180
        let dx = sin(theta), dy = -cos(theta)
        let half = (abs(size.width * dx) + abs(size.height * dy)) / 2
        let ux = dx * half / size.width, uy = dy * half / size.height
        return (UnitPoint(x: 0.5 - ux, y: 0.5 - uy), UnitPoint(x: 0.5 + ux, y: 0.5 + uy))
    }
}

/// CSS `inset x y blur color`: color everywhere except the shape shifted by
/// (x, y), blurred, clipped to the shape.
private struct InnerShadow<S: InsettableShape>: View {
    let shape: S
    let color: Color
    let x: CGFloat
    let y: CGFloat
    let blur: CGFloat

    var body: some View {
        let pad = blur * 2 + max(abs(x), abs(y)) + 4
        ZStack {
            Rectangle().fill(color).padding(-pad)
            shape.fill(Color.black)
                .offset(x: x, y: y)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .blur(radius: blur / 2)
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

/// CSS outer `0 y blur spread color`, painted only OUTSIDE the shape.
private struct OuterShadow<S: InsettableShape>: View {
    let shape: S
    let color: Color
    let y: CGFloat
    let blur: CGFloat
    let spread: CGFloat

    var body: some View {
        let pad = blur * 2 + abs(y) + abs(spread) + 4
        shape.inset(by: -spread)
            .fill(color)
            .blur(radius: blur / 2)
            .offset(y: y)
            .mask {
                ZStack {
                    Rectangle().padding(-pad)
                    shape.fill(Color.black).blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}
