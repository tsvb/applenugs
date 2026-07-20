import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Offline shows straight from the download manifest — playable with no
/// network, deletable by swipe (and right-click on the Mac). Rows build their
/// queue from the manifest so nothing here touches the catalog API. Shared by
/// the iOS Library tab, the macOS Downloads sidebar item, and both platforms'
/// Listen-Offline escape hatch.
struct DownloadsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if app.downloads.manifest.shows.isEmpty {
                ContentUnavailableView {
                    Label("Nothing downloaded", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download a show from its page to keep it for offline listening.")
                }
            } else {
                VStack(spacing: 0) {
                    List {
                        ForEach(app.downloads.manifest.shows, id: \.containerID) { show in
                            row(show)
                                .themedListRow()
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)

                    storageFooter
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.base)
    }

    /// "N shows · X GB" — the manifest is the single source of truth, so the
    /// line always matches what the list renders.
    private var storageFooter: some View {
        let count = app.downloads.manifest.shows.count
        let size = ByteCountFormatter.string(
            fromByteCount: app.downloads.manifest.totalBytes, countStyle: .file)
        return Text("\(count) \(count == 1 ? "show" : "shows") · \(size)")
            .font(theme.type.numeric(11))
            .foregroundStyle(theme.palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private func row(_ show: DownloadedShow) -> some View {
        Button {
            play(show)
        } label: {
            HStack(spacing: 12) {
                MonogramTile(text: show.artist ?? show.title ?? "?", size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(show.title ?? "Untitled show")
                        .font(theme.type.title(15))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(2)
                    Text(subtitle(show))
                        .font(theme.type.numeric(11))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                app.downloads.delete(containerID: show.containerID)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        #if os(macOS)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [app.downloads.showDirectory(containerID: show.containerID)])
            }
            Button("Remove Download", role: .destructive) {
                app.downloads.delete(containerID: show.containerID)
            }
        }
        #endif
        .accessibilityLabel("\(show.title ?? "show"), play offline")
    }

    private func subtitle(_ show: DownloadedShow) -> String {
        var parts: [String] = []
        if let artist = show.artist { parts.append(artist) }
        parts.append("\(show.tracks.count) tracks")
        parts.append(ByteCountFormatter.string(
            fromByteCount: show.totalBytes, countStyle: .file))
        return parts.joined(separator: " · ")
    }

    private func play(_ show: DownloadedShow) {
        let queue = show.tracks.map {
            QueueTrack(trackId: $0.trackId, title: $0.title,
                       artist: $0.artist ?? show.artist, show: show.title,
                       artworkPath: show.artworkPath, showId: show.containerID)
        }
        app.player.play(queue)
    }
}
