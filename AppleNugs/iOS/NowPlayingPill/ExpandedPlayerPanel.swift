import SwiftUI

/// The pill chevron's destination: everything the 48pt capsule cannot hold —
/// real scrub numerals with a thumb, the favourite star, AirPlay, the format
/// badge, and a way into the queue. (A drag-up gesture was tried first, but
/// it fought the tab bar's own scroll-to-minimize handling and was replaced
/// by the chevron tap.)
///
/// A tap on the pill still goes straight to `NowPlayingScreen`; this is the
/// in-between surface for scrubbing without losing the list you were browsing.
struct ExpandedPlayerPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var dashboardShown = false

    private var player: PlayerService { app.player }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ArtChip(image: player.nowPlayingImage,
                        fallbackText: player.current?.artist ?? "?",
                        size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.current?.title ?? "Nothing playing")
                        .font(theme.type.body(15).weight(.semibold))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(1)
                    if let show = player.current?.show ?? player.current?.artist {
                        Text(show)
                            .font(theme.type.body(12))
                            .foregroundStyle(theme.palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                favoriteStar
            }

            PanelScrubRow()

            PillTransportControls(slot: .expanded)
                .font(.title2)

            Divider().overlay(theme.palette.hairline)

            HStack {
                RoutePicker(tint: theme.palette.accent)
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("AirPlay")
                Spacer()
                if let pick = player.nowPick {
                    Text(pick.format.badge)
                        .font(theme.type.numeric(10).weight(.semibold))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                Spacer()
                Button("Queue") { dashboardShown = true }
                    .font(theme.type.body(12))
                    .foregroundStyle(theme.palette.accent)
                    .accessibilityHint("Opens the queue and stream details")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $dashboardShown) {
            DashboardPanel()
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
                .presentationBackground(theme.palette.base)
        }
    }

    private var favoriteStar: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .foregroundStyle(saved ? theme.palette.accent : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .accessibilityLabel("Save show to Favorites")
        .accessibilityAddTraits(saved ? .isSelected : [])
    }
}

/// **A leaf view** — the second and last place in this feature allowed to read
/// `currentTime`, for the same reason as `PillSeekEdge`.
private struct PanelScrubRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var player: PlayerService { app.player }

    var body: some View {
        HStack(spacing: 8) {
            Text(TransportBar.format(seconds: position))
                .font(theme.type.numeric(10))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(width: 38, alignment: .leading)

            Slider(
                value: Binding(
                    // Duration-less streams would pin the thumb hard right
                    // (sliderMax falls back to 1), reading as "finished".
                    get: { scrubbing ? scrubValue
                                     : (player.duration > 0 ? min(player.currentTime, sliderMax) : 0) },
                    set: { scrubValue = $0 }),
                in: 0...sliderMax
            ) { editing in
                if editing {
                    scrubValue = player.currentTime
                } else {
                    player.seek(to: scrubValue)
                }
                scrubbing = editing
            }
            .tint(theme.palette.accent)
            .disabled(player.duration <= 0)
            .accessibilityLabel("Playback position")
            .accessibilityValue(TransportBar.format(seconds: position))

            Text(remainingText)
                .font(theme.type.numeric(10))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private var position: Double { scrubbing ? scrubValue : player.currentTime }
    private var sliderMax: Double { max(player.duration, 1) }

    private var remainingText: String {
        guard player.duration > 0 else { return "--:--" }
        return "-" + TransportBar.format(seconds: max(player.duration - position, 0))
    }
}
