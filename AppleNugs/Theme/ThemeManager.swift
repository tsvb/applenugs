import Observation
import SwiftUI

/// Owns the selected theme and persists it to UserDefaults — the same idiom
/// PlayerService uses for volume. The derived `theme` value is what views read.
///
/// Under `-UITEST` (DEBUG only) the choice is never written, so a seeded launch
/// that opens in another theme (`-UITestTheme`, or a pick in the picker during
/// the run) can't clobber the user's persisted preference — the same rule as
/// `PlaybackStateStore` and `ListeningStatsStore`.
@MainActor
@Observable
final class ThemeManager {
    private static let key = "selectedTheme"

    var selected: ThemeID {
        didSet {
            theme = Theme.make(selected)
            #if DEBUG
            // `AppModel.isUITestRun` only exists in DEBUG, hence the `#if`.
            guard !AppModel.isUITestRun else { return }
            #endif
            UserDefaults.standard.set(selected.rawValue, forKey: Self.key)
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
