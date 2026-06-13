import Observation
import SwiftUI

/// Owns the selected theme and persists it to UserDefaults — the same idiom
/// PlayerService uses for volume. The derived `theme` value is what views read.
@MainActor
@Observable
final class ThemeManager {
    private static let key = "selectedTheme"

    var selected: ThemeID {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: Self.key)
            theme = Theme.make(selected)
        }
    }

    private(set) var theme: Theme

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        let id = stored.flatMap(ThemeID.init(rawValue:)) ?? .tapeRoom
        selected = id
        theme = Theme.make(id)
    }
}
