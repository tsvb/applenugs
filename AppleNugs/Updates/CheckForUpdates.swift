import Combine
import Sparkle

/// Mirrors Sparkle's `canCheckForUpdates` so the menu item enables/disables
/// correctly. Main-actor-confined — Sparkle's updater is only touched on the
/// main actor, which keeps this clean under SWIFT_STRICT_CONCURRENCY=complete.
@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }
}
