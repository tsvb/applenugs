import SwiftUI

// MARK: - Variation axes

/// Which bespoke now-playing treatment a theme uses in the transport bar.
enum TransportSignature: Sendable {
    case standard      // the original text block, token-styled
    case tapeLabel     // Tape Room: art chip + amber under-rule progress
    case jCard         // Shoebox: cassette J-card strip
    case faceplate     // The Receiver: full brushed-metal VU faceplate (deferred)
    case clickWheel    // Click Wheel: monochrome circular-pad player (iOS full screen)
}

/// Whether the accent is a fixed color or derived from the current cover art.
enum AccentMode: Sendable {
    case staticAccent
    case artDriven(fallback: Color)
}

/// How (if at all) the extracted album-art color washes into the chrome.
enum WashStyle: Sendable {
    case none
    case linear        // Soundboard: gradient behind transport + now-playing
    case warmLow       // Shoebox: faint warm wash
    case bloom18       // The Receiver: 18% bloom behind the inspector art only
}

/// Opt-in bespoke behaviors, kept off the host views so nothing forks.
struct Capabilities: OptionSet, Sendable {
    let rawValue: Int
    static let artWash          = Capabilities(rawValue: 1 << 0)
    static let equalizerRows    = Capabilities(rawValue: 1 << 1)
    static let vuMeter          = Capabilities(rawValue: 1 << 2)
    static let condensedHeaders = Capabilities(rawValue: 1 << 3)
    static let indexLetterTab   = Capabilities(rawValue: 1 << 4)
    /// Yeti: the blister pack (card stock + bubble) around the now-playing
    /// card's art, both Home heroes, the Mac miniplayer and the Mac Now Playing
    /// window; the EMPTY pack on sign-in, connection-failed and empty states;
    /// the iPhone Home hero.
    static let blisterPack      = Capabilities(rawValue: 1 << 5)
    /// Yeti: the play sticker, the price sticker (replaces the format badge),
    /// the static row sticker (replaces `EqualizerBars`' bounce, decided per
    /// call site), label stickers (Live/Free) and plain tags (4K/Audio/PPV).
    static let stickers         = Capabilities(rawValue: 1 << 6)
    /// Yeti: the one-shot foil sweep across the now-playing title on a new track.
    static let foilSweep        = Capabilities(rawValue: 1 << 7)
    /// Yeti: sentence-case headers, no eyebrows, errors said in snow rather than
    /// red, snow-with-night-ink primary buttons, and the barker copy. Also turns
    /// the app-wide root tint to `textPrimary` (see `Theme.rootTint(art:)`).
    static let plainVoice       = Capabilities(rawValue: 1 << 8)
}

// MARK: - Token groups

/// Semantic color roles. Views ask for `textSecondary`, never "taupe".
struct Palette: Sendable {
    let base, raised, hairline: Color
    let textPrimary, textSecondary, textIdle: Color
    let accent: Color            // static fallback; art may override at runtime
    let losslessBadge: Color?    // distinct lossless tint (Tape Room teal), else nil
    let playState: Color         // active/playing emphasis
    let vuPeak: Color?           // VU peak tick (The Receiver only)
    let labelPaper: Color?       // label/card stock: Tape Room's write-on label, Yeti's backing card
    let labelInk: Color?         // ink on that stock: Tape Room's pen, Yeti's sticker ink
}

/// Fonts as size-taking closures so a point size is a call, not six stored fonts.
struct Typography: Sendable {
    let hero, title, section: @Sendable (CGFloat) -> Font
    let body, numeric: @Sendable (CGFloat) -> Font
}

