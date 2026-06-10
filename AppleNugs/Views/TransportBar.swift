import SwiftUI

/// Bottom transport bar: now-playing block, prev/play/next, seek, volume,
/// and the current format badge. Mirrors the web Transport component.
struct TransportBar: View {
    @Environment(AppModel.self) private var app

    /// While the user drags, hold the thumb at the dragged value so the
    /// playback ticks don't yank it back.
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var player: PlayerService { app.player }

    var body: some View {
        HStack(spacing: 16) {
            nowPlayingBlock
                .frame(width: 230, alignment: .leading)

            controls

            seekBlock

            volumeBlock

            if let pick = player.nowPick {
                Text(pick.format.badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    .help(pick.format.qualityLabel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // --- blocks ------------------------------------------------------------------

    @ViewBuilder
    private var nowPlayingBlock: some View {
        if let track = player.current {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(player.index + 1)/\(player.queue.count)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(track.title ?? "Unknown track")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                Text(meta(for: track))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("Nothing playing. Press / to search.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private func meta(for track: QueueTrack) -> String {
        var parts: [String] = []
        if let artist = track.artist { parts.append(artist) }
        if let show = track.show { parts.append(show) }
        return parts.joined(separator: " · ")
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

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 24)
            }
            .disabled(player.current == nil)
            .help("Play / pause (space)")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!player.hasNext)
            .help("Next (n)")
        }
        .buttonStyle(.borderless)
    }

    private var seekBlock: some View {
        HStack(spacing: 8) {
            Text(Self.format(seconds: scrubbing ? scrubValue : player.currentTime))
                .font(.caption)
                .monospacedDigit()
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

            Text(remainingText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
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
            Slider(value: $player.volume, in: 0...1)
                .controlSize(.mini)
                .frame(width: 90)
        }
    }

    static func format(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
