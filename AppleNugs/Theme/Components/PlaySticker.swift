import SwiftUI

/// Yeti's play/pause control: a disc of sticker stock with the play or pause
/// glyph in night ink, set a few degrees off true. Translated from the design
/// sheet's `.play-sticker` (+ its per-site sizes and the `#i-play`/`#i-pause`
/// symbols, drawn here as shapes from the same 24-unit paths).
///
/// A view, not a button: hosts wrap it in their own `Button`/`HapticButton`
/// with `.buttonStyle(.plain)`, so haptics, `.disabled` and the action stay
/// theirs. It carries its own "Play"/"Pause" accessibility label; a host that
/// labels the button itself overrides it.
///
/// While `isBuffering`, the glyph gives way to the spinner the 68pt circle
/// shows today — inside the same disc, so the control never changes size.
struct PlaySticker: View {
    /// The design's four sites.
    enum Size: CGFloat, CaseIterable, Sendable {
        /// iPhone / Duo now playing.
        case s64 = 64
        /// Home heroes.
        case s54 = 54
        /// iOS expanded panel, Mac miniplayer.
        case s46 = 46
        /// Mac transport bar.
        case s34 = 34

        var diameter: CGFloat { rawValue }

        /// The glyph box the design draws at each size (28/24/22/16 of 64/54/46/34).
        var glyph: CGFloat {
            switch self {
            case .s64: return 28
            case .s54: return 24
            case .s46: return 22
            case .s34: return 16
            }
        }
    }

    /// The `.play-sticker` CSS sets no rotation; the plan asks for "a few
    /// degrees off true". The sheet's gentlest sticker tilt (the label tag's).
    static let tilt: Angle = .degrees(-4)

    @Environment(\.theme) private var theme

    let isPlaying: Bool
    var isBuffering: Bool = false
    var size: Size = .s64

    var body: some View {
        let ink = theme.stickerInk
        ZStack {
            StickerStock(shape: Circle(), lift: .play)
            if isBuffering {
                // `.tint` colors the spinner on iOS; AppKit's spinner ignores it
                // and draws light-gray under the app's forced dark scheme, which
                // vanishes on the stock. A light scheme makes it dark there.
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(size.diameter >= 54 ? .regular : .small)
                    .tint(ink)
                    .environment(\.colorScheme, .light)
            } else {
                Group {
                    if isPlaying {
                        PauseGlyph().fill(ink)
                    } else {
                        PlayGlyph().fill(ink)
                    }
                }
                .frame(width: size.glyph, height: size.glyph)
            }
        }
        .frame(width: size.diameter, height: size.diameter)
        .rotationEffect(Self.tilt)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

/// `#i-play`: M8 5.5v13 a1 1 0 0 0 1.5.86 l10.4-6.5 a1 1 0 0 0 0-1.72 L9.5 4.64
/// A1 1 0 0 0 8 5.5Z — a triangle with 1-unit rounded corners, optically set
/// right of center, in a 24-unit box.
struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * u, y: rect.midY - 12 * u)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
        // The sharp triangle the rounded path is cut from (the path's straight
        // edges extended to their intersections).
        let top = p(8, 3.7), bottom = p(8, 20.3), tip = p(21.28, 12)
        let r = 1.1 * u
        var path = Path()
        path.move(to: p(8, 12))
        path.addArc(tangent1End: bottom, tangent2End: tip, radius: r)
        path.addArc(tangent1End: tip, tangent2End: top, radius: r)
        path.addArc(tangent1End: top, tangent2End: bottom, radius: r)
        path.closeSubpath()
        return path
    }
}

/// `#i-pause`: two 4×14 bars, rx 1.6, at x 6.5 and 13.5 (y 5) in a 24-unit box.
struct PauseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * u, y: rect.midY - 12 * u)
        var path = Path()
        for x in [6.5, 13.5] as [CGFloat] {
            path.addRoundedRect(
                in: CGRect(x: o.x + x * u, y: o.y + 5 * u, width: 4 * u, height: 14 * u),
                cornerSize: CGSize(width: 1.6 * u, height: 1.6 * u))
        }
        return path
    }
}