/// Per-theme copy so idle/empty states and section headers carry personality.
///
/// The `var` fields carry defaults (today's strings, verbatim from the views
/// that hardcode them) so the memberwise init keeps every existing theme
/// literal compiling unchanged; only Yeti overrides them.
struct IdleCopy: Sendable {
    let nowPlaying: String
    let dashboardIdle: String
    let dashHeaders: (now: String, quality: String, upNext: String)
    /// Downloads' empty-state title (`DownloadsView`).
    var downloadsEmptyTitle: String = "Nothing downloaded"
    /// Search's no-results line for a query; nil = the system
    /// `ContentUnavailableView.search(text:)` (`SearchView`, `ArtistListView`).
    var searchNoResults: @Sendable (String) -> String? = { _ in nil }
    /// Videos' three section titles (`VideosView`).
    var videosResume: String = "Continue Watching"
    var videosLive: String = "Live & Upcoming"
    var videosExclusives: String = "Recent Exclusives"
    /// The video detail's live-edge button label while it is disabled
    /// (`VideoDetailView`); enabled, it reads "Go Live" in every theme.
    var liveEdgeDisabled: String = "Go Live"
    /// Home's line under the greeting (`HomeView`).
    var homeLede: String = "Pick up where you left off — or dig through the crate."
    /// The listening ledger's title (`ListeningLedger`): an eyebrow by default,
    /// a section header under `.plainVoice`.
    var ledgerTitle: String = "LISTENING"
}

// MARK: - Theme

/// A complete look, assembled from tokens. Value type read from the environment,
/// so switching republishes one value and re-renders only the affected subtrees.
struct Theme: Equatable, Sendable {
    let id: ThemeID
    let palette: Palette
    let type: Typography
    let textureOpacity: Double
    let copy: IdleCopy
    let caps: Capabilities
    let transport: TransportSignature
    let accentMode: AccentMode
    let washStyle: WashStyle
    let darkOnly: Bool

    // Closure-typed Typography isn't Equatable; identity is the key that matters.
    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id }

    /// The accent to actually use: the live art color when the theme is
    /// art-driven and a color is available, else the static accent.
    func effectiveAccent(art: Color?) -> Color {
        switch accentMode {
        case .staticAccent:      return palette.accent
        case .artDriven(let fb): return art ?? fb
        }
    }

    /// Color for the currently-playing emphasis (active row, now-playing glyph).
    /// Art-driven themes follow the cover color so it matches the rest of the
    /// chrome; static themes keep their deliberate play-state color (Tape Room
    /// amber, Shoebox rust, The Receiver tube-teal).
    func activeEmphasis(art: Color?) -> Color {
        if case .artDriven = accentMode { return effectiveAccent(art: art) }
        return palette.playState
    }

    /// The tint `ThemedRoot` applies to the whole app. Under `.plainVoice` it is
    /// snow (`textPrimary`), so system-tinted controls (prominent buttons, the
    /// selected tab, toggles, links, untinted sliders) never paint an accent
    /// fill; such a theme applies its accent explicitly, only where time moves
    /// (scrub sliders, the pill ring, progress). Every other theme keeps
    /// `effectiveAccent(art:)`, exactly as before.
    func rootTint(art: Color?) -> Color {
        if caps.contains(.plainVoice) { return palette.textPrimary }
        return effectiveAccent(art: art)
    }

    var consumesArtColor: Bool {
        if case .artDriven = accentMode { return true }
        return washStyle != .none
    }

    static func make(_ id: ThemeID) -> Theme {
        switch id {
        case .tapeRoom:   return tapeRoom
        case .soundboard: return soundboard
        case .shoebox:    return shoebox
        case .tapeDeck:   return tapeDeck
        case .clickWheel: return clickWheel
        case .yeti:       return yeti
        }
    }
}

// MARK: - The themes (the only place literal hex lives)

extension Theme {
    static let tapeRoom = Theme(
        id: .tapeRoom,
        palette: Palette(
            base: Color(hex: 0x14110E), raised: Color(hex: 0x1B1714), hairline: Color(hex: 0x2E2823),
            textPrimary: Color(hex: 0xF2EADF), textSecondary: Color(hex: 0xA89B8B), textIdle: Color(hex: 0x6E6357),
            accent: Color(hex: 0xE8A13A), losslessBadge: Color(hex: 0x5FB6A6),
            playState: Color(hex: 0xE8A13A), vuPeak: nil,
            labelPaper: Color(hex: 0xFBF9F3), labelInk: Color(hex: 0x241C12)),
        type: Typography(
            hero:    { .system(size: $0, weight: .semibold, design: .serif) },
            title:   { .system(size: $0, weight: .medium,   design: .serif) },
            section: { .system(size: $0, weight: .semibold, design: .serif) },
            body:    { .system(size: $0) },
            numeric: { .system(size: $0, design: .monospaced) }),
        textureOpacity: 0,
        copy: IdleCopy(
            nowPlaying: "Nothing playing. Press / to search.",
            dashboardIdle: "Idle",
            dashHeaders: ("Now Playing", "Quality", "Up Next")),
        caps: [],
        transport: .tapeLabel,
        accentMode: .staticAccent,
        washStyle: .none,
        darkOnly: false)

