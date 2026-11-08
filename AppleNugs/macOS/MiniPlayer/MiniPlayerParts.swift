import SwiftUI

/// The scrubber and its clock line.
///
/// **A leaf view, deliberately.** The playback tick mutates `currentTime` ~4×/sec.
/// Registering that dependency here — rather than in a miniplayer body — keeps
/// the inspector's panel body and its queue `ForEach` from re-diffing on every
/// tick. Same discipline as `ElapsedTimeLine` and `BufferedRow` in
/// `DashboardPanel`. Do not hoist these reads into a parent.
struct MiniPlayerScrubTrack: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    /// Drawn thickness. The hit area stays 20 pt tall regardless.
    private static let trackHeight: CGFloat = 3

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var player: PlayerService { app.player }
    private var duration: Double { player.duration }
    /// While dragging, hold the thumb at the dragged value so playback ticks
    /// cannot yank it back — the same trick `TransportBar.seekBlock` uses.
    private var position: Double { scrubbing ? scrubValue : player.currentTime }

    var body: some View {
        VStack(spacing: 5) {
            track
            clocks
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                Color.clear
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.palette.hairline)
                    Capsule()
                        .fill(theme.effectiveAccent(art: artColor))
                        .frame(width: width * fraction)
                }
                .frame(height: Self.trackHeight)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0, width > 0 else { return }
                        scrubbing = true
                        scrubValue = min(max(value.location.x / width, 0), 1) * duration
                    }
                    .onEnded { _ in
                        defer { scrubbing = false }
                        guard scrubbing, duration > 0 else { return }
                        player.seek(to: min(scrubValue, duration))
                    }
            )
        }
        .frame(height: 20)
        .disabled(duration <= 0)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(TransportBar.format(seconds: position))
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            switch direction {
            case .increment: player.seek(by: 5)
            case .decrement: player.seek(by: -5)
            @unknown default: break
            }
        }
    }

    private var fraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(position / duration, 0), 1))
    }

    private var clocks: some View {
        HStack {
            Text(TransportBar.format(seconds: position))
            Spacer(minLength: 4)
            Text(remaining)
        }
        .font(theme.type.numeric(10))
        .foregroundStyle(theme.palette.textSecondary)
        .lineLimit(1)
    }

    /// "-mm:ss" remaining, and its "--:--" placeholder before duration is known.
    private var remaining: String {
        guard duration > 0 else { return "--:--" }
        return "-" + TransportBar.format(seconds: max(duration - position, 0))
    }
}

/// prev / play-pause / next, spread evenly. The play button's treatment is the
/// theme's business, so it is chosen by `Style` rather than forked per variant.
struct MiniPlayerTransportTriad: View {
    enum Style: Equatable {
        case filled     // solid accent disc
        case sticker    // Yeti: the 46pt play sticker (an accent disc would be a pink fill)
    }

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    var style: Style = .filled
    var glyphSize: CGFloat = 13
    var playDiameter: CGFloat = 34

    private var player: PlayerService { app.player }

    var body: some View {
        HStack(spacing: 0) {
            step("backward.fill", label: "Previous track", help: "Previous (p)", enabled: player.hasPrevious) {
                player.previous()
            }
            Spacer(minLength: 8)
            playButton
            Spacer(minLength: 8)
            step("forward.fill", label: "Next track", help: "Next (n)", enabled: player.hasNext) {
                player.next()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func step(_ system: String,
                      label: String,
                      help: String,
                      enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        HapticButton(.transportStep, action: action) {
            Image(systemName: system)
                .font(.system(size: glyphSize))
                .foregroundStyle(theme.palette.textPrimary)
                // 20pt minimum hit area, however small the glyph is drawn.
                .frame(width: 30, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(label)
    }

    private var playButton: some View {
        HapticButton(.transportToggle) {
            player.togglePlayPause()
        } label: {
            if style == .sticker {
                // Its own disc, glyph and spinner; one size whatever the state.
                PlaySticker(isPlaying: player.isPlaying,
                            isBuffering: player.isBuffering,
                            size: .s46)
                    .foilFocusOutline(Circle())
            } else {
                ZStack {
                    Circle().fill(theme.effectiveAccent(art: artColor))
                    if player.isBuffering {
                        ProgressView().controlSize(.small).tint(theme.palette.base)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: glyphSize))
                            .foregroundStyle(theme.palette.base)
                    }
                }
                .frame(width: playDiameter, height: playDiameter)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        // The sticker draws its own foil focus outline; no system ring too.
        .macFocusEffectDisabled(style == .sticker)
        .disabled(player.current == nil)
        .help("Play / pause (space)")
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        .accessibilityValue(player.isBuffering ? "Buffering" : "")
    }
}
