import SwiftUI

/// The artist library: one scope at a time (Shows / Videos / Albums), a text
/// filter, and a flat reverse-chronological list under sticky month headers.
///
/// Replaces the old three-level Category → Year → row tree. That tree cost two
/// clicks before a single show was visible, buried "what's recent" three levels
/// down, and dumped 84 undifferentiated rows when you opened a year.
struct CrateList: View {
    let albums: [CrateItem]
    let videos: [CrateItem]
    let shows: [CrateItem]
    let loading: Bool

    @Environment(\.theme) private var theme

    @State private var scope: CrateKind = .show
    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    private var plainVoice: Bool { theme.caps.contains(.plainVoice) }

    /// Derived state, not computed in `body`: filtering + grouping + sorting a
    /// catalog hundreds deep is too heavy to redo on every body evaluation
    /// (theme switches, favorites toggles, playback ticks). Rebuilt only when
    /// the inputs actually change. The old outline re-grouped all 483 shows on
    /// every render.
    @State private var sections: [(month: Date?, items: [CrateItem])] = []

    private var scopedItems: [CrateItem] {
        switch scope {
        case .show:  return shows
        case .video: return videos
        case .album: return albums
        }
    }

    private func rebuildSections() {
        // Albums are a handful of undated studio releases — one flat section.
        guard scope != .album else {
            let needle = CrateSection.normalized(filter)
            let kept = needle.isEmpty ? albums : albums.filter { $0.searchText.contains(needle) }
            sections = kept.isEmpty ? [] : [(month: nil, items: kept)]
            return
        }
        sections = CrateSection.sections(scopedItems, filter: filter,
                                         calendar: CrateSection.catalogCalendar)
    }

    var body: some View {
        VStack(spacing: 0) {
            scopePicker
            filterField
            content
        }
        .onAppear(perform: rebuildSections)
        .onChange(of: scope) { _, _ in rebuildSections() }
        .onChange(of: filter) { _, _ in rebuildSections() }
        .onChange(of: shows.count) { _, _ in rebuildSections() }
        .onChange(of: videos.count) { _, _ in rebuildSections() }
        .onChange(of: albums.count) { _, _ in rebuildSections() }
    }

    // MARK: scope

    /// Yeti (`.plainVoice`): its own segmented control, and no counts in the
    /// labels — the header's counts line under the name already carries them.
    @ViewBuilder
    private var scopeControl: some View {
        if plainVoice {
            YetiSegmentedControl("Scope", selection: $scope, options: [
                .init(value: .show, title: "Shows"),
                .init(value: .video, title: "Videos"),
                .init(value: .album, title: "Albums"),
            ])
        } else {
            Picker("Scope", selection: $scope) {
                Text("Shows \(shows.count)").tag(CrateKind.show)
                Text("Videos \(videos.count)").tag(CrateKind.video)
                Text("Albums \(albums.count)").tag(CrateKind.album)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var scopePicker: some View {
        scopeControl
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
    }

    // MARK: filter

    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.palette.textSecondary)
            TextField(placeholder, text: $filter,
                      prompt: plainVoice
                        ? Text(placeholder).foregroundStyle(theme.palette.textIdle)
                        : nil)
                .textFieldStyle(.plain)
                .font(theme.type.body(plainVoice ? 15 : 13))
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
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, plainVoice ? 12 : 10)
        .padding(.vertical, 7)
        // Yeti's `.field`: a 40pt shelf field, radius 12, no keyline.
        .frame(minHeight: plainVoice ? 40 : nil)
        .background {
            let radius: CGFloat = plainVoice ? 12 : 8
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.palette.raised)
                .overlay {
                    if !plainVoice {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(theme.palette.hairline, lineWidth: 1)
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var placeholder: String {
        switch scope {
        case .show:  return "Filter shows by venue, city, or date"
        case .video: return "Filter videos by title or date"
        case .album: return "Filter albums"
        }
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        // Never claim "no matches" while pages are still arriving — a later page
        // may hold the match the user just typed.
        if sections.isEmpty && !filter.isEmpty && !loading {
            ContentUnavailableView {
                Label("No matches", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing in \(scope.label.lowercased()) matches “\(filter)”.")
            } actions: {
                Button("Clear filter") { filter = "" }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if scope == .album {
                    // Undated studio releases: no month headers, and no Section —
                    // an empty header would leave a dead gap at the top.
                    ForEach(Array((sections.first?.items ?? []).enumerated()),
                            id: \.element.id) { offset, item in
                        CrateRow(item: item, index: offset + 1)
                            .themedListRow()
                    }
                } else {
                    ForEach(sections, id: \.month) { section in
                        Section {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { offset, item in
                                CrateRow(item: item, index: offset + 1)
                                    .themedListRow()
                            }
                        } header: {
                            monthHeader(section.month)
                        }
                    }
                }
                if loading { loadingFooter }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    /// Month headers. Yeti (`.plainVoice`): the barker's heavy slush 15
    /// (`.month`), sentence case; every other theme keeps the system header.
    @ViewBuilder
    private func monthHeader(_ month: Date?) -> some View {
        if theme.caps.contains(.plainVoice) {
            Text(header(month))
                .font(theme.type.section(15))
                .foregroundStyle(theme.palette.textSecondary)
        } else {
            Text(header(month))
        }
    }

    private func header(_ month: Date?) -> String {
        let title = CrateSection.monthTitle(month,
                                            calendar: CrateSection.catalogCalendar,
                                            locale: .current)
        return theme.caps.contains(.condensedHeaders) ? title.uppercased() : title
    }

    private var loadingFooter: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading more…")
                .font(theme.type.body(12))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedListRow()
    }
}
