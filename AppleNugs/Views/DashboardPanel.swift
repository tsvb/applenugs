import SwiftUI

/// Right-hand inspector: now playing, stream quality, and the up-next queue.
/// Port of the web DashboardPanel, with the format/spec data coming from the
/// player's resolved pick + AVFoundation decoder instead of header parsing.
struct DashboardPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    private var player: PlayerService { app.player }

    var body: some View {
        List {
            nowPlayingSection
            qualitySection
            queueSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.palette.base)
    }

    /// Section headers in the theme's display face; condensed themes track them
    /// out as letterpress small caps.
    private func sectionHeader(_ text: String) -> some View {
        let condensed = theme.caps.contains(.condensedHeaders)
        return Text(condensed ? text.uppercased() : text)
            .font(theme.type.section(12))
            .tracking(condensed ? 1.6 : 0)
            .foregroundStyle(theme.palette.textSecondary)
    }

    // --- now playing ---------------------------------------------------------

    @ViewBuilder
    private var nowPlayingSection: some View {
        Section {
            if let track = player.current {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title ?? "Unknown track")
                        .font(theme.type.title(15))
                    if let artist = track.artist {
                        Text(artist).font(.caption)
                    }
                    if let show = track.show {
                        Text(show).font(.caption).foregroundStyle(theme.palette.textSecondary)
                    }
                    if player.duration > 0 {
                        Text("\(TransportBar.format(seconds: player.currentTime)) / \(TransportBar.format(seconds: player.duration))")
                            .font(theme.type.numeric(11))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
                .listRowBackground(
                    Color.clear.artWash(theme.washStyle, color: artColor))
                if let error = player.playbackError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text(theme.copy.dashboardIdle)
                    .font(.caption)
                    .foregroundStyle(theme.palette.textIdle)
            }
        } header: {
            sectionHeader(theme.copy.dashHeaders.now)
        }
    }

    // --- quality ----------------------------------------------------------------

    @ViewBuilder
    private var qualitySection: some View {
        if let pick = player.nowPick {
            Section {
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
            } header: {
                sectionHeader(theme.copy.dashHeaders.quality)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.palette.textSecondary)
            Spacer()
            Text(value).font(theme.type.numeric(11))
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
                    .foregroundStyle(theme.palette.textIdle)
            } else {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { i, track in
                    queueRow(i, track)
                }
            }
        } header: {
            HStack {
                sectionHeader(theme.copy.dashHeaders.upNext)
                Spacer()
                if !player.queue.isEmpty {
                    Button("Clear") { player.clear() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(theme.palette.textSecondary)
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
                        if theme.caps.contains(.equalizerRows) {
                            EqualizerBars(isPlaying: player.isPlaying)
                                .frame(width: 16)
                        } else {
                            Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                .font(.caption2)
                                .foregroundStyle(theme.activeEmphasis(art: artColor))
                                .frame(width: 16)
                        }
                    } else {
                        Text(String(i + 1))
                            .font(theme.type.numeric(10))
                            .foregroundStyle(theme.palette.textSecondary)
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
