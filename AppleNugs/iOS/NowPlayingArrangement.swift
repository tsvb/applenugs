import SwiftUI

/// The full-screen player's container: on a canvas wide enough to split
/// (iPhone Duo's inner display, unfolded flat ≈ 951×669pt landscape), the
/// player sits beside its own queue — player primary, `DashboardPanel`
/// secondary, with the panel's "Now" section dropped because the player IS
/// the now-playing view. Where `.split.axes(.horizontal)` can't split — iPhone,
/// the Duo's compact outer display, the inner display held upright — the SDK
/// shows only the primary, and the player keeps its queue button and sheet.
///
/// Measured on the Duo simulator (iOS 27.1, unfolded flat): the split is an
/// even 50/50 of the safe area (two 433.5×635pt columns), and each column
/// reports a COMPACT horizontal size class — so the players' regular-width
/// readable-width cap does not apply inside the split.
///
/// `queueBeside` is derived from the secondary's own appearance because the
/// SDK exposes no "is the secondary visible" signal for `.split` (only the
/// `.overlay` style has `overlayArrangementZIndex`). That assumes the
/// arrangement REMOVES the secondary when it can't split rather than keeping
/// it at zero size. It flips on layout change, never per tick, and this view
/// reads no `player.currentTime`.
///
/// `ArrangementView` is iOS 27.1+; the floor stays 26.1, so older systems take
/// the bare player.
struct NowPlayingArrangement: View {
    @State private var queueBeside = false

    var body: some View {
        if #available(iOS 27.1, *) {
            ArrangementView {
                NowPlayingScreen()
            } secondary: {
                DashboardPanel(showsNowPlaying: false)
                    .onAppear { queueBeside = true }
                    .onDisappear { queueBeside = false }
            }
            .arrangementViewStyle(.split.axes(.horizontal))
            .environment(\.nowPlayingQueueBeside, queueBeside)
        } else {
            NowPlayingScreen()
        }
    }
}
