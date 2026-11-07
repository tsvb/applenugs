import Foundation

/// What the Yeti price sticker (the lossless badge) says — or `nil` when it
/// should not be shown at all.
///
/// Pure Foundation so the rules are pinned host-free in `AppleNugsTests`. The
/// view (`PriceSticker`) feeds it plain values; `PriceStickerLabel(player:)`
/// in `PriceSticker.swift` reads them off `PlayerService` correctly.
///
/// **Presence is the CALLER's job and is gated on `player.current`, never on
/// the stream pick or the specs.** `PlayerService.startCurrent()` nils both
/// `nowPick` and `specs` on every track change, so a sticker gated on them
/// would blink off and on at each track boundary (the Signal-section bug class,
/// one sticker at a time). That is why an unknown pick still yields a label:
///
/// - pick unknown → "Lossless", no spec line. Tier 7 (ALAC 16) is always tried
///   first (`StreamTierPlan`), so lossless is the honest default while the
///   pick resolves. Any depth/rate passed in is ignored: it can only be stale.
/// - pick known and lossless → "Lossless" over "24/96" (bit depth / sample rate
///   in whole kHz, 44.1 → "44"); no spec line while either value is unknown.
/// - pick known and NOT lossless → `nil`: hidden (the view keeps its footprint).
struct PriceStickerLabel: Equatable, Sendable {
    /// The top line, always "Lossless".
    let title: String
    /// The bottom line, e.g. "24/96" or "16/44"; `nil` while depth or rate is
    /// unknown (or the pick is).
    let spec: String?
    /// What VoiceOver reads: "Lossless, 24-bit 96 kilohertz" / "Lossless".
    /// Speaks the true rate ("44.1 kilohertz") where the printed line rounds.
    let accessibilityLabel: String

    static let title = "Lossless"

    /// - Parameters:
    ///   - pickKnown: whether a stream pick (format) is known for the current track.
    ///   - isLossless: the pick's `AudioFormat.isLossless`; ignored when the pick is unknown.
    ///   - bitDepth: bits per sample; `nil` or `<= 0` is unknown.
    ///   - sampleRate: in Hz; `nil`, `<= 0` or non-finite is unknown.
    init?(pickKnown: Bool, isLossless: Bool, bitDepth: Int?, sampleRate: Double?) {
        title = Self.title
        guard pickKnown else {
            spec = nil
            accessibilityLabel = Self.title
            return
        }
        guard isLossless else { return nil }

        guard let bits = bitDepth, bits > 0,
              let hz = sampleRate, hz > 0, hz.isFinite else {
            spec = nil
            accessibilityLabel = Self.title
            return
        }
        spec = "\(bits)/\(Self.wholeKilohertz(hz))"
        accessibilityLabel = "\(Self.title), \(bits)-bit \(Self.spokenKilohertz(hz)) kilohertz"
    }

    /// Whole kHz for the printed line, truncated the way rates are written on
    /// the box: 44,100 → 44, 88,200 → 88, 96,000 → 96. Rounds to whole Hz
    /// first so a decoder's 47,999.99 still reads 48.
    private static func wholeKilohertz(_ hz: Double) -> Int {
        Int(hz.rounded()) / 1000
    }

    /// kHz to one decimal, trailing ".0" dropped: 44,100 → "44.1", 96,000 →
    /// "96". Integer arithmetic, so no locale decides the decimal separator.
    private static func spokenKilohertz(_ hz: Double) -> String {
        let tenths = Int((hz / 100).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }
}
