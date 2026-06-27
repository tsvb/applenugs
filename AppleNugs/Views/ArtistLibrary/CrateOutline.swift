import SwiftUI

/// The artist library: Albums / Videos / Shows as collapsible category nodes.
/// Videos and Shows nest a second level by year; Albums list rows directly.
/// All nodes start collapsed. Lazy rendering means a year's rows only build
/// when that year is expanded, so a large video catalog never forms a wall.
struct CrateOutline: View {
    let albums: [CrateItem]
    let videos: [CrateItem]
    let shows: [CrateItem]
    let canLoadMore: Bool
    let loading: Bool
    let loadMore: () -> Void

    @Environment(\.theme) private var theme

    @State private var expandedCategories: Set<CrateKind> = []
    @State private var expandedYears: Set<YearKey> = []

    private struct YearKey: Hashable { let kind: CrateKind; let year: Int? }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if !albums.isEmpty { categoryNode(.album, items: albums, grouped: false) }
            if !videos.isEmpty { categoryNode(.video, items: videos, grouped: true) }
            if !shows.isEmpty  { categoryNode(.show,  items: shows,  grouped: true) }
        }
    }

    // MARK: category node

    @ViewBuilder
    private func categoryNode(_ kind: CrateKind, items: [CrateItem], grouped: Bool) -> some View {
        let open = expandedCategories.contains(kind)
        let label = theme.caps.contains(.condensedHeaders) ? kind.label.uppercased() : kind.label

        Button {
            toggle(&expandedCategories, kind)
        } label: {
            HStack(spacing: 8) {
                chevron(open)
                Image(systemName: kind.icon).frame(width: 16)
                Text(label).font(theme.type.section(15))
                Spacer(minLength: 8)
                Text("\(items.count)")
                    .font(theme.type.numeric(11))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .foregroundStyle(theme.palette.textPrimary)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.label), \(items.count) items")
        .accessibilityValue(open ? "expanded" : "collapsed")

        if open {
            if grouped {
                ForEach(items.groupedByYear(), id: \.year) { group in
                    yearNode(kind: kind, year: group.year, items: group.items)
                }
                if kind == .show { paginationFooter }
            } else {
                rows(items)
            }
        }
    }

    // MARK: year node

    @ViewBuilder
    private func yearNode(kind: CrateKind, year: Int?, items: [CrateItem]) -> some View {
        let key = YearKey(kind: kind, year: year)
        let open = expandedYears.contains(key)
        let title = year.map(String.init) ?? "Unknown"

        Button {
            toggle(&expandedYears, key)
        } label: {
            HStack(spacing: 8) {
                chevron(open)
                Text(title).font(theme.type.body(13))
                Spacer(minLength: 8)
                Text("\(items.count)")
                    .font(theme.type.numeric(11))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .foregroundStyle(theme.palette.textSecondary)
            .padding(.vertical, 5)
            .padding(.leading, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(items.count) items")
        .accessibilityValue(open ? "expanded" : "collapsed")

        if open { rows(items, indent: 36) }
    }

    // MARK: rows

    @ViewBuilder
    private func rows(_ items: [CrateItem], indent: CGFloat = 18) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
            CrateRow(item: item, index: offset + 1)
                .padding(.leading, indent)
        }
    }

    private var paginationFooter: some View {
        Group {
            if loading {
                ProgressView().controlSize(.small).padding(.vertical, 6)
            } else if canLoadMore {
                Color.clear.frame(height: 1).onAppear(perform: loadMore)
            }
        }
        .padding(.leading, 18)
    }

    // MARK: helpers

    private func chevron(_ open: Bool) -> some View {
        Image(systemName: open ? "chevron.down" : "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.palette.textSecondary)
            .frame(width: 13)
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}
