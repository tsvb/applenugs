import SwiftUI

/// The Library tab: Favorites and Downloads under one segmented control.
struct LibraryView: View {
    @Environment(\.theme) private var theme

    private enum Segment: String, CaseIterable, Identifiable {
        case favorites = "Favorites"
        case downloads = "Downloads"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .favorites

    var body: some View {
        VStack(spacing: 0) {
            Picker("Library section", selection: $segment) {
                ForEach(Segment.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch segment {
            case .favorites: FavoritesView()
            case .downloads: DownloadsView()
            }
        }
        .background(theme.palette.base)
        // FavoritesView titles itself; this covers the Downloads segment so
        // the header tracks the visible content.
        .navigationTitle(segment == .favorites ? "Favorites" : "Downloads")
    }
}

/// Offline shows straight from the download manifest — playable with no
/// network, deletable by swipe. Rows build their queue from the manifest so
/// nothing here touches the catalog API.
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
                List {
                    ForEach(app.downloads.manifest.shows, id: \.containerID) { show in
                        row(show)
                            .themedListRow()
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.base)
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
