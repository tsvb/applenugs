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
            #if os(iOS)
            legacyNowPlayingBlock
            #else
            // The Mac inspector gets the per-theme miniplayer. iOS keeps the
            // text block above: it reaches this panel as a sheet from the
            // full-screen players, which already carry their own transport.
            DashboardMiniPlayer()
            // Deliberately still conditional, unlike the Signal rows below.
            // This is not transient churn — startCurrent() clears it and only a
            // real failure sets it — so permanently reserving two lines of empty
            // space for a state that is almost never present would cost more
            // than the one jump it prevents (clicking a new track after an
            // error). If it ever does bother us, the fix is to fold the error
            // into the Signal section as an extra row, not to reserve a gap.
            if let error = player.playbackError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif
        }
    }

    #if os(iOS)
    /// The original text-only now-playing block, still used on iOS.
    @ViewBuilder
    private var legacyNowPlayingBlock: some View {
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
    #endif

    // --- quality ----------------------------------------------------------------

    /// Gated on `player.current`, NOT on `player.nowPick`/`player.specs`.
    ///
    /// Those two are nilled by `startCurrent()` on every track change and only
    /// come back after a stream resolve and an asset load respectively, so
    /// keying the section (or any individual row) on them made it collapse from
    /// six rows to two on every click in the Up Next list — jumping the whole
    /// queue below it — and hid it entirely on a launch-restored queue. The row
    /// SET is now constant for the life of a track and unknown values degrade to
    /// `SignalReadout.unknown`; see `SignalReadout` for why that beats a
    /// reserved height, and `SignalReadoutTests` for the invariant.
    ///
    /// The idle state is still correct: `stopPlayback()` is reachable only from
    /// `clear()` and `remove(at:)`-to-empty, both of which also empty the queue,
    /// so `current == nil` exactly when there is genuinely nothing playing.
    @ViewBuilder
    private var qualitySection: some View {
        if player.current != nil {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader(theme.copy.dashHeaders.quality)
                VStack(spacing: 5) {
                    ForEach(SignalReadout.rows(format: player.nowPick?.format,
                                               platformId: player.nowPick?.platformId,
                                               sampleRate: player.specs?.sampleRate,
                                               bitDepth: player.specs?.bitDepth,
                                               channels: player.specs?.channels)) { row in
                        SignalRowView(label: row.label, value: row.value, isUnknown: row.isUnknown)
                    }
                    BufferedRow()   // leaf: isolates the ticking bufferedAhead read
                }
            }
        }
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

// MARK: - rows

/// A label/value row. The label keeps its width; the value truncates so the row
/// can never demand more width than the inspector column.
///
/// Takes plain values and reads only `\.theme` — deliberately NO
/// `@Environment(AppModel.self)`, so that `BufferedRow` can render one of these
/// without the ticking `bufferedAhead` dependency escaping the leaf.
///
/// An unknown value is dimmed via `foregroundStyle` and NOTHING else: changing
/// the font, size or weight would move the row height and reintroduce, one row
/// at a time, the collapse this whole arrangement removes.
private struct SignalRowView: View {
    @Environment(\.theme) private var theme

    let label: String
    let value: String
    var isUnknown: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .font(theme.type.numeric(11))
                .foregroundStyle(isUnknown ? theme.palette.textIdle : theme.palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

// MARK: - 4Hz leaf views

/// The playback tick mutates currentTime ~4x/sec while playing. These leaves
/// carry that @Observable dependency so the inspector's body — including the
/// full queue ForEach — re-evaluates only on real state changes.
///
/// A leaf must also render CONSTANT-HEIGHT content. A leaf that collapses to
/// nothing when its value is unknown changes size, and a size change in a child
/// invalidates the parent's layout — which is both the visible jump users see
/// and the perf cost the isolation exists to avoid. Rendering a placeholder row
/// instead means the tick can no longer invalidate the enclosing VStack at all.
#if os(iOS)
private struct ElapsedTimeLine: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        // Always rendered. `duration` is zeroed on every track change, so
        // hiding the line while it's unknown made the block above the Signal
        // section shrink and grow on each track — the same defect one section
        // up. `--:--` is the clock placeholder used by MiniPlayerClock.
        let known = app.player.duration > 0
        Text(known
             ? "\(TransportBar.format(seconds: app.player.currentTime)) / \(TransportBar.format(seconds: app.player.duration))"
             : "--:-- / --:--")
            .font(theme.type.numeric(11))
            .foregroundStyle(known ? theme.palette.textSecondary : theme.palette.textIdle)
            .lineLimit(1)
    }
}
#endif

private struct BufferedRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // The bufferedAhead read stays inside this body, so the ~4Hz dependency
        // registers on the leaf. SignalRowView takes plain values and observes
        // nothing, so passing them across registers nothing on the parent.
        let ahead = app.player.bufferedAhead
        SignalRowView(label: SignalReadout.bufferedLabel,
                      value: SignalReadout.buffered(secondsAhead: ahead),
                      isUnknown: !(ahead > 0))
    }
}
