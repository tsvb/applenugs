import SwiftUI

// Yeti's one flourish: when a new track starts, a band of foil pink crosses
// the now-playing title once, left to right, over 1,020 ms on the standard
// ease-in-out, then the title rests in snow. Translated from the design
// sheet's `.sweep` rules:
//
//     linear-gradient(100deg, snow 0 42%, foil 48%, foil 52%, snow 58% 100%)
//     background-size: 220% 100%; background-clip: text;
//     animation: 1.02s cubic-bezier(.4, 0, .2, 1), position 100% → 0%
//
// Sites (spec): the now-playing card title and the Mac miniplayer title.
// Nowhere else.

extension View {
    /// Runs Yeti's foil sweep across this title when `FoilSweepTrigger` says a
    /// new track has started playing. Apply it directly to the title `Text`,
    /// BEFORE any frame or padding, so the band spans the glyphs and not the
    /// slack around them.
    ///
    /// - `identity`: the current track's catalog id — pass
    ///   `player.current?.trackId` (see `FoilSweepTrigger` for why not the
    ///   per-entry `id`).
    /// - `isPlaying`: `player.isPlaying`.
    ///
    /// Reads **no playback time**: the inputs are plain values and the band
    /// runs on its own keyframe clock, so it adds nothing to the 4 Hz tick and
    /// the host must not pass anything derived from `currentTime` either.
    /// The band is an overlay masked by the title's own glyphs, so the title
    /// never changes size or wraps differently mid-pass. Skipped (the title
    /// simply stays snow) under Reduce Motion.
    func foilSweep(identity: String?, isPlaying: Bool) -> some View {
        modifier(FoilSweepModifier(identity: identity, isPlaying: isPlaying))
    }
}

struct FoilSweepModifier: ViewModifier {
    let identity: String?
    let isPlaying: Bool

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var trigger = FoilSweepTrigger()
    /// Bumped once per sweep; the keyframe animator replays on each change.
    @State private var runs = 0

    /// 1,020 ms on `cubic-bezier(.4, 0, .2, 1)`.
    static let duration: TimeInterval = 1.02
    static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.4, y: 0),
                                        endControlPoint: UnitPoint(x: 0.2, y: 1))

    func body(content: Content) -> some View {
        // Read here, on the main actor: the animator's content closure is not.
        let foil = theme.palette.accent
        return content
            .overlay {
                // At rest the animator sits at 1: the band has left the
                // title on the trailing side, so nothing is drawn.
                Color.clear
                    .keyframeAnimator(initialValue: 1.0, trigger: runs) { clear, phase in
                        clear.overlay {
                            if phase > 0, phase < 1 {
                                FoilBand(phase: phase, foil: foil)
                            }
                        }
                    } keyframes: { _ in
                        KeyframeTrack {
                            MoveKeyframe(0.0)
                            LinearKeyframe(1.0, duration: Self.duration, timingCurve: Self.curve)
                        }
                    }
                    .mask { content }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear { trigger.appear(identity: identity, isPlaying: isPlaying) }
            .onChange(of: identity) { evaluate() }
            .onChange(of: isPlaying) { evaluate() }
    }

    private func evaluate() {
        // The trigger advances even when the band won't run (Reduce Motion),
        // so toggling it later can't replay a stale track's sweep.
        guard trigger.observe(identity: identity, isPlaying: isPlaying),
              !reduceMotion else { return }
        runs &+= 1
    }
}

/// The foil band at one moment of the sweep, drawn across the whole frame it
/// is given (the host masks it to the glyphs). `phase` is the EASED progress,
/// 0...1. Pure function of `phase` so a review still can be rendered at any
/// point without a clock.
///
/// Proportions follow the CSS: the gradient image is 220% of the title's
/// width, so the band (snow→foil fade 6%, solid foil 4%, foil→snow fade 6% of
/// that image) is 35.2% of the title's width, tilted 10° (the gradient's 100°).
/// One deliberate difference: the CSS band starts and ends partly ON the
/// title (its 100%/0% positions leave ~58% foil on the first/last glyph, which
/// the `.rest` class then pops off). Here the band travels from fully off the
/// leading edge to fully off the trailing edge — the same crossing at the
/// midpoint, with no pop at either end, so the title rests in plain snow.
struct FoilBand: View {
    let phase: CGFloat
    let foil: Color

    /// Band width as a fraction of the title's width: 16% of a 220% image.
    static let widthFraction: CGFloat = 0.16 * 2.2
    /// The gradient's 100° is 10° off a vertical band.
    static let tilt = Angle.degrees(10)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let band = max(w * Self.widthFraction, 1)
            // Travel far enough that the TILTED band is clear of the title at
            // both ends: its top and bottom lean half of h·tan(10°) either way.
            let lean = h * CGFloat(tan(Self.tilt.radians)) / 2
            let start = -band / 2 - lean
            let end = w + band / 2 + lean
            let centerX = start + (end - start) * phase
            Rectangle()
                .fill(LinearGradient(
                    stops: [.init(color: foil.opacity(0), location: 0),
                            .init(color: foil, location: 6 / 16),
                            .init(color: foil, location: 10 / 16),
                            .init(color: foil.opacity(0), location: 1)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: band, height: h + 2 * band + 2 * lean)
                .rotationEffect(Self.tilt)
                .position(x: centerX, y: h / 2)
        }
    }
}
