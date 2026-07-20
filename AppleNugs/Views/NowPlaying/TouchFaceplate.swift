import SwiftUI

/// The Receiver's now-playing as a touch-first faceplate: the desktop bar's
/// design language (brushed chassis, knurled transport, LED volume ladder,
/// L/R VU meter, tuner seek, seven-segment-ish readouts) re-proportioned for
/// a phone in the hand — 44pt+ targets, a 76pt play knob, full-width meters.
struct TouchFaceplate: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var dashboardShown = false

    private var player: PlayerService { app.player }

    var body: some View {
        VStack(spacing: 24) {
            header

            Spacer(minLength: 0)

            chassis

            Spacer(minLength: 0)

            seekBlock
                .padding(.horizontal, 24)

            controls

            volumeLadder

            qualityReadout

            bottomRow
                .padding(.horizontal, 28)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [Color(hex: 0x1C1A17), Color(hex: 0x14120F)],
                startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        }
        .sheet(isPresented: $dashboardShown) {
            DashboardPanel()
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
                .presentationBackground(theme.palette.base)
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

            // The channel block already reads out queue position; the header
            // carries the tuner flavor only while idle.
            Text(player.current != nil ? "RECEIVING" : theme.copy.nowPlaying.uppercased())
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

    // --- chassis: channel readout + big VU -----------------------------------

    private var chassis: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(channelText)
                        .font(theme.type.numeric(15).weight(.heavy))
                        .foregroundStyle(theme.palette.accent)
                    Text(player.current?.title ?? "—")
                        .font(theme.type.title(18))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(1)
                }
                Text(tickerText)
                    .font(theme.type.numeric(10))
                    .tracking(0.6)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(2)
            }

            VUMeter(isPlaying: player.isPlaying)
                .scaleEffect(1.9, anchor: .leading)
                .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: 0x231F1B), Color(hex: 0x161310)],
                    startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.palette.hairline, lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.05))
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                }
        }
        .padding(.horizontal, 20)
    }

    private var channelText: String {
        guard player.current != nil else { return "—" }
        return "\(player.index + 1)/\(player.queue.count)"
    }

    private var tickerText: String {
        guard let track = player.current else { return theme.copy.nowPlaying.uppercased() }
        return NowPlayingMeta.line(track).uppercased()
    }

    // --- tuner seek -----------------------------------------------------------

    private var seekBlock: some View {
        HStack(spacing: 10) {
            Text(TransportBar.format(seconds: scrubbing ? scrubValue : player.currentTime))
                .font(theme.type.numeric(13))
                .foregroundStyle(theme.palette.accent)
                .frame(width: 52, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : min(player.currentTime, sliderMax) },
                    set: { scrubValue = $0 }),
                in: 0...sliderMax
            ) { editing in
                if editing { scrubValue = player.currentTime } else { player.seek(to: scrubValue) }
                scrubbing = editing
            }
            .tint(theme.palette.accent)
            .disabled(player.duration <= 0)
            .accessibilityLabel("Playback position")
            .accessibilityValue(TransportBar.format(seconds: scrubbing ? scrubValue : player.currentTime))

            Text(remainingText)
                .font(theme.type.numeric(13))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(width: 58, alignment: .leading)
        }
    }

    private var sliderMax: Double { max(player.duration, 1) }

    private var remainingText: String {
        guard player.duration > 0 else { return "--:--" }
        let position = scrubbing ? scrubValue : player.currentTime
        return "-" + TransportBar.format(seconds: max(player.duration - position, 0))
    }

    // --- knurled transport ----------------------------------------------------

    private var controls: some View {
        HStack(spacing: 22) {
            KnurledButton(system: "backward.fill", size: 54, glow: false) { player.previous() }
                .disabled(!player.hasPrevious)
                .accessibilityLabel("Previous track")
            KnurledButton(system: "gobackward.15", size: 46, glow: false) { player.seek(by: -15) }
                .disabled(player.current == nil)
                .accessibilityLabel("Back 15 seconds")
            KnurledButton(
                system: player.isPlaying ? "pause.fill" : "play.fill",
                size: 76, glow: player.isPlaying) { player.togglePlayPause() }
                .disabled(player.current == nil)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            KnurledButton(system: "goforward.30", size: 46, glow: false) { player.seek(by: 30) }
                .disabled(player.current == nil)
                .accessibilityLabel("Forward 30 seconds")
            KnurledButton(system: "forward.fill", size: 54, glow: false) { player.next() }
                .disabled(!player.hasNext)
                .accessibilityLabel("Next track")
        }
    }

    // --- LED volume ladder ------------------------------------------------------

    private var volumeLadder: some View {
        @Bindable var player = app.player
        let segs = 14
        let lit = Int((Double(player.volume) * Double(segs)).rounded())
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<segs, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < lit ? theme.palette.accent : theme.palette.hairline)
                        .opacity(i < lit ? 1 : 0.5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 8 + CGFloat(i) * 1.6)
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
        .frame(width: 240, height: 34)
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

    // --- quality + bottom -------------------------------------------------------

    private var qualityReadout: some View {
        Text(qualityText)
            .font(theme.type.numeric(10))
            .foregroundStyle(theme.palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minHeight: 14)
    }

    private var qualityText: String {
        guard let pick = player.nowPick else { return " " }
        var parts = [pick.format.badge.uppercased()]
        if let specs = player.specs {
            if let depth = specs.bitDepth { parts.append("\(depth)BIT") }
            if specs.sampleRate > 0 { parts.append(String(format: "%.1fkHz", specs.sampleRate / 1000)) }
            parts.append(specs.channels == 2 ? "STEREO" : "\(specs.channels)CH")
        }
        return parts.joined(separator: " · ")
    }

    private var bottomRow: some View {
        HStack {
            RoutePicker(tint: theme.palette.accent)
                .frame(width: 44, height: 44)

            Spacer()

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
        }
    }

    private var star: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(saved ? theme.palette.accent : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .accessibilityLabel("Save show to Favorites")
        .accessibilityAddTraits(saved ? .isSelected : [])
    }
}
