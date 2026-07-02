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
                .accessibilityHidden(true)
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
                .accessibilityLabel("Previous track")
            KnurledButton(system: "gobackward.15", size: 26, glow: false) { player.seek(by: -15) }
                .disabled(player.current == nil)
                .accessibilityLabel("Back 15 seconds")
            KnurledButton(
                system: player.isPlaying ? "pause.fill" : "play.fill",
                size: 40, glow: player.isPlaying) { player.togglePlayPause() }
                .disabled(player.current == nil)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            KnurledButton(system: "goforward.30", size: 26, glow: false) { player.seek(by: 30) }
                .disabled(player.current == nil)
                .accessibilityLabel("Forward 30 seconds")
            KnurledButton(system: "forward.fill", size: 30, glow: false) { player.next() }
                .disabled(!player.hasNext)
                .accessibilityLabel("Next track")
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
            .accessibilityLabel("Playback position")
            .accessibilityValue(TransportBar.format(seconds: scrubbing ? scrubValue : player.currentTime))

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
        // The drag-on-shapes ladder is invisible to VoiceOver; expose it as a
        // single adjustable Volume control.
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((player.volume * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.volume = min(1, player.volume + 0.05)
            case .decrement: player.volume = max(0, player.volume - 0.05)
            @unknown default: break
            }
        }
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
        .accessibilityLabel("Save show to Favorites")
        .accessibilityAddTraits(saved ? .isSelected : [])
    }
}
