import SwiftUI

/// The Dashboard inspector's now-playing surface: a compact player carrying the
/// active theme's personality.
///
/// Dispatches on `theme.transport` exactly as `TransportBar`'s now-playing block
/// and `NowPlayingScreen` do — host views are never forked per theme.
struct DashboardMiniPlayer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var player: PlayerService { app.player }

    var body: some View {
        if player.current == nil {
            Text(theme.copy.dashboardIdle)
                .font(.caption)
                .foregroundStyle(theme.palette.textIdle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            variant
        }
    }

    @ViewBuilder
    private var variant: some View {
        switch theme.transport {
        case .standard, .jCard: MiniPlayerStandard()
        case .tapeLabel:        MiniPlayerStandard()   // Task 4 replaces this
        case .faceplate:        MiniPlayerStandard()   // Task 5 replaces this
        case .clickWheel:       MiniPlayerStandard()   // Task 6 replaces this
        }
    }
}
