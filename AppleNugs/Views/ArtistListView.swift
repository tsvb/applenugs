import SwiftUI

/// Full artist list landing page (catalog.artists), with a local filter.
/// The list is cached on AppModel for the app lifetime.
struct ArtistListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var artists: [ArtistEntry] = []
    @State private var filter = ""
    @State private var loading = false
    @State private var error: String?
    @FocusState private var filterFocused: Bool

    private var filtered: [ArtistEntry] {
        guard !filter.isEmpty else { return artists }
        return artists.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    /// The catalog is hundreds deep, so group it into A–Z sections (numbers and
    /// symbols collected under "#", sorted first) and let the sticky letter
    /// headers carry the rhythm instead of a divider under every row.
    private var sections: [(letter: String, artists: [ArtistEntry])] {
        let grouped = Dictionary(grouping: filtered) { artist -> String in
            guard let first = artist.name.first else { return "#" }
            let s = String(first).uppercased()
            return s.first!.isLetter ? s : "#"
        }
        return grouped
            .map { (letter: $0.key,
                    artists: $0.value.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }) }
            .sorted { lhs, rhs in
                if lhs.letter == "#" { return true }
                if rhs.letter == "#" { return false }
                return lhs.letter < rhs.letter
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterField
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

            List {
                ForEach(sections, id: \.letter) { section in
                    Section {
                        ForEach(section.artists) { artist in
                            NavigationLink(value: Route.artist(artist)) {
                                Text(artist.name)
                                    .font(theme.type.body(14))
                                    .foregroundStyle(theme.palette.textPrimary)
                                    .padding(.vertical, 1)
                            }
                            .listRowSeparator(.hidden)
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
                        Text(section.letter)
                            .font(theme.type.section(12))
                            .tracking(theme.caps.contains(.condensedHeaders) ? 1.6 : 0.5)
                            .foregroundStyle(theme.palette.accent)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(theme.palette.base)
        .navigationTitle("Artists")
        .overlay {
            if loading {
                ProgressView()
            } else if let error {
                ContentUnavailableView(
                    "Couldn't load artists",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if filtered.isEmpty && !artists.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
        .task { await load() }
    }

    /// A compact, contextual filter that lives just above the list instead of
    /// stretching across the toolbar into the inspector.
    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.palette.textSecondary)
            TextField("Filter artists", text: $filter)
                .textFieldStyle(.plain)
                .font(theme.type.body(13))
                .foregroundStyle(theme.palette.textPrimary)
                .focused($filterFocused)
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.palette.raised)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(filterFocused ? theme.palette.accent.opacity(0.7) : theme.palette.hairline,
                                      lineWidth: 1)
                }
        }
        .frame(maxWidth: 340)
    }

    private func load() async {
        guard artists.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            artists = try await app.artists()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
