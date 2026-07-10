import SwiftUI

/// Click Wheel's now-playing: a monochrome pocket-player homage. Large art
/// card, a compact track card, a thin white progress rule, and a circular
/// control pad — heart up top, prev/next on the ring, mute below, play in the
/// center — ringed by four satellite buttons (queue, AirPlay, ±seek).
struct ClickWheelScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var dashboardShown = false
    /// Volume to restore when the mute button toggles back on.
    @State private var unmutedVolume: Float = 1

    private var player: PlayerService { app.player }

    var body: some View {
        VStack(spacing: 18) {
            header

            Spacer(minLength: 0)

            artwork
                .padding(.horizontal, 44)

            trackCard
                .padding(.horizontal, 24)

            seekBlock
                .padding(.horizontal, 28)

            Spacer(minLength: 0)

            controlPad
                .padding(.bottom, 8)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { theme.palette.base.ignoresSafeArea() }
        .sheet(isPresented: $dashboardShown) {
            DashboardPanel()
                .presentationDetents([.medium, .large])
                .presentationBackground(theme.palette.base)
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(theme.palette.raised))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close now playing")

            Spacer()

            Text("Now Playing")
                .font(theme.type.title(15))
                .foregroundStyle(theme.palette.textPrimary)

            Spacer()

            // Balance the chevron so the title stays centered.
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
    }

    private var artwork: some View {
        ZStack {
            if let image = player.nowPlayingImage {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                MonogramTile(
                    text: player.current?.artist ?? player.current?.title ?? "?",
                    size: 260)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }

    /// The compact "artist / bold title" card from the reference, with the
    /// favorites star standing in for its Follow pill.
    private var trackCard: some View {
        HStack(spacing: 10) {
            ArtChip(image: player.nowPlayingImage,
                    fallbackText: player.current?.artist ?? "?",
                    size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.artist ?? "—")
                    .font(theme.type.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
                Text(player.current?.title ?? "Nothing playing")
                    .font(theme.type.title(15))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            savePill
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.palette.raised)
        }
    }

    private var savePill: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Text(saved ? "Saved" : "Save")
                .font(theme.type.body(12).weight(.semibold))
                .foregroundStyle(saved ? theme.palette.base : theme.palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(saved ? theme.palette.textPrimary : theme.palette.hairline)
                }
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .accessibilityLabel("Save show to Favorites")
        .accessibilityAddTraits(saved ? .isSelected : [])
    }

    // --- thin progress rule + times -----------------------------------------

    private var seekBlock: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : min(player.currentTime, sliderMax) },
                    set: { scrubValue = $0 }),
                in: 0...sliderMax
            ) { editing in
                if editing { scrubValue = player.currentTime } else { player.seek(to: scrubValue) }
                scrubbing = editing
            }
            .controlSize(.mini)
            .tint(theme.palette.textPrimary)
            .disabled(player.duration <= 0)
            .accessibilityLabel("Playback position")
            .accessibilityValue(TransportBar.format(seconds: scrubbing ? scrubValue : player.currentTime))

            HStack {
                Text(TransportBar.format(seconds: scrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text(remainingText)
            }
            .font(theme.type.numeric(11))
            .foregroundStyle(theme.palette.textSecondary)
        }
    }

    private var sliderMax: Double { max(player.duration, 1) }

    private var remainingText: String {
        guard player.duration > 0 else { return "--:--" }
        let position = scrubbing ? scrubValue : player.currentTime
        return "-" + TransportBar.format(seconds: max(player.duration - position, 0))
    }

    // --- the wheel ------------------------------------------------------------

    private var controlPad: some View {
        ZStack {
            // Satellites sit on the diagonals outside the wheel.
            VStack {
                HStack {
                    satellite("ellipsis", label: "Queue and stream details") { dashboardShown = true }
                    Spacer()
                    RoutePicker(tint: theme.palette.textPrimary)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(theme.palette.raised))
                }
                Spacer()
                HStack {
                    satellite("gobackward.15", label: "Back 15 seconds") { player.seek(by: -15) }
                    Spacer()
                    satellite("goforward.30", label: "Forward 30 seconds") { player.seek(by: 30) }
                }
            }
            .frame(width: 330, height: 260)

            wheel
        }
        .frame(maxWidth: .infinity)
    }

    /// A pad outside the ring. Seek and queue live here, one wheel-width from
    /// the prev/next glyphs that tick — so they tick the same way.
    private func satellite(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        HapticButton(.transportStep, action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.palette.textPrimary)
                .frame(width: 52, height: 52)
                .background(Circle().fill(theme.palette.raised))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var wheel: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return ZStack {
            Circle()
                .fill(theme.palette.raised)
                .overlay {
                    Circle().strokeBorder(theme.palette.hairline, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)

            // Ring glyphs (N/S/E/W).
            VStack {
                wheelButton(saved ? "heart.fill" : "heart",
                            label: "Save show to Favorites") {
                    NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
                }
                .disabled(player.current?.showId == nil)
                Spacer()
                wheelButton(player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            label: player.volume == 0 ? "Unmute" : "Mute") {
                    toggleMute()
                }
            }
            .padding(.vertical, 20)

            HStack {
                wheelButton("backward.fill", label: "Previous track") { player.previous() }
                    .disabled(!player.hasPrevious)
                Spacer()
                wheelButton("forward.fill", label: "Next track") { player.next() }
                    .disabled(!player.hasNext)
            }
            .padding(.horizontal, 20)

            // Center play/pause puck.
            HapticButton(.transportToggle) {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(theme.palette.base)
                    if player.isBuffering {
                        ProgressView()
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(theme.palette.textPrimary)
                    }
                }
                .frame(width: 88, height: 88)
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        }
        .frame(width: 240, height: 240)
    }

    /// A glyph on the ring. Ticks like the original scroll wheel.
    private func wheelButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        HapticButton(.transportStep, action: action) {
            Image(systemName: system)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.palette.textPrimary)
                .frame(width: 52, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func toggleMute() {
        if player.volume == 0 {
            player.volume = unmutedVolume > 0 ? unmutedVolume : 1
        } else {
            unmutedVolume = player.volume
            player.volume = 0
        }
    }
}
