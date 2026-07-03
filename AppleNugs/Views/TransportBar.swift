import SwiftUI

/// Bottom transport bar: now-playing block, prev/play/next, seek, volume,
/// and the current format badge. Mirrors the web Transport component.
struct TransportBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    /// While the user drags, hold the thumb at the dragged value so the
    /// playback ticks don't yank it back.
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var player: PlayerService { app.player }

    var body: some View {
        if theme.transport == .faceplate {
            #if os(macOS)
            FaceplateTransport()
            #else
            standardBar   // placeholder until Phase C's TouchFaceplate
            #endif
        } else {
            standardBar
        }
    }

    private var standardBar: some View {
        #if os(macOS)
        HStack(spacing: 16) {
            nowPlayingBlock
                .frame(width: 230, alignment: .leading)

            controls

            seekBlock

            volumeBlock

            nowPlayingStar

            if let pick = player.nowPick {
                Text(pick.format.badge)
                    .font(theme.type.numeric(10).weight(.semibold))
                    .foregroundStyle(badgeColor(for: pick.format))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.palette.hairline, in: RoundedRectangle(cornerRadius: 4))
                    .help(pick.format.qualityLabel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background { barBackground }
        #else
        compactBar
        #endif
    }

    #if os(iOS)
    /// Compact bar for iPhone width: the theme's signature now-playing block
    /// (tape label / J-card / standard) + play/next, with a hairline progress
    /// track on top. Tape Room's label card carries its own under-rule
    /// counter, so the hairline is skipped there. Tap opens the full-screen
    /// now-playing (wired by the shell).
    private var compactBar: some View {
        VStack(spacing: 0) {
            if theme.transport != .tapeLabel {
                MiniProgressStrip()
            }

            HStack(spacing: 12) {
                compactNowPlayingBlock
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    player.togglePlayPause()
                } label: {
                    if player.isBuffering {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 28)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.palette.textPrimary)
                .disabled(player.current == nil)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.palette.textPrimary)
                .disabled(!player.hasNext)
                .accessibilityLabel("Next track")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background { barBackground }
    }

    /// A leaf view: the 4Hz currentTime dependency registers here, so the
    /// rest of the compact bar (signature block, transport buttons) only
    /// re-evaluates on real state changes.
    private struct MiniProgressStrip: View {
        @Environment(AppModel.self) private var app
        @Environment(\.theme) private var theme

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    theme.palette.hairline
                    theme.palette.accent
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 2)
            .accessibilityHidden(true)
        }

        private var fraction: Double {
            let player = app.player
            guard player.duration > 0 else { return 0 }
            return min(max(player.currentTime / player.duration, 0), 1)
        }
    }

    /// The same per-theme signature switch the Mac bar uses, with an art chip
    /// added for the chip-less standard block so the bar still reads at 36pt.
    @ViewBuilder
    private var compactNowPlayingBlock: some View {
        switch theme.transport {
        case .tapeLabel:
            TapeLabelCard()
        case .jCard:
            JCardStrip()
        case .standard, .faceplate, .clickWheel:
            HStack(spacing: 10) {
                ArtChip(image: player.nowPlayingImage,
                        fallbackText: player.current?.artist ?? player.current?.title ?? "?",
                        size: 36)
                StandardNowPlaying()
            }
        }
    }
    #endif

    private var barBackground: some View {
        theme.palette.raised
            .overlay { ArtWashBackground(style: theme.washStyle, color: artColor ?? .clear) }
            .overlay {
                if theme.textureOpacity > 0 {
                    PaperGrain().opacity(theme.textureOpacity).allowsHitTesting(false)
                }
            }
    }

    /// Lossless formats get the theme's dedicated lossless tint when it has one;
    /// everything else rides the accent.
    private func badgeColor(for format: AudioFormat) -> Color {
        let lossless: Set<AudioFormat> = [.flac16, .alac16, .mqa24]
        if lossless.contains(format), let badge = theme.palette.losslessBadge {
            return badge
        }
        return theme.palette.textSecondary
    }

    private var nowPlayingStar: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 13))
                .foregroundStyle(saved ? theme.palette.accent : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .help("Save this show to Favorites")
        .accessibilityLabel("Save show to Favorites")
        .accessibilityAddTraits(saved ? .isSelected : [])
    }

    // --- blocks ------------------------------------------------------------------

    @ViewBuilder
    private var nowPlayingBlock: some View {
        switch theme.transport {
        case .tapeLabel:
            TapeLabelCard()
        case .jCard:
            JCardStrip()
        case .standard, .faceplate, .clickWheel:
            // Faceplate has its own whole-bar treatment on the Mac; Click
            // Wheel's circular pad is an iOS full-screen idea — on the Mac
            // bar both fall back to the standard block in their own tokens.
            StandardNowPlaying()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(!player.hasPrevious)
            .help("Previous (p)")
            .accessibilityLabel("Previous track")

            Button {
                player.seek(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
            }
            .disabled(player.current == nil)
            .help("Back 15s (←)")
            .accessibilityLabel("Back 15 seconds")

            Button {
                player.togglePlayPause()
            } label: {
                if player.isBuffering {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 24)
                }
            }
            .disabled(player.current == nil)
            .help("Play / pause (space)")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityValue(player.isBuffering ? "Buffering" : "")

            Button {
                player.seek(by: 30)
            } label: {
                Image(systemName: "goforward.30")
            }
            .disabled(player.current == nil)
            .help("Forward 30s (→)")
            .accessibilityLabel("Forward 30 seconds")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!player.hasNext)
            .help("Next (n)")
            .accessibilityLabel("Next track")
        }
        .buttonStyle(.borderless)
    }

    private var seekBlock: some View {
        HStack(spacing: 8) {
            Text(Self.format(seconds: scrubbing ? scrubValue : player.currentTime))
                .font(theme.type.numeric(11))
                .frame(width: 44, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : min(player.currentTime, sliderMax) },
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
            .disabled(player.duration <= 0)
            .controlSize(.small)
            .accessibilityLabel("Playback position")
            .accessibilityValue(Self.format(seconds: scrubbing ? scrubValue : player.currentTime))

            Text(remainingText)
                .font(theme.type.numeric(11))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(width: 50, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var sliderMax: Double {
        max(player.duration, 1)
    }

    private var remainingText: String {
        guard player.duration > 0 else { return "--:--" }
        let position = scrubbing ? scrubValue : player.currentTime
        return "-" + Self.format(seconds: max(player.duration - position, 0))
    }

    private var volumeBlock: some View {
        @Bindable var player = app.player
        return HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: $player.volume, in: 0...1)
                .controlSize(.mini)
                .frame(width: 90)
                .accessibilityLabel("Volume")
        }
    }

    static func format(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Shared now-playing → FavShow bridge used by both the standard transport and
/// the faceplate. A track is favoritable only when it carries a `showId`
/// (i.e. it was queued from a show, not a single-track search hit).
@MainActor
enum NowPlayingFavorite {
    static func isSaved(_ track: QueueTrack?, favorites: FavoritesStore) -> Bool {
        guard let id = track?.showId else { return false }
        return favorites.isShowFavorited(id)
    }

    static func toggle(_ track: QueueTrack?, favorites: FavoritesStore) {
        guard let track, let id = track.showId else { return }
        favorites.toggleShow(
            id: id,
            title: track.show ?? track.title ?? "Show",
            artistName: track.artist ?? "",
            dateText: nil,
            venue: nil,
            imageURL: track.artworkPath.flatMap { NugsConstants.imageURL(path: $0)?.absoluteString })
    }
}
