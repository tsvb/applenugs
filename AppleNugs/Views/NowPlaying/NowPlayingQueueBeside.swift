import SwiftUI

extension EnvironmentValues {
    /// True while the up-next queue is already on screen BESIDE the full-screen
    /// player — iPhone Duo's inner display, where `NowPlayingArrangement` puts
    /// a `DashboardPanel` in the secondary column. The players then swap their
    /// queue button for a same-size clear placeholder (constant shape: the
    /// click wheel's satellites and the bottom rows are fixed geometry), since
    /// a button that opens the queue as a sheet over the queue is just noise.
    ///
    /// Declared in shared code so macOS and every iPhone see the `false`
    /// default and are untouched; only `NowPlayingArrangement` (iOS-only) sets it.
    @Entry var nowPlayingQueueBeside: Bool = false
}
