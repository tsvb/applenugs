import SwiftUI

/// Right-hand inspector: now playing, stream quality, and the up-next queue.
/// Port of the web DashboardPanel, with the format/spec data coming from the
/// player's resolved pick + AVFoundation decoder instead of header parsing.
///
/// Rendered as a `ScrollView`+`VStack` rather than a `List`: the inspector
/// content updates every frame during playback (elapsed time, buffer-ahead,
/// the equalizer animation), and a `List` is `NSTableView`-backed. Live size
/// churn inside the inspector's split child re-enters the `NSTableView`
/// delegate, which on macOS 26 aborts with `_postWindowNeedsUpdateConstraints`
/// when it collides with a window resize / inspector toggle. A `ScrollView`
/// constrains its content to the column width (so text truncates instead of
/// overflowing) and has no table delegate to re-enter.
struct DashboardPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    private var player: PlayerService { app.player }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                nowPlayingSection
                qualitySection
                queueSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(theme.copy.dashHeaders.now)
            if let track = player.current {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title ?? "Unknown track")
                        .font(theme.type.title(15))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let artist = track.artist {
                        Text(artist)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let show = track.show {
                        Text(show)
                            .font(.caption)
                            .foregroundStyle(theme.palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    // A leaf view: the 4Hz currentTime dependency registers
                    // here, not on the whole inspector (whose queue list
                    // would otherwise re-diff every tick).
                    ElapsedTimeLine()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.clear.artWash(theme.washStyle, color: artColor))
                if let error = player.playbackError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(theme.copy.dashboardIdle)
                    .font(.caption)
                    .foregroundStyle(theme.palette.textIdle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // --- quality ----------------------------------------------------------------

    @ViewBuilder
    private var qualitySection: some View {
        if let pick = player.nowPick {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader(theme.copy.dashHeaders.quality)
                VStack(spacing: 5) {
                    row("Format", pick.format.qualityLabel)
                    // platformId 0 is the local-file sentinel, not a tier.
                    if pick.platformId > 0 {
                        row("Platform tier", String(pick.platformId))
                    } else {
                        row("Source", "Downloaded file")
                    }
                    if let specs = player.specs {
                        if specs.sampleRate > 0 {
                            row("Sample rate", String(format: "%.1f kHz", specs.sampleRate / 1000))
                        }
                        if let bitDepth = specs.bitDepth {
                            row("Bit depth", "\(bitDepth)-bit")
                        }
                        row("Channels", specs.channels == 2 ? "Stereo" : String(specs.channels))
                    }
                    BufferedRow()   // leaf: isolates the ticking bufferedAhead read
                }
            }
        }
    }

    /// A label/value row. The label keeps its width; the value truncates so the
    /// row can never demand more width than the inspector column.
    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .font(theme.type.numeric(11))
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    // --- queue -------------------------------------------------------------------

    @ViewBuilder
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if player.queue.isEmpty {
                Text("Queue is empty")
                    .font(.caption)
                    .foregroundStyle(theme.palette.textIdle)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { i, track in
                        queueRow(i, track)
                    }
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
                        .truncationMode(.tail)
                        .fontWeight(i == player.index ? .semibold : .regular)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(i == player.index
                ? "Now playing, \(track.title ?? "track")"
                : "Play \(track.title ?? "track")")

            Button {
                player.remove(at: i)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Remove from queue")
            .accessibilityLabel("Remove from queue")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 4Hz leaf views

/// The playback tick mutates currentTime ~4x/sec while playing. These leaves
/// carry that @Observable dependency so the inspector's body — including the
/// full queue ForEach — re-evaluates only on real state changes.
private struct ElapsedTimeLine: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        if app.player.duration > 0 {
            Text("\(TransportBar.format(seconds: app.player.currentTime)) / \(TransportBar.format(seconds: app.player.duration))")
                .font(theme.type.numeric(11))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
        }
    }
}

private struct BufferedRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        if app.player.bufferedAhead > 0 {
            HStack(spacing: 8) {
                Text("Buffered")
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(String(format: "%.0f s ahead", app.player.bufferedAhead))
                    .font(theme.type.numeric(11))
                    .lineLimit(1)
            }
            .font(.caption)
        }
    }
}
