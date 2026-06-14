import SwiftUI

/// The Receiver's signature transport: a brushed-metal faceplate with a live
/// L/R VU meter, knurled buttons, an LED volume ladder, a tuner-style seek, and
/// a seven-segment-ish quality readout. Reuses the player's scrub/seek/volume
/// bindings unchanged.
struct FaceplateTransport: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var player: PlayerService { app.player }

    var body: some View {
        HStack(spacing: 18) {
            channelBlock
            controls
            VUMeter(isPlaying: player.isPlaying)
                .frame(width: 150)
            seekBlock
            volumeLadder
            qualityReadout
                .frame(width: 130, alignment: .trailing)
            faceplateStar
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background {
            LinearGradient(
                colors: [Color(hex: 0x1C1A17), Color(hex: 0x14120F)],
                startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(.black.opacity(0.45)).frame(height: 1)
            }
        }
    }

    // --- left: channel counter + amber ticker -------------------------------

    private var channelBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(channelText)
                    .font(theme.type.numeric(13).weight(.heavy))
                    .foregroundStyle(theme.palette.accent)
                if let track = player.current {
                    Text(track.title ?? "Unknown")
                        .font(theme.type.title(14))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(1)
                }
            }
            Text(tickerText)
                .font(theme.type.numeric(9))
                .tracking(0.6)
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 220, alignment: .leading)
    }

    private var channelText: String {
        guard player.current != nil else { return "—" }
        return "\(player.index + 1)/\(player.queue.count)"
    }

    private var tickerText: String {
        guard let track = player.current else { return theme.copy.nowPlaying.uppercased() }
        return NowPlayingMeta.line(track).uppercased()
    }

    // --- center: knurled transport buttons ----------------------------------

    private var controls: some View {
        HStack(spacing: 12) {
            KnurledButton(system: "backward.fill", size: 30, glow: false) { player.previous() }
                .disabled(!player.hasPrevious)
            KnurledButton(system: "gobackward.15", size: 26, glow: false) { player.seek(by: -15) }
                .disabled(player.current == nil)
            KnurledButton(
                system: player.isPlaying ? "pause.fill" : "play.fill",
                size: 40, glow: player.isPlaying) { player.togglePlayPause() }
                .disabled(player.current == nil)
            KnurledButton(system: "goforward.30", size: 26, glow: false) { player.seek(by: 30) }
                .disabled(player.current == nil)
            KnurledButton(system: "forward.fill", size: 30, glow: false) { player.next() }
                .disabled(!player.hasNext)
        }
    }

    // --- seek (tuner dial) --------------------------------------------------

    private var seekBlock: some View {
        HStack(spacing: 8) {
            Text(TransportBar.format(seconds: scrubbing ? scrubValue : player.currentTime))
                .font(theme.type.numeric(11))
                .foregroundStyle(theme.palette.accent)
                .frame(width: 46, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : min(player.currentTime, sliderMax) },
                    set: { scrubValue = $0 }),
                in: 0...sliderMax
            ) { editing in
                if editing { scrubValue = player.currentTime } else { player.seek(to: scrubValue) }
                scrubbing = editing
            }
            .controlSize(.small)
            .tint(theme.palette.accent)
            .disabled(player.duration <= 0)

            Text(remainingText)
                .font(theme.type.numeric(11))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(width: 52, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var sliderMax: Double { max(player.duration, 1) }

    private var remainingText: String {
        guard player.duration > 0 else { return "--:--" }
        let position = scrubbing ? scrubValue : player.currentTime
        return "-" + TransportBar.format(seconds: max(player.duration - position, 0))
    }

    // --- volume LED ladder --------------------------------------------------

    private var volumeLadder: some View {
        @Bindable var player = app.player
        let segs = 10
        let lit = Int((Double(player.volume) * Double(segs)).rounded())
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<segs, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < lit ? theme.palette.accent : theme.palette.hairline)
                        .opacity(i < lit ? 1 : 0.5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 5 + CGFloat(i))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        player.volume = Float(max(0, min(1, v.location.x / geo.size.width)))
                    })
        }
        .frame(width: 76, height: 16)
    }

    // --- quality readout ----------------------------------------------------

    private var qualityReadout: some View {
        Text(qualityText)
            .font(theme.type.numeric(9))
            .foregroundStyle(theme.palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var qualityText: String {
        guard let pick = player.nowPick else { return "" }
        var parts = [pick.format.badge.uppercased()]
        if let specs = player.specs {
            if let depth = specs.bitDepth { parts.append("\(depth)BIT") }
            if specs.sampleRate > 0 { parts.append(String(format: "%.1fkHz", specs.sampleRate / 1000)) }
            parts.append(specs.channels == 2 ? "STEREO" : "\(specs.channels)CH")
        }
        return parts.joined(separator: " · ")
    }

    private var faceplateStar: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(saved ? theme.palette.accent : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .help("Save this show to Favorites")
    }
}

// MARK: - VU meter

/// Two horizontal LED-segment level bars (L/R) that sway while playing and rest
/// at the floor when paused. Synthesized motion (no FFT), throttled to ~12fps
/// and frozen when not playing.
private struct VUMeter: View {
    @Environment(\.theme) private var theme
    let isPlaying: Bool

    private let segments = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: 3) {
                channel(level: level(t, seed: 0.0), label: "L")
                channel(level: level(t, seed: 1.7), label: "R")
            }
        }
    }

    private func level(_ t: Double, seed: Double) -> Double {
        guard isPlaying else { return 0.06 }
        let a = 0.5 + 0.5 * sin(t * 6.0 + seed)
        let b = 0.5 + 0.5 * sin(t * 11.3 + seed * 2.3)
        return min(1, 0.22 + 0.62 * (0.6 * a + 0.4 * b))
    }

    private func channel(level: Double, label: String) -> some View {
        let lit = Int((level * Double(segments)).rounded())
        return HStack(spacing: 4) {
            Text(label)
                .font(theme.type.numeric(8).weight(.bold))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(width: 8)
            HStack(spacing: 1.5) {
                ForEach(0..<segments, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color(index: i, lit: i < lit))
                        .frame(width: 5, height: 7)
                        .opacity(i < lit ? 1 : 0.35)
                }
            }
        }
    }

    private func color(index: Int, lit: Bool) -> Color {
        guard lit else { return theme.palette.hairline }
        let isPeak = index >= segments - 2
        return isPeak ? (theme.palette.vuPeak ?? theme.palette.accent) : theme.palette.accent
    }
}

// MARK: - Knurled button

private struct KnurledButton: View {
    @Environment(\.theme) private var theme
    let system: String
    let size: CGFloat
    let glow: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(hex: 0x2A2622), Color(hex: 0x141210)],
                        center: .center, startRadius: 1, endRadius: size))
                Circle().strokeBorder(theme.palette.hairline, lineWidth: 1)
                Image(systemName: system)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(theme.palette.accent)
            }
            .frame(width: size, height: size)
            .shadow(color: glow ? theme.palette.accent.opacity(0.55) : .clear, radius: glow ? 6 : 0)
        }
        .buttonStyle(.plain)
    }
}
