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

    /// Yeti (`.plainVoice`): the `.alist` rows of the first sheet's "Pill over
    /// an artist list" — names only (Tim's ruling 2: no show counts), heavy
    /// 17 on frost rules, under heavy slush letter headers.
    private var plainVoice: Bool { theme.caps.contains(.plainVoice) }

    /// A–Z sections, derived state: filtering + grouping + locale-aware
    /// sorting over a catalog hundreds deep is too heavy to redo on every
    /// body evaluation (favorites toggles, theme switches, toasts) — it
    /// rebuilds only when the inputs actually change (load, keystroke).
    @State private var sections: [(letter: String, artists: [ArtistEntry])] = []

    /// The catalog is hundreds deep, so group it into A–Z sections (numbers and
    /// symbols collected under "#", sorted first) and let the sticky letter
    /// headers carry the rhythm instead of a divider under every row.
    private func rebuildSections() {
        let filtered = filter.isEmpty
            ? artists
            : artists.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        let grouped = Dictionary(grouping: filtered) { artist -> String in
            // Trim first: catalog names occasionally carry leading whitespace,
            // which would misfile them under "#".
            guard let first = artist.name.trimmingCharacters(in: .whitespaces).first else {
                return "#"
            }
            let s = String(first).uppercased()
            return s.first!.isLetter ? s : "#"
        }
        sections = grouped
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
                                    .font(plainVoice ? theme.type.title(17) : theme.type.body(14))
                                    .foregroundStyle(theme.palette.textPrimary)
                                    .lineLimit(plainVoice ? 1 : nil)
                                    .padding(.vertical, plainVoice ? 4 : 1)
                            }
                            // Yeti rules each row in frost (`.alist li`); the
                            // other themes let the letter headers carry it.
                            .listRowSeparator(plainVoice ? .visible : .hidden)
                            .listRowSeparatorTint(plainVoice ? theme.palette.hairline : nil)
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
                        if plainVoice {
                            // `.letter`: heavy slush, untracked. A header isn't
                            // time moving, so it isn't foil.
                            Text(section.letter)
                                .font(theme.type.section(17))
                                .foregroundStyle(theme.palette.textSecondary)
                        } else {
                            Text(section.letter)
                                .font(theme.type.section(12))
                                .tracking(theme.caps.contains(.condensedHeaders) ? 1.6 : 0.5)
                                .foregroundStyle(theme.palette.accent)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .reportsScrollForPillDuck()
        }
        .background(theme.palette.base)
        .navigationTitle("Artists")
        .compactNavigationTitle()
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            #if os(iOS)
            // Escape hatch while the keyboard covers the tab bar (SwiftUI
            // has no tap-outside dismissal) — same treatment as SearchView.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { filterFocused = false }
            }
            #endif
        }
        .overlay {
            if loading {
                ProgressView()
            } else if let error {
                ContentUnavailableView(
                    "Couldn't load artists",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if sections.isEmpty && !artists.isEmpty {
                if let line = theme.copy.searchNoResults(filter) {
                    ContentUnavailableView(line, systemImage: "magnifyingglass")
                } else {
                    ContentUnavailableView.search(text: filter)
                }
            }
        }
        .task { await load() }
        .onChange(of: filter) { rebuildSections() }
    }

    /// A compact, contextual filter that lives just above the list instead of
    /// stretching across the toolbar into the inspector.
    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: plainVoice ? 15 : 12, weight: .medium))
                .foregroundStyle(theme.palette.textSecondary)
            TextField("Filter artists", text: $filter,
                      prompt: plainVoice
                        ? Text("Filter artists").foregroundStyle(theme.palette.textIdle)
                        : nil)
                .textFieldStyle(.plain)
                .font(theme.type.body(plainVoice ? 16 : 13))
                .foregroundStyle(theme.palette.textPrimary)
                // The root tint is snow under Yeti; the caret is focus, and
                // focus is foil.
                .tintIfSet(plainVoice ? theme.palette.accent : nil)
                .focused($filterFocused)
                .submitLabel(.done)
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, plainVoice ? 12 : 10)
        .padding(.vertical, 7)
        // `.search`: a 38pt shelf field, radius 12, no keyline at rest (the
        // foil focus ring stays).
        .frame(minHeight: plainVoice ? 38 : nil)
        .background {
            let radius: CGFloat = plainVoice ? 12 : 9
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.palette.raised)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(filterFocused ? theme.palette.accent.opacity(0.7)
                                                    : (plainVoice ? .clear : theme.palette.hairline),
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
            rebuildSections()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
