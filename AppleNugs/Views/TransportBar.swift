import SwiftUI

/// Bottom transport bar: now-playing block, prev/play/next, seek, volume,
/// and the current format badge. Mirrors the web Transport component.
struct TransportBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    /// While the user drags, hold the thumb at the dragged value so the
    /// playback ticks don't yank it back.
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var player: PlayerService { app.player }
    private var plainVoice: Bool { theme.caps.contains(.plainVoice) }

    var body: some View {
        #if os(macOS)
        standardBar
        #else
        // iOS uses NowPlayingPill in the tab accessory; nothing docks here.
        EmptyView()
        #endif
    }

    #if os(macOS)
    private var standardBar: some View {
        HStack(spacing: 16) {
            nowPlayingBlock
                .frame(width: 230, alignment: .leading)

            controls

            seekBlock

            volumeBlock

            // AirPlay isn't time moving: slush, not foil, under `.plainVoice`.
            RoutePicker(tint: plainVoice ? theme.palette.textSecondary : theme.palette.accent)
                .frame(width: 26, height: 26)
                .help("AirPlay")

            nowPlayingStar

            Button { openWindow(id: NowPlayingWindow.id) } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)
            .help("Open the Now Playing window")
            .accessibilityLabel("Open the Now Playing window")

            if theme.caps.contains(.stickers) {
                // The price sticker replaces the badge. Presence follows
                // `player.current` (inside the sticker's own init), never
                // `nowPick`, and it holds its 36pt frame when hidden, so the
                // bar never reflows at a track boundary.
                PriceSticker(player: player, size: .s36)
            } else if let pick = player.nowPick {
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
        if format.isLossless, let badge = theme.palette.losslessBadge {
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
                // A saved show isn't time moving: under `.plainVoice` the
                // filled star is snow, not an accent fill.
                .foregroundStyle(saved
                                 ? (plainVoice ? theme.palette.textPrimary : theme.palette.accent)
                                 : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .help("Save this show to Favorites")
        .accessibilityLabel("Save show to Favorites")
        .accessibilityAddTraits(saved ? .isSelected : [])
    }

    // --- blocks ------------------------------------------------------------------

    private var nowPlayingBlock: some View {
        StandardNowPlaying()
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

            playPauseButton

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

    /// Yeti's 34pt play sticker under `.stickers` (its own disc, glyph and
    /// spinner, one size in every state); the plain glyph otherwise.
    @ViewBuilder
    private var playPauseButton: some View {
        if theme.caps.contains(.stickers) {
            Button {
                player.togglePlayPause()
            } label: {
                PlaySticker(isPlaying: player.isPlaying,
                            isBuffering: player.isBuffering,
                            size: .s34)
                    .foilFocusOutline(Circle())
            }
            // `.borderless` (the cluster's style) would decorate the sticker.
            .buttonStyle(.plain)
            // The sticker draws its own foil focus outline; no system ring too.
            .macFocusEffectDisabled()
            .disabled(player.current == nil)
            .help("Play / pause (space)")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityValue(player.isBuffering ? "Buffering" : "")
        } else {
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
        }
    }

    private var seekBlock: some View {
        HStack(spacing: 8) {
            Text(Self.format(seconds: scrubbing ? scrubValue : player.currentTime))
                .font(theme.type.numeric(11))
                .frame(width: 44, alignment: .trailing)

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
            .disabled(player.duration <= 0)
            .controlSize(.small)
            // The root tint is snow under `.plainVoice`; time moving is foil,
            // so say it here. Other themes keep inheriting the root's accent.
            .tintIfSet(plainVoice ? theme.effectiveAccent(art: artColor) : nil)
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
                // Volume isn't time, so under `.plainVoice` it's slush, not foil.
                .tintIfSet(plainVoice ? theme.palette.textSecondary : nil)
                .accessibilityLabel("Volume")
        }
    }

    static func format(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Shared now-playing → FavShow bridge used by the transport bar and the
/// now-playing screens. A track is favoritable only when it carries a `showId`
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
