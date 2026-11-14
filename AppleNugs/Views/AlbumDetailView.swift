import SwiftUI

/// One show / studio release (catalog.container): header, play actions,
/// show notes, and the track list grouped by set with encore labels.
struct AlbumDetailView: View {
    let albumId: String
    var titleHint: String?

    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(\.theme) private var theme

    @State private var album: AlbumDetailModel?
    @State private var error: String?
    /// Parsed once when the album loads — HTML parsing is too heavy to run
    /// on every body evaluation.
    @State private var notesText = ""

    var body: some View {
        ScrollView {
            if let album {
                VStack(alignment: .leading, spacing: 14) {
                    header(album)
                    actions(album)
                    notes(album)
                    trackList(album)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.palette.base)
        .navigationTitle(album?.title ?? titleHint ?? "Album")
        .compactNavigationTitle()
        .overlay {
            if album == nil && error == nil {
                ProgressView()
            } else if let error {
                ContentUnavailableView(
                    "Couldn't load this show",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            }
        }
        .task(id: albumId) { await load() }
    }

    // --- sections ---------------------------------------------------------------

    private func header(_ album: AlbumDetailModel) -> some View {
        // `.show-ios` sets the text against the cover's bottom edge.
        HStack(alignment: .bottom, spacing: 14) {
            if album.imageURL != nil {
                CoverArt(url: album.imageURL)
                    .frame(width: 110)
            }
            headerText(album)
        }
    }

    /// `.show-ios`: the meta stacks instead of sitting side by side
    /// (where a city wrapped into a ragged column of its own). Title, then
    /// the artist as a snow link, then "date · venue" on one truncating line,
    /// then "runtime · N tracks", both in slush 13.5. A missing field drops
    /// out rather than leaving a blank line.
    private func headerText(_ album: AlbumDetailModel) -> some View {
        let place = [album.dateText, album.venue].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            Text(album.title)
                .font(theme.type.hero(26))
                .foregroundStyle(theme.palette.textPrimary)
            artistLink(album.artistName)
            VStack(alignment: .leading, spacing: 2) {
                if !place.isEmpty {
                    Text(place)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let runtime = album.totalRunningTime {
                    Text("\(runtime) · \(album.tracks.count) tracks")
                        .lineLimit(1)
                }
            }
            .font(theme.type.body(13.5))
            .foregroundStyle(theme.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The artist, heavy 15 in snow, opening the artist page through the same
    /// `x-applenugs-meta://` route the now-playing links use (the scene
    /// root's `.nowPlayingMetaLinks` resolves the name; a miss is a toast).
    /// A `.link` run in a `Text`, like `NowPlayingMetaText`, carrying its snow
    /// explicitly so SwiftUI doesn't paint it in the link tint.
    private func artistLink(_ name: String) -> some View {
        var run = AttributedString(name)
        run[AttributeScopes.FoundationAttributes.LinkAttribute.self] =
            NowPlayingMetaLine.Target.artist(name: name).url
        run[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = theme.palette.textPrimary
        return Text(run)
            .font(theme.type.title(15))
            .lineLimit(1)
    }

    /// Play all is the one snow primary and the rest are frost rings — round
    /// icon buttons on iPhone (`.actrow .ib`), frost-outlined labeled buttons
    /// on the Mac.
    private func actions(_ album: AlbumDetailModel) -> some View {
        HStack(spacing: 8) {
            playAllButton(album)

            Button {
                if app.player.playNext(queueTracks(album)) {
                    ui.showToast("Playing next")
                }
            } label: {
                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .disabled(album.tracks.isEmpty)
            .yetiPageAction()

            Button {
                if app.player.enqueue(queueTracks(album)) {
                    ui.showToast("Added to queue")
                }
            } label: {
                Label("Queue", systemImage: "plus")
            }
            .disabled(album.tracks.isEmpty)
            .yetiPageAction()

            // `.actrow .grow`: Save and Download sit at the trailing edge.
            Spacer(minLength: 0)

            // Five labeled buttons overflow iPhone widths; the secondary
            // actions go icon-only there (labels stay for accessibility).
            Group {
                saveButton(album)

                // A child view, not a builder method: download progress
                // mutates DownloadStore.trackProgress at up to ~1% steps per
                // track, and with @Observable the dependency registers on
                // whichever body READ it — a method would pin it to this
                // whole screen (re-grouping the track list per update).
                ShowDownloadButton(albumId: albumId, album: album)
            }
            #if os(iOS)
            .labelStyle(.iconOnly)
            #endif
        }
    }

    private func playAllButton(_ album: AlbumDetailModel) -> some View {
        Button {
            app.player.play(queueTracks(album))
        } label: {
            Label("Play all", systemImage: "play.fill")
        }
        .disabled(album.tracks.isEmpty)
        .buttonStyle(.yetiPrimary)
    }

    /// Offline download state machine: idle → live progress → downloaded
    /// (tap to remove) / failed (tap to retry). Shared by both platforms.
    /// A separate View so the live-progress @Observable dependency
    /// invalidates only this button, never the surrounding screen.
    private struct ShowDownloadButton: View {
        let albumId: String
        let album: AlbumDetailModel

        @Environment(AppModel.self) private var app
        @Environment(\.theme) private var theme
        @State private var confirmRemoveDownload = false
        @State private var downloadFailureShown = false

        var body: some View {
            switch app.downloads.state(for: albumId) {
            case .none:
                Button {
                    app.downloads.download(downloadRequest())
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .disabled(album.tracks.isEmpty)
                .yetiPageAction()

            case .downloading(let fraction):
                HStack(spacing: 6) {
                    ProgressView(value: fraction)
                        // A download moves through time: foil, explicitly,
                        // against the snow root tint.
                        .tint(theme.palette.accent)
                        .frame(width: 44)
                        .accessibilityLabel("Downloading show")
                        .accessibilityValue("\(Int(fraction * 100)) percent")
                    Button {
                        app.downloads.delete(containerID: albumId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel download")
                }

            case .downloaded:
                Button {
                    confirmRemoveDownload = true
                } label: {
                    Label("Downloaded", systemImage: "arrow.down.circle.fill")
                }
                .yetiDownloadedAction()
                .confirmationDialog("Remove this show's downloaded files?",
                                    isPresented: $confirmRemoveDownload,
                                    titleVisibility: .visible) {
                    Button("Remove Download", role: .destructive) {
                        app.downloads.delete(containerID: albumId)
                    }
                }

            case .failed(let message):
                // Tooltips don't exist on touch — the tap explains and retries.
                Button {
                    downloadFailureShown = true
                } label: {
                    Label("Download failed", systemImage: "exclamationmark.arrow.circlepath")
                }
                .yetiPageAction()
                .alert("Download failed", isPresented: $downloadFailureShown) {
                    Button("Retry") { app.downloads.download(downloadRequest()) }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(message)
                }
            }
        }

        private func downloadRequest() -> ShowDownloadRequest {
            ShowDownloadRequest(
                containerID: albumId,
                title: album.title,
                artist: album.artistName,
                artworkPath: album.imagePath,
                tracks: album.tracks.map {
                    .init(trackId: $0.id, title: $0.title,
                          artist: album.artistName, durationText: $0.durationText)
                })
        }
    }

    private func saveButton(_ album: AlbumDetailModel) -> some View {
        let fav = app.favorites.isShowFavorited(albumId)
        return Button {
            app.favorites.toggleShow(id: albumId, title: album.title,
                                     artistName: album.artistName,
                                     dateText: album.dateText, venue: album.venue,
                                     imageURL: album.imageURL?.absoluteString)
        } label: {
            Label(fav ? "Saved" : "Save", systemImage: fav ? "star.fill" : "star")
        }
        // A saved show isn't time moving: the star is snow (the frost ring's
        // glyph), never accent.
        .yetiPageAction()
        .help(fav ? "Remove from Favorites" : "Save show to Favorites")
    }

    @ViewBuilder
    private func notes(_ album: AlbumDetailModel) -> some View {
        let text = notesText
        if !text.isEmpty {
            DisclosureGroup("Show notes") {
                Text(text)
                    .font(theme.type.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func trackList(_ album: AlbumDetailModel) -> some View {
        let queue = queueTracks(album)
        let groups = Dictionary(grouping: Array(album.tracks.enumerated()), by: { $0.element.setNum })
            .sorted { $0.key < $1.key }
        let showHeaders = groups.count > 1

        ForEach(groups, id: \.key) { setNum, rows in
            if showHeaders {
                Text(TrackEntry.setLabel(setNum))
                    .font(theme.type.section(15))
                    // `.setname`: set headers are the barker's heavy slush,
                    // sentence case.
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(.top, 6)
            }
            VStack(spacing: 0) {
                ForEach(rows, id: \.element.id) { queueIndex, track in
                    TrackRow(
                        track: track,
                        play: { app.player.play(queue, startAt: queueIndex) },
                        playNext: {
                            if app.player.playNext([queue[queueIndex]]) {
                                ui.showToast("Playing next")
                            }
                        },
                        enqueue: {
                            if app.player.enqueue([queue[queueIndex]]) {
                                ui.showToast("Added to queue")
                            }
                        },
                        isCurrent: app.player.current?.trackId == track.id)
                }
            }
        }
    }

    // --- helpers ----------------------------------------------------------------

    /// Flat queue list in performance order so autoplay traverses
    /// Set 1 → Set 2 → Encore correctly.
    private func queueTracks(_ album: AlbumDetailModel) -> [QueueTrack] {
        album.tracks.map {
            QueueTrack(trackId: $0.id, title: $0.title,
                       artist: album.artistName, show: album.title,
                       artworkPath: album.imagePath, showId: album.id)
        }
    }

    private func load() async {
        do {
            let json = try await app.client.album(id: albumId)
            album = Catalog.album(from: json, id: albumId)
            notesText = (album?.notesHTML ?? []).map(Self.plainText(fromHTML:))
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Show notes arrive as HTML strings; render them as plain text.
    private static func plainText(fromHTML html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil)
        else { return html }
        return attributed.string
    }
}

/// One row in the track list: number, title, duration, hover actions.
private struct TrackRow: View {
    let track: TrackEntry
    let play: () -> Void
    let playNext: () -> Void
    let enqueue: () -> Void
    let isCurrent: Bool

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var hovering = false

    /// Touch has no hover: on iOS the per-row actions are always visible
    /// (the context menu still offers them via long-press as well).
    private var rowActionsVisible: Bool {
        #if os(iOS)
        true
        #else
        hovering
        #endif
    }

    /// The setlist rows (`.setlist li`, `.setlist.ios li`): 44pt on iPhone,
    /// 36pt on the Mac, each ruled in frost.
    private var rowHeight: CGFloat {
        #if os(iOS)
        44
        #else
        36
        #endif
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: play) {
                HStack(spacing: 8) {
                    numberColumn
                    Text(track.title)
                        .font(theme.type.body(15))
                        .fontWeight(isCurrent ? .heavy : .regular)
                        .foregroundStyle(isCurrent ? theme.palette.playState : theme.palette.textPrimary)
                    Spacer(minLength: 8)
                    if let duration = track.durationText {
                        Text(duration)
                            .font(theme.type.numeric(12))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                Button(action: playNext) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                }
                .help("Play next")
                Button(action: enqueue) {
                    Image(systemName: "plus")
                }
                .help("Add to queue")
            }
            .buttonStyle(.borderless)
            // `.setlist.ios li .q`: lamp-off idle (the snow root tint would
            // print them louder than the title).
            .tint(theme.palette.textIdle)
            .opacity(rowActionsVisible ? 1 : 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(minHeight: rowHeight)
        .background {
            if isCurrent {
                // The playing row's faint sale wash (`.setlist li.playing`),
                // the Mac setlist rule brought to iPhone too.
                LinearGradient(stops: [.init(color: theme.palette.playState.opacity(0.07), location: 0),
                                       .init(color: theme.palette.playState.opacity(0), location: 0.7)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .background(hovering ? theme.palette.raised : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.palette.hairline).frame(height: 1)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Play", action: play)
            Button("Play Next", action: playNext)
            Button("Add to Queue", action: enqueue)
        }
    }

    /// The 28pt number column. The playing row shows the 20pt `RowSticker`
    /// in place of its number (the stage-c spec's row-sticker table), and
    /// EVERY row's column is 20pt tall, so the sticker moving to another track
    /// never resizes a row. `isPlaying` is read only on the playing row, so a
    /// pause re-renders that one row, not the show page.
    private var numberColumn: some View {
        Group {
            if isCurrent {
                RowSticker(isPlaying: app.player.isPlaying, size: .s20)
            } else {
                Text("\(track.trackNum)")
                    .font(theme.type.numeric(12))
                    .foregroundStyle(theme.palette.textIdle)
            }
        }
        .frame(width: 28, height: RowSticker.Size.s20.diameter, alignment: .trailing)
    }
}
