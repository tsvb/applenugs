import SwiftUI

/// Right-hand inspector: now playing, stream quality, and the up-next queue.
/// Port of the web DashboardPanel, with the format/spec data coming from the
/// player's resolved pick + AVFoundation decoder instead of header parsing.
struct DashboardPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui

    private var player: PlayerService { app.player }

    var body: some View {
        List {
            nowPlayingSection
            qualitySection
            queueSection
        }
        .listStyle(.sidebar)
    }

    // --- now playing ---------------------------------------------------------

    @ViewBuilder
    private var nowPlayingSection: some View {
        Section("Now Playing") {
            if let track = player.current {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title ?? "Unknown track")
                        .font(.callout.weight(.semibold))
                    if let artist = track.artist {
                        Text(artist).font(.caption)
                    }
                    if let show = track.show {
                        Text(show).font(.caption).foregroundStyle(.secondary)
                    }
                    if player.duration > 0 {
                        Text("\(TransportBar.format(seconds: player.currentTime)) / \(TransportBar.format(seconds: player.duration))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = player.playbackError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Idle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // --- quality ----------------------------------------------------------------

    @ViewBuilder
    private var qualitySection: some View {
        if let pick = player.nowPick {
            Section("Quality") {
                row("Format", pick.format.qualityLabel)
                row("Platform tier", String(pick.platformId))
                if let specs = player.specs {
                    if specs.sampleRate > 0 {
                        row("Sample rate", String(format: "%.1f kHz", specs.sampleRate / 1000))
                    }
                    if let bitDepth = specs.bitDepth {
                        row("Bit depth", "\(bitDepth)-bit")
                    }
                    row("Channels", specs.channels == 2 ? "Stereo" : String(specs.channels))
                }
                if player.bufferedAhead > 0 {
                    row("Buffered", String(format: "%.0f s ahead", player.bufferedAhead))
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    // --- queue -------------------------------------------------------------------

    @ViewBuilder
    private var queueSection: some View {
        Section {
            if player.queue.isEmpty {
                Text("Queue is empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { i, track in
                    queueRow(i, track)
                }
            }
        } header: {
            HStack {
                Text("Up Next")
                Spacer()
                if !player.queue.isEmpty {
                    Button("Clear") { player.clear() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func queueRow(_ i: Int, _ track: QueueTrack) -> some View {
        HStack(spacing: 6) {
            Button {
                player.jump(to: i)
            } label: {
                HStack(spacing: 6) {
                    if i == player.index {
                        Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .frame(width: 16)
                    } else {
                        Text(String(i + 1))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                    }
                    Text(track.title ?? "Unknown track")
                        .font(.caption)
                        .lineLimit(1)
                        .fontWeight(i == player.index ? .semibold : .regular)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                player.remove(at: i)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Remove from queue")
        }
    }
}