    static let soundboard = Theme(
        id: .soundboard,
        palette: Palette(
            base: Color(hex: 0x0C0B0E), raised: Color(hex: 0x17161A), hairline: Color(hex: 0x26262A),
            textPrimary: Color(hex: 0xF4F1EC), textSecondary: Color(hex: 0x9A958E), textIdle: Color(hex: 0x6E6A63),
            accent: Color(hex: 0xE0902E), losslessBadge: nil,
            playState: Color(hex: 0xE0902E), vuPeak: nil,
            labelPaper: nil, labelInk: nil),
        type: Typography(
            hero:    { .system(size: $0, weight: .bold,     design: .serif) },
            title:   { .system(size: $0, weight: .semibold, design: .serif) },
            section: { .system(size: $0, weight: .semibold) },
            body:    { .system(size: $0) },
            numeric: { .system(size: $0, design: .monospaced) }),
        textureOpacity: 0,
        copy: IdleCopy(
            nowPlaying: "Nothing playing — press / to search.",
            dashboardIdle: "Idle",
            dashHeaders: ("Now Playing", "Signal", "Up Next")),
        caps: [.artWash, .equalizerRows],
        transport: .standard,
        accentMode: .artDriven(fallback: Color(hex: 0xE0902E)),
        washStyle: .linear,
        darkOnly: false)

    static let shoebox = Theme(
        id: .shoebox,
        palette: Palette(
            base: Color(hex: 0x16110D), raised: Color(hex: 0x1E1712), hairline: Color(hex: 0x2C2118),
            textPrimary: Color(hex: 0xEDE3CF), textSecondary: Color(hex: 0xA8987E), textIdle: Color(hex: 0x6E6151),
            accent: Color(hex: 0xE0922F), losslessBadge: nil,
            playState: Color(hex: 0xB5561F), vuPeak: nil,
            labelPaper: nil, labelInk: nil),
        type: Typography(
            hero:    { .custom("AvenirNextCondensed-Heavy", size: $0) },
            title:   { .system(size: $0, weight: .medium, design: .serif) },
            section: { .custom("AvenirNextCondensed-Bold", size: $0) },
            body:    { .system(size: $0) },
            numeric: { .system(size: $0, design: .monospaced) }),
        textureOpacity: 0.035,
        copy: IdleCopy(
            nowPlaying: "B-side's empty. Press / to find a show.",
            dashboardIdle: "Nothing cued up.",
            dashHeaders: ("Now Playing", "Quality", "Up Next")),
        caps: [.condensedHeaders, .indexLetterTab, .artWash],
        transport: .jCard,
        accentMode: .staticAccent,
        washStyle: .warmLow,
        darkOnly: false)

    static let tapeDeck = Theme(
        id: .tapeDeck,
        palette: Palette(
            base: Color(hex: 0x0B0A08), raised: Color(hex: 0x1C1A17), hairline: Color(hex: 0x14120F),
            textPrimary: Color(hex: 0xEFE7D8), textSecondary: Color(hex: 0xB5701A), textIdle: Color(hex: 0x7A5414),
            accent: Color(hex: 0xFFA62B), losslessBadge: nil,
            playState: Color(hex: 0x36C9C0), vuPeak: Color(hex: 0xFF4D2E),
            labelPaper: nil, labelInk: nil),
        type: Typography(
            hero:    { .system(size: $0, weight: .semibold, design: .serif) },
            title:   { .system(size: $0, weight: .medium,   design: .serif) },
            section: { .system(size: $0, weight: .heavy,    design: .monospaced) },
            body:    { .system(size: $0) },
            numeric: { .system(size: $0, weight: .heavy,    design: .monospaced) }),
        textureOpacity: 0,
        copy: IdleCopy(
            nowPlaying: "No signal. Press / to tune in.",
            dashboardIdle: "NO SIGNAL",
            dashHeaders: ("TUNED TO", "SIGNAL", "REELS")),
        caps: [.vuMeter, .artWash],
        transport: .faceplate,
        accentMode: .staticAccent,
        washStyle: .bloom18,
        darkOnly: true)
}

