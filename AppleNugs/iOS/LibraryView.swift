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
        // the header tracks the visible content. Inline, because the Picker an
        // inch below already names the segment — a large title would spend the
        // top of the phone's longest list saying it a second time.
        .navigationTitle(segment == .favorites ? "Favorites" : "Downloads")
        .compactNavigationTitle()
    }
}
