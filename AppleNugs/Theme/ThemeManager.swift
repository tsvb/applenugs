import Observation
import SwiftUI

/// Yeti is the only design: the manager always yields `Theme.yeti`. Nothing is
/// read from or written to UserDefaults any more — the old `selectedTheme` key
/// is simply never consulted again (Tim is the only user; no migration). The
/// class itself goes when the five old themes are deleted.
@MainActor
@Observable
final class ThemeManager {
    let theme: Theme = .yeti
}
