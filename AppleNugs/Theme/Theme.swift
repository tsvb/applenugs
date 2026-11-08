import SwiftUI

// The design system: ONE token struct, `Theme.yeti`, read from the environment
// as `@Environment(\.theme)` (its default value — nothing has to inject it).
// Views ask for roles (`theme.palette.textSecondary`, `theme.type.title(17)`,
// `theme.copy.homeLede`), never for literal colors or strings. This file is
// the only place literal hex lives. The design pages behind every value are
// `docs/design/yeti-theme/` (the token sheet is the first panel of
// `yeti-theme.html`).

// MARK: - Token groups

/// Semantic color roles. Views ask for `textSecondary`, never "slush".
struct Palette: Sendable {
    /// Night: the window background.
    let base: Color
    /// Shelves: rows, cards, sheets.
    let raised: Color
    /// Frost: 1pt keylines and dividers.
    let hairline: Color
    /// Snow, slush and the idle gray.
    let textPrimary, textSecondary, textIdle: Color
    /// Foil: kept for things that move with time (scrubs, the pill ring, the
    /// foil sweep, the caret, download/resume progress). Never a control fill.
    let accent: Color
    /// Active/playing emphasis: the sale yellow.
    let playState: Color
    /// The backing card stock under the blister pack, monograms and posters.
    let cardStock: Color
    /// Night ink printed on sticker stock.
    let stickerInk: Color
    /// Sticker stock's radial gradient stops (`StickerStock`): highlight →
    /// sale yellow at 55% → edge.
    let stickerHighlight, stickerSale, stickerEdge: Color
    /// `YetiSegmentedControl`'s selected segment: a lighter shelf than `raised`.
    let segmentThumb: Color
    /// The near-black behind a video error drawn over the player.
    let videoErrorBackdrop: Color
    /// The blister bubble's plastic (`BlisterGlass`): its glass tint, the shade
    /// pooling in it, and the top of the glaze over the art. Light on the
    /// plastic is `textPrimary`; the glaze's bottom is `base`.
    let bubbleGlass, bubbleShade, bubbleGlaze: Color
}

/// Fonts as size-taking closures so a point size is a call, not six stored fonts.
struct Typography: Sendable {
    let hero, title, section: @Sendable (CGFloat) -> Font
    let body, numeric: @Sendable (CGFloat) -> Font
}

/// The app's voice: idle/empty states and section headers.
struct Copy: Sendable {
    /// The now-playing surfaces' idle line.
    let nowPlaying = "It's on its way"
    /// The dashboard's idle line.
    let dashboardIdle = "It's on its way"
    /// `DashboardPanel`'s three section headers.
    let dashNow = "Here it comes"
    let dashQuality = "Says so on the box"
    let dashUpNext = "Coming up next"
    /// Downloads' empty-state title (`DownloadsView`).
    let downloadsEmptyTitle = "Nothing boxed up yet"
    /// Videos' three section titles (`VideosView`).
    let videosResume = "Pick up where you left off"
    let videosLive = "Live and coming up"
    let videosExclusives = "Just streamed"
    /// The video detail's live-edge button label while it is disabled
    /// (`VideoDetailView`); enabled, it reads "Go Live".
    let liveEdgeDisabled = "At the live edge"
    /// Home's line under the greeting (`HomeView`).
    let homeLede = "Pick up where you left off, or dig through the crate."
    /// The listening ledger's section header (`ListeningLedger`).
    let ledgerTitle = "The nice list"

    /// Search's no-results line for a query (`SearchView`, `ArtistListView`).
    func searchNoResults(_ query: String) -> String {
        "Nothing on the shelf for \u{201C}\(query)\u{201D}"
    }
}

// MARK: - Theme

/// The complete look, assembled from tokens. A value type read from the
/// environment (`\.theme`, whose default is `Theme.yeti`).
struct Theme: Sendable {
    let palette: Palette
    let type: Typography
    let copy: Copy
}

extension Theme {
    /// Yeti, an unofficial player's own look: night-blue shelves, snow type,
    /// sale-yellow stickers and one foil accent kept for things that move with
    /// time. Heavy rounded type, dark only.
    static let yeti = Theme(
        palette: Palette(
            base: Color(hex: 0x0F1424), raised: Color(hex: 0x18203A),
            hairline: Color(hex: 0x2E3A5C),
            textPrimary: Color(hex: 0xE9EEF7),
            textSecondary: Color(hex: 0x9FABCE),
            textIdle: Color(hex: 0x8590B0),
            accent: Color(hex: 0xFF8FC4),
            playState: Color(hex: 0xF2E27A),
            cardStock: Color(hex: 0x1B2443),
            stickerInk: Color(hex: 0x0F1424),
            stickerHighlight: Color(hex: 0xFBF1A6),
            stickerSale: Color(hex: 0xF2E27A),
            stickerEdge: Color(hex: 0xE3D267),
            segmentThumb: Color(hex: 0x2A355A),
            videoErrorBackdrop: Color(hex: 0x05070D),
            bubbleGlass: Color(hex: 0xE1E9FA),
            bubbleShade: Color(hex: 0x040710),
            bubbleGlaze: Color(hex: 0xBED2FF)),
        type: Typography(
            hero:    { .system(size: $0, weight: .heavy, design: .rounded) },
            title:   { .system(size: $0, weight: .heavy, design: .rounded) },
            section: { .system(size: $0, weight: .heavy, design: .rounded) },
            body:    { .system(size: $0, design: .rounded) },
            numeric: { .system(size: $0, design: .rounded).monospacedDigit() }),
        copy: Copy())
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255)
    }
}