extension Theme {
    /// Monochrome pocket-player homage: graphite surfaces, white glyphs, soft
    /// raised circles, zero color — the album art is the only pigment on
    /// screen. iOS gets the circular-pad full-screen player; the Mac bar keeps
    /// its standard shape in these tokens.
    static let clickWheel = Theme(
        id: .clickWheel,
        palette: Palette(
            base: Color(hex: 0x0E0E0F), raised: Color(hex: 0x1C1C1E), hairline: Color(hex: 0x2A2A2C),
            textPrimary: Color(hex: 0xF5F5F5), textSecondary: Color(hex: 0x9A9A9E), textIdle: Color(hex: 0x5C5C60),
            accent: Color(hex: 0xE9E9EB), losslessBadge: nil,
            playState: Color(hex: 0xF5F5F5), vuPeak: nil,
            labelPaper: nil, labelInk: nil),
        type: Typography(
            hero:    { .system(size: $0, weight: .bold) },
            title:   { .system(size: $0, weight: .semibold) },
            section: { .system(size: $0, weight: .semibold) },
            body:    { .system(size: $0) },
            numeric: { .system(size: $0, design: .monospaced) }),
        textureOpacity: 0,
        copy: IdleCopy(
            nowPlaying: "Nothing playing. Give the wheel a spin.",
            dashboardIdle: "Idle",
            dashHeaders: ("Now Playing", "Quality", "Up Next")),
        caps: [],
        transport: .clickWheel,
        accentMode: .staticAccent,
        washStyle: .none,
        darkOnly: true)
}

extension Theme {
    /// Yeti, an unofficial player's own look: night-blue shelves, snow type,
    /// sale-yellow stickers and one foil accent kept for things that move with
    /// time. Heavy rounded type, no texture, no art wash, dark only. Its
    /// bespoke visuals are gated on the caps below, never on `id`.
    static let yeti = Theme(
        id: .yeti,
        palette: Palette(
            base: Color(hex: 0x0F1424), raised: Color(hex: 0x18203A),
            hairline: Color(hex: 0x2E3A5C),
            textPrimary: Color(hex: 0xE9EEF7),
            textSecondary: Color(hex: 0x9FABCE),
            textIdle: Color(hex: 0x8590B0),
            accent: Color(hex: 0xFF8FC4),
            losslessBadge: Color(hex: 0xF2E27A),
            playState: Color(hex: 0xF2E27A), vuPeak: nil,
            labelPaper: Color(hex: 0x1B2443),  // backing card
            labelInk: Color(hex: 0x0F1424)),   // sticker ink
        type: Typography(
            hero:    { .system(size: $0, weight: .heavy, design: .rounded) },
            title:   { .system(size: $0, weight: .heavy, design: .rounded) },
            section: { .system(size: $0, weight: .heavy, design: .rounded) },
            body:    { .system(size: $0, design: .rounded) },
            numeric: { .system(size: $0, design: .rounded).monospacedDigit() }),
        textureOpacity: 0,
        copy: IdleCopy(
            nowPlaying: "It's on its way",
            dashboardIdle: "It's on its way",
            dashHeaders: ("Here it comes", "Says so on the box", "Coming up next"),
            downloadsEmptyTitle: "Nothing boxed up yet",
            searchNoResults: { "Nothing on the shelf for \u{201C}\($0)\u{201D}" },
            videosResume: "Pick up where you left off",
            videosLive: "Live and coming up",
            videosExclusives: "Just streamed",
            liveEdgeDisabled: "At the live edge",
            homeLede: "Pick up where you left off, or dig through the crate.",
            ledgerTitle: "The nice list"),
        caps: [.equalizerRows, .blisterPack, .stickers, .foilSweep, .plainVoice],
        transport: .standard,
        accentMode: .staticAccent,
        washStyle: .none,
        darkOnly: true)
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
