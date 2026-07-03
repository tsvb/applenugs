import SwiftUI

/// The three top-level catalog categories shown on the artist page.
enum CrateKind: Hashable {
    case album, video, show

    /// SF Symbol for the category node.
    var icon: String {
        switch self {
        case .album: return "opticaldisc"
        case .video: return "play.rectangle"
        case .show:  return "music.mic"
        }
    }

    /// Plural category label for the node header.
    var label: String {
        switch self {
        case .album: return "Albums"
        case .video: return "Videos"
        case .show:  return "Shows"
        }
    }

    /// Singular word used in row accessibility labels.
    var word: String {
        switch self {
        case .album: return "album"
        case .video: return "video"
        case .show:  return "show"
        }
    }
}

/// One row in the artist library outline. Unifies a studio release, a live
/// show (both `ContainerSummary`) and a video (`VideoSummary`) into a single
/// presentation model so the outline renders them with one row view.
struct CrateItem: Identifiable, Hashable {
    let rawID: String          // catalog id used for routes + favorites
    let kind: CrateKind
    let title: String
    let artistName: String
    let venue: String?
    let dateText: String?
    let date: Date?
    let imageURL: URL?
    let isLive: Bool
    let has4K: Bool
    let route: Route

    // Kind-qualified so a video and a show that share a catalog id never
    // collide inside a mixed ForEach.
    var id: String { "\(kind)-\(rawID)" }

    var year: Int? {
        guard let date else { return nil }
        return Calendar.current.component(.year, from: date)
    }
}

extension CrateItem {
    /// Crate rows render 24-40pt thumbnails — request a matching CDN resize
    /// (?h=96 covers 3x displays) instead of decoding 400px covers per row.
    private static func thumbURL(_ path: String?) -> URL? {
        path.flatMap { NugsConstants.imageURL(path: $0, height: 96) }
    }

    static func album(_ c: ContainerSummary, artist: String) -> CrateItem {
        CrateItem(rawID: c.id, kind: .album, title: c.title,
                  artistName: c.artistName ?? artist, venue: c.venue,
                  dateText: c.dateText, date: c.date, imageURL: thumbURL(c.imagePath),
                  isLive: false, has4K: false,
                  route: .album(id: c.id, title: c.title))
    }

    static func show(_ c: ContainerSummary, artist: String) -> CrateItem {
        let display = c.venue ?? c.title
        return CrateItem(rawID: c.id, kind: .show, title: display,
                  artistName: c.artistName ?? artist, venue: c.venue,
                  dateText: c.dateText, date: c.date, imageURL: thumbURL(c.imagePath),
                  isLive: false, has4K: false,
                  route: .album(id: c.id, title: display))
    }

    static func video(_ v: VideoSummary, artist: String) -> CrateItem {
        let d = Catalog.parseDate(v.performanceDate) ?? v.eventStart
        return CrateItem(rawID: v.id, kind: .video, title: v.title,
                  artistName: v.artistName ?? artist, venue: nil,
                  dateText: v.dateText, date: d, imageURL: thumbURL(v.imagePath),
                  isLive: v.isLive, has4K: v.has4K,
                  route: .video(id: v.id, title: v.title))
    }
}

extension Array where Element == CrateItem {
    /// Groups by calendar year, newest year first; undated items fall into a
    /// trailing `nil` ("Unknown") group. Within a group, newest item first.
    func groupedByYear() -> [(year: Int?, items: [CrateItem])] {
        Dictionary(grouping: self, by: { $0.year })
            .map { (year: $0.key,
                    items: $0.value.sorted {
                        ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
                    }) }
            .sorted { lhs, rhs in
                switch (lhs.year, rhs.year) {
                case let (l?, r?): return l > r
                case (nil, _):     return false   // Unknown sorts last
                case (_, nil):     return true
                }
            }
    }
}

#Preview("CrateItem mapping") {
    let containers = [
        ContainerSummary(id: "a1", title: "Viva El Gonzo", artistName: "Goose",
                         venue: nil, performanceDate: nil, imagePath: nil),
        ContainerSummary(id: "s1", title: "Show", artistName: "Goose",
                         venue: "Solid Sound Festival", performanceDate: "6/29/2024",
                         imagePath: nil),
    ]
    let videos = [
        VideoSummary(id: "v1", title: "Live from MSG", artistName: "Goose",
                     performanceDate: "6/19/2026", imagePath: nil, isLive: false,
                     eventStart: nil, has4K: true),
    ]
    let items = containers.filter { !$0.isLiveShow }.map { CrateItem.album($0, artist: "Goose") }
        + containers.filter(\.isLiveShow).map { CrateItem.show($0, artist: "Goose") }
        + videos.map { CrateItem.video($0, artist: "Goose") }
    return List(items) { item in
        Text("\(item.kind.label) · \(item.title) · \(item.year.map(String.init) ?? "—")")
    }
}
