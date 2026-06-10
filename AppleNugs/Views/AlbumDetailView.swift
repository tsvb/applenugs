import SwiftUI

/// One show / studio release (catalog.container): header, play actions,
/// show notes, and the track list grouped by set with encore labels.
struct AlbumDetailView: View {
    let albumId: String
    var titleHint: String?

    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui

    @State private var album: AlbumDetailModel?
    @State private var error: String?

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
        .navigationTitle(album?.title ?? titleHint ?? "Album")
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
        VStack(alignment: .leading, spacing: 4) {
            Text(album.title).font(.title.weight(.semibold))
            Text(album.artistName).font(.title3).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if let date = album.dateText {
                    Text(date).monospacedDigit()
                }
                if let venue = album.venue {
                    Text(venue)
                }
                if let runtime = album.totalRunningTime {
                    Text("\(runtime) · \(album.tracks.count) tracks")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }

    private func actions(_ album: AlbumDetailModel) -> some View {
        HStack(spacing: 8) {
            Button {
                app.player.play(queueTracks(album))
            } label: {
                Label("Play all", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(album.tracks.isEmpty)

            Button {
                if app.player.playNext(queueTracks(album)) {
                    ui.showToast("Playing next")
                }
            } label: {
                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .disabled(album.tracks.isEmpty)

            Button {
                if app.player.enqueue(queueTracks(album)) {
                    ui.showToast("Added to queue")
                }
            } label: {
                Label("Queue", systemImage: "plus")
            }
            .disabled(album.tracks.isEmpty)
        }
    }

    @ViewBuilder
    private func notes(_ album: AlbumDetailModel) -> some View {
        let text = album.notesHTML.map(Self.plainText(fromHTML:)).joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            DisclosureGroup("Show notes") {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                    .font(.headline)
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
                       artist: album.artistName, show: album.title)
        }
    }

    private func load() async {
        do {
            let json = try await app.client.album(id: albumId)
            album = Catalog.album(from: json, id: albumId)
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

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: play) {
                HStack(spacing: 8) {
                    Text("\(track.trackNum).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    Text(track.title)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    Spacer(minLength: 8)
                    if let duration = track.durationText {
                        Text(duration)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
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
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 5))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Play", action: play)
            Button("Play Next", action: playNext)
            Button("Add to Queue", action: enqueue)
        }
    }
}
