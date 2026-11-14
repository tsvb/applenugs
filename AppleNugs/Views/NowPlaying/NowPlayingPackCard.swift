import SwiftUI

/// The now-playing card (the blister pack): the cover sealed in the bubble on
/// card stock, the price sticker on the bubble's corner, and the title printed
/// on the card at nameplate size with the meta line under it. Translated from
/// the design sheet's `.np .card` / `.name h2.plate` / `.name .meta`.
///
/// Hosted by `NowPlayingScreen` in place of its artwork + title block —
/// iPhone full screen, the Duo's player column, the Mac Now Playing window.
/// Takes plain values (no `PlayerService`), so it has no playback-time input at
/// all and an offscreen render can build it as-is.
///
/// **Art yields height** (CLAUDE.md, iPhone Duo layout rules): the pack is a
/// flexible child of the player's stack, and inside it `BlisterPack` gives the
/// nameplate and meta their natural height first, so on a short canvas the
/// bubble shrinks and the text keeps its lines.
struct NowPlayingPackCard: View {
    @Environment(\.theme) private var theme

    let track: QueueTrack?
    let image: PlatformImage?
    let isPlaying: Bool
    /// The corner sticker's label; `nil` draws none. Pass
    /// `PriceStickerLabel(player:)` (it gates on `player.current`).
    let price: PriceStickerLabel?

    var body: some View {
        // ONE pack for both "nothing loaded" and "playing": branching to the
        // empty pack on `track == nil` would change the title's view identity
        // and reset the foil sweep's trigger just as the first track arrives.
        BlisterPack(price: price, maxBubbleSide: NowPlayingCardMetrics.maxBubble) {
            PackArt(image: image, monogram: track?.artist ?? track?.title ?? "?")
        } below: {
            VStack(alignment: .leading, spacing: NowPlayingCardMetrics.metaGap) {
                NowPlayingNameplate(text: track?.title ?? "Nothing playing",
                                    identity: track?.trackId,
                                    isPlaying: isPlaying)
                if let track {
                    NowPlayingMetaText(track: track)
                        .font(theme.type.body(NowPlayingCardMetrics.metaSize))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

/// The card title: heavy rounded at 44pt, scaling down to a 34pt floor before
/// it wraps a third line (`.name h2.plate`: "34 to 44pt, scales down before it
/// wraps a third line"). Only a title that still needs more than two lines AT
/// the floor gets a third (and truncates past it), so a long segue ("Arcadia >
/// Hot Tea > Madhuvan") stays readable in the Duo's narrow upright column.
///
/// Which mode applies is decided by two hidden probes set at the floor size
/// and measured at the FULL available width (not the title's own, which
/// depends on the mode — that would loop): the title with no line limit, and
/// with two. Taller unlimited = it needs a third line at 34pt. The probes sit
/// in a background, so they never add height; the visible `Text` keeps one
/// identity across both modes, so the foil sweep's state survives a flip.
///
/// The foil sweep sits on the `Text` itself, before any frame, so the band
/// spans the glyphs; its mask redraws this same text at the same proposal, so
/// it scales with it.
struct NowPlayingNameplate: View {
    @Environment(\.theme) private var theme

    let text: String
    /// The catalog id (`QueueTrack.trackId`), not the per-entry queue id.
    let identity: String?
    let isPlaying: Bool

    @State private var heightAtFloor = (unlimited: CGFloat(0), twoLines: CGFloat(0))

    private var needsThirdLine: Bool {
        heightAtFloor.unlimited > heightAtFloor.twoLines + 0.5
    }

    var body: some View {
        let m = NowPlayingCardMetrics.self
        let third = needsThirdLine
        Text(text)
            .font(theme.type.hero(third ? m.plateFloor : m.plateSize))
            .tracking(m.plateTracking)
            .foregroundStyle(theme.palette.textPrimary)
            .lineLimit(third ? 3 : 2)
            .minimumScaleFactor(third ? 1 : m.plateFloor / m.plateSize)
            .multilineTextAlignment(.leading)
            .foilSweep(identity: identity, isPlaying: isPlaying)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    probe(lineLimit: nil)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            heightAtFloor.unlimited = $0
                        }
                    probe(lineLimit: 2)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            heightAtFloor.twoLines = $0
                        }
                }
                .hidden()
                .accessibilityHidden(true)
            }
    }

    private func probe(lineLimit: Int?) -> some View {
        Text(text)
            .font(theme.type.hero(NowPlayingCardMetrics.plateFloor))
            .tracking(NowPlayingCardMetrics.plateTracking)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Every number the blister-pack now-playing layout uses, in one place so the
/// height budget can be checked offscreen with the exact same constants.
///
/// Budget at the Duo's flat inner-display column (433×635pt) with a two-line
/// title and a two-line meta: the chrome around the bubble (header, card
/// padding and hang slot, nameplate, meta, scrub, transport, volume, bottom
/// row, these gaps) is fixed, and the bubble takes what is left. Today's 22pt
/// stack spacing alone would cost ~150pt across seven gaps and leave the bubble
/// almost nothing, so the card layout uses the mockup's tighter margins.
enum NowPlayingCardMetrics {
    /// The player stack's vertical padding (today 18).
    static let verticalPadding: CGFloat = 12
    /// `.np .card { margin: 4px 20px 0 }`
    static let cardTop: CGFloat = 4
    static let cardInset: CGFloat = 20
    /// `.scrub { margin-top: 22px }`, trimmed.
    static let scrubTop: CGFloat = 18
    /// `.transport { margin-top: 12px }`, trimmed.
    static let transportTop: CGFloat = 8
    static let volumeTop: CGFloat = 8
    /// `.np-bottom { margin-top: 14px }`, trimmed (the row's 44pt targets
    /// already carry air).
    static let bottomTop: CGFloat = 4
    /// The bubble's cap: about the sheet's 298pt, so a tall canvas (the Mac
    /// window stretched, the upright Duo with the player alone) doesn't blow
    /// the cover up past the pack's proportions.
    static let maxBubble: CGFloat = 320
    /// `.name h2.plate { font-size: 44px; letter-spacing: -.02em }`
    static let plateSize: CGFloat = 44
    static let plateFloor: CGFloat = 34
    static let plateTracking: CGFloat = -0.88
    /// `.name .meta { margin: 6px 0 0; font-size: 15px }`
    static let metaGap: CGFloat = 6
    static let metaSize: CGFloat = 15
}
