import SwiftUI

/// Global catalog search (catalog.search). The "/" shortcut lands here with
/// the field focused.
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(\.theme) private var theme

    @State private var query = ""
    @State private var searchedQuery: String?
    @State private var results: SearchModel?
    @State private var searching = false
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search shows, artists, songs", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .submitLabel(.search)
                .onSubmit { Task { await run() } }
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)

            resultsBody
        }
        .navigationTitle("Search")
        .onAppear {
            // Auto-focus serves the Mac's "/" flow. On iOS it would slam the
            // keyboard over the tab bar the moment the tab opens.
            #if os(macOS)
            fieldFocused = true
            #endif
        }
        .onChange(of: ui.searchFocusTick) { fieldFocused = true }
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            #if os(iOS)
            // Escape hatch while the keyboard is up (no tap-outside dismissal
            // in SwiftUI, and the tab bar is hidden behind the keyboard).
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
            }
            #endif
        }
    }

    @ViewBuilder
    private var resultsBody: some View {
        if searching {
            Spacer()
            ProgressView()
            Spacer()
        } else if let error {
            ContentUnavailableView(
                "Search failed",
                systemImage: "exclamationmark.triangle",
                description: Text(error))
        } else if let results, let searchedQuery {
            if results.isEmpty {
                ContentUnavailableView.search(text: searchedQuery)
            } else {
                resultsList(results)
            }
        } else {
            ContentUnavailableView(
                "Search the nugs catalog",
                systemImage: "magnifyingglass",
                description: Text("Shows, studio releases, artists, and songs."))
        }
    }

    private func resultsList(_ results: SearchModel) -> some View {
        List {
            if !results.artists.isEmpty {
                Section {
                    ForEach(results.artists) { artist in
                        NavigationLink(value: Route.artist(artist)) {
                            Label(artist.name, systemImage: "music.mic")
                        }
                        .themedListRow()
                        .contextMenu {
                            let fav = app.favorites.isArtistFavorited(artist.id)
                            Button(fav ? "Remove from Favorites" : "Add to Favorites",
                                   systemImage: fav ? "star.slash" : "star") {
                                app.favorites.toggleArtist(id: artist.id, name: artist.name)
                            }
                        }
                    }
                } header: {
                    sectionHeader("Artists")
                }
            }
            ForEach(results.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        row(item)
                            .themedListRow()
                    }
                } header: {
                    sectionHeader(section.header)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.palette.base)
    }

    private func sectionHeader(_ text: String) -> some View {
        let condensed = theme.caps.contains(.condensedHeaders)
        return Text(condensed ? text.uppercased() : text)
            .font(theme.type.section(12))
            .tracking(condensed ? 1.5 : 0)
            .foregroundStyle(theme.palette.textSecondary)
    }

    @ViewBuilder
    private func row(_ item: SearchModel.Item) -> some View {
        switch item.kind {
        case .container(let id):
            NavigationLink(value: Route.album(id: id, title: item.venue ?? item.name)) {
                HStack(spacing: 10) {
                    if let date = item.dateText {
                        Text(date)
                            .font(theme.type.numeric(12))
                            .foregroundStyle(theme.palette.textSecondary)
                        Text(item.venue ?? item.name).lineLimit(1)
                    } else {
                        Text(item.name).lineLimit(1)
                        if let artist = item.artistName {
                            Text("— \(artist)").foregroundStyle(theme.palette.textSecondary).lineLimit(1)
                        }
                    }
                }
            }
            .contextMenu {
                let fav = app.favorites.isShowFavorited(id)
                Button(fav ? "Remove from Favorites" : "Add to Favorites",
                       systemImage: fav ? "star.slash" : "star") {
                    app.favorites.toggleShow(id: id, title: item.venue ?? item.name,
                                             artistName: item.artistName ?? "",
                                             dateText: item.dateText, venue: item.venue,
                                             imageURL: nil)
                }
            }
        case .track(let trackId):
            // A direct song hit — playable in place, like the web port.
            let single = [QueueTrack(
                trackId: trackId, title: item.name,
                artist: item.artistName, show: nil)]
            HStack {
                Button {
                    app.player.play(single)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.caption)
                        Text(item.name)
                        if let artist = item.artistName {
                            Text("— \(artist)").foregroundStyle(theme.palette.textSecondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    if app.player.playNext(single) { ui.showToast("Playing next") }
                } label: {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                }
                .buttonStyle(.borderless)
                .help("Play next")
                .accessibilityLabel("Play \(item.name) next")
                Button {
                    if app.player.enqueue(single) { ui.showToast("Added to queue") }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add to queue")
                .accessibilityLabel("Add \(item.name) to queue")
            }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            let json = try await app.client.search(q)
            results = Catalog.search(from: json)
            searchedQuery = q
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
