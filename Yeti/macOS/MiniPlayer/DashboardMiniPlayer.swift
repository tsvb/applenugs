import SwiftUI

/// The Dashboard inspector's now-playing surface: the idle line, or the
/// compact player (`MiniPlayerStandard`) once something is loaded.
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
            MiniPlayerStandard()
        }
    }
}
