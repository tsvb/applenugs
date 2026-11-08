import SwiftUI

/// Stable, persisted identity for each theme.
enum ThemeID: String, CaseIterable, Identifiable, Codable {
    case tapeRoom
    case soundboard
    case shoebox
    case tapeDeck
    case clickWheel
    case yeti

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tapeRoom:   return "Tape Room"
        case .soundboard: return "Soundboard"
        case .shoebox:    return "Shoebox"
        case .tapeDeck:   return "The Receiver"
        case .clickWheel: return "Click Wheel"
        case .yeti:       return "Yeti"
        }
    }

    /// Accent swatch for the picker (the theme's accent).
    var swatch: Color { Theme.make(self).palette.accent }
}
