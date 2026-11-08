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

    /// False when the panel sits BESIDE the full-screen player (iPhone Duo's
    /// `NowPlayingArrangement`), where the "Now" section would only repeat the
    /// player next to it. Fixed per instance — never toggled per tick — so the
    /// Signal section's constant-row-set rule is untouched.
    var showsNowPlaying: Bool = true

    /// The "Clear" button asks first, like the ⋯ menu (ruling P2).
    @State private var confirmingClear = false

    private var player: PlayerService { app.player }
    private var plainVoice: Bool { theme.caps.contains(.plainVoice) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if showsNowPlaying {
                    nowPlayingSection
                } else if let error = player.playbackError {
                    // Beside the player, the "Now" section is dropped — but on
                    // iOS it is the only place a playback error renders, and
                    // the player's own queue button (the old route to it) is
                    // hidden while this column shows. Keep the error alone.
                    // Conditional for the same reason as the Mac branch below:
                    // a real failure is rare, not per-tick churn.
                    PlaybackErrorLine(message: error)
                }
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
    /// out as letterpress small caps. Under `.plainVoice` they are the design's
    /// barker headers: a real section header in snow ("Here it comes"), not a
    /// small gray label.
    private func sectionHeader(_ text: String) -> some View {
        let condensed = theme.caps.contains(.condensedHeaders)
        let plain = theme.caps.contains(.plainVoice)
        return Text(condensed ? text.uppercased() : text)
            .font(theme.type.section(plain ? 17 : 12))
            .tracking(condensed ? 1.6 : 0)
            .foregroundStyle(plain ? theme.palette.textPrimary : theme.palette.textSecondary)
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
                PlaybackErrorLine(message: error)
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
                    .font(theme.type.title(theme.caps.contains(.plainVoice) ? 20 : 15))
                    .lineLimit(1)
                    .truncationMode(.tail)
                NowPlayingMetaText(track: track, fields: [.artist])
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                NowPlayingMetaText(track: track, fields: [.show])
                    .font(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // A leaf view: the 4Hz currentTime dependency registers
                // here, not on the whole inspector (whose queue list
                // would otherwise re-diff every tick).
                ElapsedTimeLine()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.clear.artWash(theme.washStyle, color: artColor))
            if let error = player.playbackError {
                PlaybackErrorLine(message: error)
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
                if theme.caps.contains(.stickers) {
                    // The price sticker rides the quality header. This whole
                    // section is already gated on `player.current`, and the
                    // sticker holds its frame when a known lossy pick hides
                    // it, so the header never changes height.
                    HStack {
                        sectionHeader(theme.copy.dashHeaders.quality)
                        Spacer(minLength: 8)
                        PriceSticker(player: player, size: Self.headerStickerSize)
                    }
                } else {
                    sectionHeader(theme.copy.dashHeaders.quality)
                }
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

    /// The design draws the Mac inspector's sticker at 44pt and the iOS
    /// sheet's at 38pt (the nearest size the sticker comes in is 40).
    #if os(macOS)
    private static let headerStickerSize: PriceSticker.Size = .s44
    #else
    private static let headerStickerSize: PriceSticker.Size = .s40
    #endif

    // --- queue -------------------------------------------------------------------

    @ViewBuilder
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader(theme.copy.dashHeaders.upNext)
                Spacer()
                if !player.queue.isEmpty {
                    Button("Clear") { confirmingClear = true }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                        .clearQueueConfirmation(isPresented: $confirmingClear) {
                            player.clear()
                        }
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

    /// The row's title. Yeti (`.plainVoice`) prints the playing row heavy in
    /// sale yellow (`activeEmphasis` = `playState` on a static theme); every
    /// other theme keeps the inherited text color, untouched.
    @ViewBuilder
    private func queueTitle(_ track: QueueTrack, isCurrent: Bool) -> some View {
        let title = Text(track.title ?? "Unknown track")
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.tail)
        if plainVoice && isCurrent {
            title
                .fontWeight(.heavy)
                .foregroundStyle(theme.activeEmphasis(art: artColor))
        } else {
            title
                .fontWeight(isCurrent ? .semibold : .regular)
        }
    }

    private func queueRow(_ i: Int, _ track: QueueTrack) -> some View {
        HStack(spacing: 6) {
            Button {
                player.jump(to: i)
            } label: {
                HStack(spacing: 6) {
                    if i == player.index {
                        // `.stickers` first: Yeti carries `.equalizerRows` too,
                        // and its queue slot takes the static row sticker
                        // instead of the bounce (spec's EqualizerBars table).
                        if theme.caps.contains(.stickers) {
                            RowSticker(isPlaying: player.isPlaying, size: .s16)
                                .frame(width: 16)
                        } else if theme.caps.contains(.equalizerRows) {
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
                    queueTitle(track, isCurrent: i == player.index)
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

/// A playback error, as the dashboard shows it. Red with a warning triangle in
/// every theme but Yeti, which says it in snow with a slush mark on a shelf
/// block (`.plainVoice`: errors are said, not alarmed). Reads no player state.
private struct PlaybackErrorLine: View {
    @Environment(\.theme) private var theme

    let message: String

    /// The offline-expiry error's "why" line (`OfflineAccessPolicy.detail`),
    /// on every theme. Part of this conditional error block — never a Signal
    /// row, so the Signal section's constant row set is untouched.
    private var detail: String? { OfflineAccessPolicy.detail(forError: message) }

    var body: some View {
        if theme.caps.contains(.plainVoice) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.palette.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .foregroundStyle(theme.palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.palette.hairline, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .foregroundStyle(theme.palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
    }
}

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
        // up. `--:--` is the clock placeholder used by MiniPlayerScrubTrack.
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
