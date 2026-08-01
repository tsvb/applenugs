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
    var trackHeight: CGFloat = 3
    var showsClocks: Bool = true
    /// Defaults to the theme's effective (possibly art-driven) accent.
    var fillColor: Color? = nil

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
            if showsClocks { clocks }
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
                        .fill(fillColor ?? theme.effectiveAccent(art: artColor))
                        .frame(width: width * fraction)
                }
                .frame(height: trackHeight)
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

    private var remaining: String {
        MiniPlayerClock.remainingText(elapsed: position, duration: duration)
    }
}

/// A single time readout, for variants that place elapsed and remaining apart
/// from the scrubber (Tape Room puts them in the shell's bottom corners).
///
/// **A leaf view**, for the same reason as `MiniPlayerScrubTrack`: it owns a
/// `currentTime` read.
struct MiniPlayerClock: View {
    enum Kind { case elapsed, remaining }

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    let kind: Kind
    var size: CGFloat = 9

    var body: some View {
        Text(text)
            .font(theme.type.numeric(size))
            .foregroundStyle(theme.palette.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)   // the scrubber already announces position
    }

    private var text: String {
        let player = app.player
        switch kind {
        case .elapsed:
            guard player.duration > 0 else { return "--:--" }
            return TransportBar.format(seconds: player.currentTime)
        case .remaining:
            return Self.remainingText(elapsed: player.currentTime, duration: player.duration)
        }
    }

    /// Shared "-mm:ss" remaining-time formula, and its "--:--" placeholder
    /// before duration is known. Reused by `MiniPlayerScrubTrack` so the two
    /// clocks can't drift as more variants (Task 4+) add their own readouts.
    static func remainingText(elapsed: Double, duration: Double) -> String {
        guard duration > 0 else { return "--:--" }
        return "-" + TransportBar.format(seconds: max(duration - elapsed, 0))
    }
}

/// prev / play-pause / next, spread evenly. The play button's treatment is the
/// theme's business, so it is chosen by `Style` rather than forked per variant.
struct MiniPlayerTransportTriad: View {
    enum Style: Equatable {
        case filled     // Soundboard: solid accent disc
        case outline    // Shoebox: rust keyline
        case bare       // Tape Room's ridged band: glyph only
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
                .foregroundStyle(style == .bare ? theme.palette.accent : theme.palette.textPrimary)
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
            ZStack {
                switch style {
                case .filled:  Circle().fill(theme.effectiveAccent(art: artColor))
                case .outline: Circle().strokeBorder(theme.palette.playState, lineWidth: 1.5)
                case .bare:    Color.clear
                }
                if player.isBuffering {
                    ProgressView().controlSize(.small).tint(playGlyphColor)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: style == .bare ? glyphSize + 2 : glyphSize))
                        .foregroundStyle(playGlyphColor)
                }
            }
            .frame(width: playDiameter, height: playDiameter)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(player.current == nil)
        .help("Play / pause (space)")
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        .accessibilityValue(player.isBuffering ? "Buffering" : "")
    }

    private var playGlyphColor: Color {
        switch style {
        case .filled:  return theme.palette.base
        case .outline: return theme.palette.playState
        case .bare:    return theme.palette.accent
        }
    }
}
