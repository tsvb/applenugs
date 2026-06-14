import SwiftUI

/// Artist landing page (catalog.containersAll): studio releases as a cover
/// grid, live shows grouped by year (newest expanded). Unlike the web port,
/// pagination is wired — "Load more" pulls the next 100 containers.
struct ArtistDetailView: View {
    let artist: ArtistEntry

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var containers: [ContainerSummary] = []
    @State private var loading = false
    @State private var error: String?
    @State private var canLoadMore = false
    @State private var expandedYears: Set<Int> = []

    private static let pageSize = 100

    private var releases: [ContainerSummary] { containers.filter { !$0.isLiveShow } }
    private var shows: [ContainerSummary] { containers.filter(\.isLiveShow) }

    private var showsByYear: [(year: Int, shows: [ContainerSummary])] {
        Dictionary(grouping: shows, by: \.year)
            .sorted { $0.key > $1.key }
            .map { (year: $0.key, shows: $0.value.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if !releases.isEmpty {
                    sectionTitle("Releases")
                    releaseGrid
                }

                if !shows.isEmpty {
                    sectionTitle("Shows")
                    ForEach(showsByYear, id: \.year) { group in
                        yearSection(group.year, group.shows)
                    }
                }

                if canLoadMore {
                    Button("Load more shows") {
                        Task { await load(reset: false) }
                    }
                    .disabled(loading)
                }

                if loading && !containers.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.base)
        .navigationTitle(artist.name)
        .overlay {
            if loading && containers.isEmpty {
                ProgressView()
            } else if let error, containers.isEmpty {
                ContentUnavailableView(
                    "Couldn't load shows",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            }
        }
        .task(id: artist.id) { await load(reset: true) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            followButton
            if !releases.isEmpty {
                Text("^[\(releases.count) release](inflect: true)")
            }
            if !shows.isEmpty {
                Text("^[\(shows.count) show](inflect: true)")
            }
        }
        .font(theme.type.numeric(12))
        .foregroundStyle(theme.palette.textSecondary)
    }

    private var followButton: some View {
        let fav = app.favorites.isArtistFavorited(artist.id)
        return Button {
            app.favorites.toggleArtist(id: artist.id, name: artist.name)
        } label: {
            Label(fav ? "Following" : "Follow", systemImage: fav ? "star.fill" : "star")
                .font(theme.type.body(12))
        }
        .buttonStyle(.bordered)
        .tint(fav ? theme.palette.accent : theme.palette.textSecondary)
        .help(fav ? "Unfollow artist" : "Follow artist")
    }

    private func sectionTitle(_ text: String) -> some View {
        let condensed = theme.caps.contains(.condensedHeaders)
        return Text(condensed ? text.uppercased() : text)
            .font(theme.type.section(17))
            .tracking(condensed ? 1.4 : 0)
            .foregroundStyle(theme.palette.textPrimary)
    }

    private var releaseGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 14)],
                  alignment: .leading, spacing: 14) {
            ForEach(releases) { release in
                NavigationLink(value: Route.album(id: release.id, title: release.title)) {
                    VStack(alignment: .leading, spacing: 6) {
                        CoverArt(url: release.imageURL)
                        Text(release.title)
                            .font(theme.type.body(13))
                            .foregroundStyle(theme.palette.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                .help(release.title)
            }
        }
    }

    private func yearSection(_ year: Int, _ shows: [ContainerSummary]) -> some View {
        DisclosureGroup(isExpanded: yearBinding(year)) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(shows) { show in
                    NavigationLink(value: Route.album(id: show.id, title: show.venue ?? show.title)) {
                        HStack(spacing: 10) {
                            Text(show.dateText ?? "")
                                .font(theme.type.numeric(12))
                                .foregroundStyle(theme.palette.textSecondary)
                                .frame(width: 86, alignment: .leading)
                            Text(show.venue ?? show.title)
                                .font(theme.type.body(13))
                                .foregroundStyle(theme.palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
            }
            .padding(.leading, 4)
        } label: {
            HStack {
                Text(String(year)).font(theme.type.section(16))
                Text("^[\(shows.count) show](inflect: true)")
                    .font(theme.type.numeric(12))
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
    }

    private func yearBinding(_ year: Int) -> Binding<Bool> {
        Binding(
            get: { expandedYears.contains(year) },
            set: { open in
                if open { expandedYears.insert(year) } else { expandedYears.remove(year) }
            })
    }

    private func load(reset: Bool) async {
        if reset {
            containers = []
            expandedYears = []
            canLoadMore = false
        }
        loading = true
        defer { loading = false }
        do {
            let json = try await app.client.artistShows(
                id: artist.id, offset: containers.count + 1, limit: Self.pageSize)
            let page = Catalog.containers(from: json)
            containers += page
            canLoadMore = page.count >= Self.pageSize
            error = nil
            // Expand only the newest year by default, like the web port.
            if reset, let newest = showsByYear.first?.year {
                expandedYears = [newest]
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Square cover-art thumbnail with a placeholder while loading / on miss.
struct CoverArt: View {
    let url: URL?

    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    default:
                        placeholder.overlay(ProgressView().controlSize(.small))
                    }
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(theme.palette.raised)
            .overlay(Image(systemName: "music.note").foregroundStyle(theme.palette.accent.opacity(0.7)))
    }
}
