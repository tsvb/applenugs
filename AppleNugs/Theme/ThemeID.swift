import SwiftUI

/// Stable, persisted identity for each theme.
enum ThemeID: String, CaseIterable, Identifiable, Codable {
    case tapeRoom
    case soundboard
    case shoebox
    case tapeDeck

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tapeRoom:   return "Tape Room"
        case .soundboard: return "Soundboard"
        case .shoebox:    return "Shoebox"
        case .tapeDeck:   return "The Receiver"
        }
    }

    /// Accent swatch for the picker (the static accent; art-driven themes show
    /// their fallback).
    var swatch: Color { Theme.make(self).palette.accent }
}
