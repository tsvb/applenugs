import SwiftUI

// MARK: - Variation axes

/// Which bespoke now-playing treatment a theme uses in the transport bar.
enum TransportSignature {
    case standard      // the original text block, token-styled
    case tapeLabel     // Tape Room: art chip + amber under-rule progress
    case jCard         // Shoebox: cassette J-card strip
    case faceplate     // The Receiver: full brushed-metal VU faceplate (deferred)
}

/// Whether the accent is a fixed color or derived from the current cover art.
enum AccentMode {
    case staticAccent
    case artDriven(fallback: Color)
}

/// How (if at all) the extracted album-art color washes into the chrome.
enum WashStyle {
    case none
    case linear        // Soundboard: gradient behind transport + now-playing
    case warmLow       // Shoebox: faint warm wash
    case bloom18       // The Receiver: 18% bloom behind the inspector art only
}

/// Opt-in bespoke behaviors, kept off the host views so nothing forks.
struct Capabilities: OptionSet {
    let rawValue: Int
    static let artWash          = Capabilities(rawValue: 1 << 0)
    static let equalizerRows    = Capabilities(rawValue: 1 << 1)
    static let vuMeter          = Capabilities(rawValue: 1 << 2)
    static let condensedHeaders = Capabilities(rawValue: 1 << 3)
    static let indexLetterTab   = Capabilities(rawValue: 1 << 4)
}

// MARK: - Token groups

/// Semantic color roles. Views ask for `textSecondary`, never "taupe".
struct Palette {
    let base, raised, hairline: Color
    let textPrimary, textSecondary, textIdle: Color
    let accent: Color            // static fallback; art may override at runtime
    let losslessBadge: Color?    // distinct lossless tint (Tape Room teal), else nil
    let playState: Color         // active/playing emphasis
    let vuPeak: Color?           // VU peak tick (The Receiver only)
}

/// Fonts as size-taking closures so a point size is a call, not six stored fonts.
struct Typography {
    let hero, title, section: (CGFloat) -> Font
    let body, numeric: (CGFloat) -> Font
}

/// Per-theme copy so idle/empty states and section headers carry personality.
struct IdleCopy {
    let nowPlaying: String
    let dashboardIdle: String
    let dashHeaders: (now: String, quality: String, upNext: String)
}

// MARK: - Theme

/// A complete look, assembled from tokens. Value type read from the environment,
/// so switching republishes one value and re-renders only the affected subtrees.
struct Theme: Equatable {
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
        }
    }
}

// MARK: - The four themes (the only place literal hex lives)

extension Theme {
    static let tapeRoom = Theme(
        id: .tapeRoom,
        palette: Palette(
            base: Color(hex: 0x14110E), raised: Color(hex: 0x1B1714), hairline: Color(hex: 0x2E2823),
            textPrimary: Color(hex: 0xF2EADF), textSecondary: Color(hex: 0xA89B8B), textIdle: Color(hex: 0x6E6357),
            accent: Color(hex: 0xE8A13A), losslessBadge: Color(hex: 0x5FB6A6),
            playState: Color(hex: 0xE8A13A), vuPeak: nil),
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
            playState: Color(hex: 0xE0902E), vuPeak: nil),
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
            playState: Color(hex: 0xB5561F), vuPeak: nil),
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
            playState: Color(hex: 0x36C9C0), vuPeak: Color(hex: 0xFF4D2E)),
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
