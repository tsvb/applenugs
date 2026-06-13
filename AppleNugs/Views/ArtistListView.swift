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

    private var filtered: [ArtistEntry] {
        guard !filter.isEmpty else { return artists }
        return artists.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        List(filtered) { artist in
            NavigationLink(value: Route.artist(artist)) {
                ArtistRow(entry: artist)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.palette.base)
        .navigationTitle("Artists")
        .searchable(text: $filter, placement: .toolbar, prompt: "Filter artists")
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
