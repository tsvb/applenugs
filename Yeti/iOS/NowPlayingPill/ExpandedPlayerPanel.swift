import SwiftUI

/// The pill chevron's destination: everything the 48pt capsule cannot hold —
/// real scrub numerals with a thumb, the favorite star, AirPlay, the format
/// badge (the price sticker), and a way into the queue. (A drag-up gesture was tried first, but
/// it fought the tab bar's own scroll-to-minimize handling and was replaced
/// by the chevron tap.)
///
/// A tap on the pill still goes straight to `NowPlayingScreen`; this is the
/// in-between surface for scrubbing without losing the list you were browsing.
struct ExpandedPlayerPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(UIState.self) private var ui

    @State private var dashboardShown = false

    private var player: PlayerService { app.player }

    var body: some View {
        // The 46pt play sticker in the transport row is taller than the glyph
        // it replaced, so the stack keeps tight 6pt gaps to hold the whole
        // panel inside the fixed 250pt detent. No price sticker here (Tim,
        // 2026-11-07: next to the play sticker its weight competed with it):
        // the quality is quiet text under the venue instead.
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ArtChip(image: player.nowPlayingImage,
                        fallbackText: player.current?.artist ?? "?",
                        size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.current?.title ?? "Nothing playing")
                        .font(theme.type.title(17))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(1)
                    NowPlayingMetaText(track: player.current, mode: .firstAvailable)
                        .font(theme.type.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                    qualityLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                favoriteStar
            }

            PanelScrubRow()

            PillTransportControls(controls: PillLayout.controls(for: .expanded),
                                  playControl: .sticker(.s46))
                .font(.title2)

            Divider().overlay(theme.palette.hairline)

            HStack {
                // AirPlay isn't time moving: slush, not foil.
                RoutePicker(tint: theme.palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("AirPlay")
                Spacer()
                queueButton
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .dismissesOnNavigation($dashboardShown, ui: ui)
        .sheet(isPresented: $dashboardShown) {
            DashboardPanel()
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
                .presentationBackground(theme.palette.base)
        }
    }

    /// "Lossless 16/44" in quiet slush text, from the same policy as the price
    /// sticker: presence follows `player.current`, never `nowPick` (which is
    /// nil'd on every track change), so it reads "Lossless" until the stream
    /// is known instead of blinking. Always one line tall — a blank line when
    /// hidden (a stream known to be lossy) — so the panel never reflows.
    private var qualityLine: some View {
        let label = PriceStickerLabel(player: player)
        let text = label.map { [$0.title, $0.spec].compactMap { $0 }.joined(separator: " ") } ?? " "
        return Text(text)
            .font(theme.type.numeric(11))
            .foregroundStyle(theme.palette.textSecondary)
            .lineLimit(1)
            .accessibilityLabel(label?.accessibilityLabel ?? "")
            .accessibilityHidden(label == nil)
    }

    /// A frost-outlined button (never filled or tinted with the accent).
    private var queueButton: some View {
        Button { dashboardShown = true } label: {
            Label("Queue", systemImage: "list.bullet")
        }
        .buttonStyle(.yetiSecondary)
        .controlSize(.small)
        .accessibilityHint("Opens the queue and stream details")
    }

    private var favoriteStar: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                // A saved show isn't time moving: the filled star is snow,
                // not an accent fill.
                .foregroundStyle(saved ? theme.palette.textPrimary : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .accessibilityLabel("Save show to Favorites")
        .accessibilityAddTraits(saved ? .isSelected : [])
    }
}

/// **A leaf view** — the second and last place in this feature allowed to read
/// `currentTime`. The playback clock ticks ~4Hz; isolating the read here
/// keeps that churn from re-diffing the panel's body around it.
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
