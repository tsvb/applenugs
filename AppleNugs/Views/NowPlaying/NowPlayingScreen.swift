import SwiftUI

/// Scene id for the macOS Now Playing window (see AppleNugsApp). Shared so the
/// window scene, the Window-menu command, and the transport expand buttons all
/// reference one constant.
enum NowPlayingWindow {
    static let id = "now-playing"
}

/// Full-screen now-playing, presented from a tap on the compact transport bar.
/// Themes with the faceplate transport (The Receiver) get the TouchFaceplate;
/// everything else gets the standard layout below, tinted by theme tokens.
struct NowPlayingScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            switch theme.transport {
            case .faceplate:
                TouchFaceplate()
            case .clickWheel:
                ClickWheelScreen()
            case .standard, .tapeLabel, .jCard:
                StandardNowPlayingScreen()
            }
        }
    }
}

// MARK: - Standard layout

struct StandardNowPlayingScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var dashboardShown = false
    @State private var confirmClear = false

    private var player: PlayerService { app.player }

    var body: some View {
        VStack(spacing: 22) {
            header

            Spacer(minLength: 0)

            artwork
                .padding(.horizontal, 36)

            // Tape Room: the label card's "tape counter" under-rule rides
            // directly beneath the reel (in addition to the scrubber below).
            if theme.transport == .tapeLabel {
                tapeCounter
                    .padding(.horizontal, 72)
            }

            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    if theme.caps.contains(.equalizerRows) {
                        EqualizerBars(isPlaying: player.isPlaying)
                    }
                    Text(player.current?.title ?? "Nothing playing")
                        .font(theme.type.hero(22))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                if let track = player.current {
                    // Shoebox liner-note treatment: typed-out tracked caps,
                    // as on its J-card spine.
                    if theme.transport == .jCard {
                        Text(NowPlayingMeta.line(track).uppercased())
                            .font(theme.type.numeric(11))
                            .tracking(0.9)
                            .foregroundStyle(theme.palette.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(NowPlayingMeta.line(track))
                            .font(theme.type.title(14))
                            .foregroundStyle(theme.palette.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            seekBlock
                .padding(.horizontal, 24)

            transportRow

            volumeRow
                .padding(.horizontal, 32)

            bottomRow
                .padding(.horizontal, 28)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            theme.palette.base
                .overlay { ArtWashBackground(style: theme.washStyle, color: artColor ?? .clear) }
                .overlay {
                    if theme.textureOpacity > 0 {
                        PaperGrain().opacity(theme.textureOpacity).allowsHitTesting(false)
                    }
                }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $dashboardShown) {
            DashboardPanel()
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
                .presentationBackground(theme.palette.base)
        }
        .confirmationDialog("Clear the queue?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Queue", role: .destructive) { app.player.clear() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close now playing")

            Spacer()

            // Queue position while loaded; the theme's flavor copy only for
            // the empty state (its keyboard hints don't apply on iOS anyway).
            Text(player.current != nil
                 ? "TRACK \(player.index + 1) OF \(player.queue.count)"
                 : theme.copy.nowPlaying.uppercased())
                .font(theme.type.numeric(11))
                .tracking(1.6)
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)

            Spacer()

            star
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
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
                    size: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.palette.textPrimary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: (artColor ?? theme.palette.accent).opacity(0.35), radius: 28, y: 10)
    }

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
            .tint(theme.effectiveAccent(art: artColor))
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

    private var tapeCounter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.palette.hairline)
                Capsule().fill(theme.palette.accent)
                    .frame(width: geo.size.width * counterProgress)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var counterProgress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return min(max(CGFloat(player.currentTime / player.duration), 0), 1)
    }

    private var sliderMax: Double { max(player.duration, 1) }

    private var remainingText: String {
        guard player.duration > 0 else { return "--:--" }
        let position = scrubbing ? scrubValue : player.currentTime
        return "-" + TransportBar.format(seconds: max(player.duration - position, 0))
    }

    private var transportRow: some View {
        HStack(spacing: 26) {
            HapticButton(.transportStep) { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 26))
            }
            .disabled(!player.hasPrevious)
            .accessibilityLabel("Previous track")

            HapticButton(.transportStep) { player.seek(by: -15) } label: {
                Image(systemName: "gobackward.15").font(.system(size: 20))
            }
            .disabled(player.current == nil)
            .accessibilityLabel("Back 15 seconds")

            HapticButton(.transportToggle) { player.togglePlayPause() } label: {
                if player.isBuffering {
                    ProgressView()
                        .frame(width: 68, height: 68)
                } else {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 68))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .disabled(player.current == nil)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            HapticButton(.transportStep) { player.seek(by: 30) } label: {
                Image(systemName: "goforward.30").font(.system(size: 20))
            }
            .disabled(player.current == nil)
            .accessibilityLabel("Forward 30 seconds")

            HapticButton(.transportStep) { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 26))
            }
            .disabled(!player.hasNext)
            .accessibilityLabel("Next track")
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.textPrimary)
    }

    private var volumeRow: some View {
        @Bindable var player = app.player
        return HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.system(size: 12))
            Slider(value: $player.volume, in: 0...1)
                .tint(theme.effectiveAccent(art: artColor))
                .accessibilityLabel("Volume")
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 12))
        }
        .foregroundStyle(theme.palette.textSecondary)
    }

    private var bottomRow: some View {
        HStack {
            if let pick = player.nowPick {
                Text(pick.format.badge)
                    .font(theme.type.numeric(10).weight(.semibold))
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.palette.hairline, in: RoundedRectangle(cornerRadius: 4))
            }

            Spacer()

            RoutePicker(tint: theme.effectiveAccent(art: artColor))
                .frame(width: 44, height: 44)

            Button {
                dashboardShown = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Queue and stream details")

            if !player.queue.isEmpty {
                Menu {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Clear Queue", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More queue actions")
            }
        }
    }

    private var star: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 17))
                .foregroundStyle(saved ? theme.palette.accent : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .accessibilityLabel("Save show to Favorites")
        .accessibilityAddTraits(saved ? .isSelected : [])
    }
}
