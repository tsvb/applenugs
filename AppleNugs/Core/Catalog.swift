import Foundation

// --- typed catalog models -----------------------------------------------------
// The Razor components dug into raw JsonNode defensively; the Swift port does
// the same digging once, here, and hands typed models to the views.

struct ArtistEntry: Identifiable, Hashable {
    let id: String
    let name: String
}

/// One container (live show or studio release) as it appears in
/// catalog.containersAll and search results.
struct ContainerSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String?
    let venue: String?
    let performanceDate: String?   // "M/d/yyyy" — nil for studio releases
    let imagePath: String?

    var isLiveShow: Bool { performanceDate != nil }

    var date: Date? { Catalog.parseDate(performanceDate) }

    var year: Int {
        guard let date else { return 0 }
        return Calendar.current.component(.year, from: date)
    }

    var dateText: String? { Catalog.isoDate(performanceDate) }

    var imageURL: URL? {
        guard let imagePath else { return nil }
        return NugsConstants.imageURL(path: imagePath)
    }
}

struct TrackEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let durationText: String?
    let setNum: Int
    let trackNum: Int

    /// nugs's setNum convention: 1/2/3 are sets, 4+ are encores. Studio
    /// releases use setNum=0 across the board — rendered with no header.
    static func setLabel(_ n: Int) -> String {
        switch n {
        case 0: return "Tracks"
        case 1...3: return "Set \(n)"
        case 4: return "Encore"
        default: return "Encore \(n - 3)"
        }
    }
}

struct AlbumDetailModel {
    var id: String
    var title: String
    var artistName: String
    var venue: String?
    var dateText: String?
    var totalRunningTime: String?
    var imagePath: String?
    var notesHTML: [String]
    var tracks: [TrackEntry]

    var imageURL: URL? {
        guard let imagePath else { return nil }
        return NugsConstants.imageURL(path: imagePath)
    }
}

struct SearchModel {
    struct Item: Identifiable {
        enum Kind {
            case track(trackId: String)
            case container(id: String)
        }
        let id = UUID()
        let kind: Kind
        let name: String
        let artistName: String?
        let dateText: String?
        let venue: String?
    }

    struct Section: Identifiable {
        let id = UUID()
        let header: String
        let items: [Item]
    }

    var artists: [ArtistEntry]
    var sections: [Section]

    var isEmpty: Bool { artists.isEmpty && sections.isEmpty }
}

// --- parsing --------------------------------------------------------------------

enum Catalog {
    /// catalog.artists → sorted artist list. Key candidates carried over from
    /// the web port's CatalogCache.
    static func artists(from json: JSON) -> [ArtistEntry] {
        let items = json.unwrapped.arr(
            "artists", "Artists",
            "catalogArtists", "CatalogArtists",
            "items", "Items")
        var list: [ArtistEntry] = []
        for item in items {
            guard let id = item.str("artistID", "ArtistID", "artistId", "id"),
                  let name = item.str("artistName", "ArtistName", "name")
            else { continue }
            list.append(ArtistEntry(id: id, name: name))
        }
        return list.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// catalog.containersAll → containers (newest-first per the API).
    static func containers(from json: JSON) -> [ContainerSummary] {
        json.unwrapped.arr("containers", "Containers").compactMap { c in
            guard let id = c.str("containerID", "ContainerID", "id") else { return nil }
            return ContainerSummary(
                id: id,
                title: c.str("containerInfo", "ContainerInfo", "title") ?? "(untitled)",
                artistName: c.str("artistName", "ArtistName"),
                venue: c.str("venue")?.trimmingCharacters(in: .whitespaces),
                performanceDate: c.str("performanceDate"),
                imagePath: c["img"].str("url"))
        }
    }

    /// catalog.container → one show / studio release with its track list.
    static func album(from json: JSON, id: String) -> AlbumDetailModel {
        let r = json.unwrapped
        let title = r.str("containerInfo", "ContainerInfo", "title") ?? "(album)"

        // Prefer performanceDateFormatted ("yyyy/MM/dd") over performanceDate
        // ("M/d/yyyy"), same as AlbumDetail.razor.
        let rawDate = r.str("performanceDateFormatted") ?? r.str("performanceDate")

        let tracks = r.arr("tracks", "Tracks", "songs", "Songs").compactMap { t -> TrackEntry? in
            guard let trackId = t.str("trackID", "TrackID", "trackId", "id") else { return nil }
            return TrackEntry(
                id: trackId,
                title: t.str("songTitle", "SongTitle", "title") ?? "(untitled)",
                durationText: t.str("hhmmssTotalRunningTime"),
                setNum: t["setNum"].int ?? 0,
                trackNum: t["trackNum"].int ?? 0)
        }

        return AlbumDetailModel(
            id: id,
            title: title,
            artistName: r.str("artistName", "ArtistName") ?? "",
            venue: r.str("venue")?.trimmingCharacters(in: .whitespaces),
            dateText: isoDate(rawDate),
            totalRunningTime: r.str("hhmmssTotalRunningTime"),
            imagePath: r["img"].str("url"),
            notesHTML: r.arr("notes").compactMap { $0.str("note") },
            tracks: tracks)
    }

    /// catalog.search → flattened sections plus a deduped artist row, same
    /// scheme as SearchResults.razor.
    static func search(from json: JSON) -> SearchModel {
        var sections: [SearchModel.Section] = []
        var artistsById: [String: String] = [:]
        var artistOrder: [String] = []

        for tc in json.unwrapped.arr("catalogSearchTypeContainers") {
            for sc in tc.arr("catalogSearchContainers") {
                let header = sc.str("scHeader") ?? "Results"
                var items: [SearchModel.Item] = []

                for item in sc.arr("catalogSearchResultItems") {
                    if let aid = item.str("artistID"), let aname = item.str("artistName"),
                       artistsById.updateValue(aname, forKey: aid) == nil {
                        artistOrder.append(aid)
                    }

                    let trackId = item.str("trackID")
                    let containerId = item.str("containerID")
                    let name = item.str("containerName") ?? "(untitled)"
                    let date = item.str("performanceDate")
                    let venue = item.str("venue", "venueName")
                    let artist = item.str("artistName")

                    if let trackId, trackId != "0" {
                        items.append(SearchModel.Item(
                            kind: .track(trackId: trackId),
                            name: name, artistName: artist,
                            dateText: isoDate(date), venue: venue))
                    } else if let containerId, containerId != "0" {
                        items.append(SearchModel.Item(
                            kind: .container(id: containerId),
                            name: name, artistName: artist,
                            dateText: isoDate(date), venue: venue))
                    }
                }

                if !items.isEmpty {
                    sections.append(SearchModel.Section(header: header, items: items))
                }
            }
        }

        let artists = artistOrder.map { ArtistEntry(id: $0, name: artistsById[$0]!) }
        return SearchModel(artists: artists, sections: sections)
    }

    // --- dates --------------------------------------------------------------

    private static let slashShort: DateFormatter = makeFormatter("M/d/yyyy")
    private static let slashFull: DateFormatter = makeFormatter("yyyy/MM/dd")
    private static let iso: DateFormatter = makeFormatter("yyyy-MM-dd")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return slashShort.date(from: raw) ?? slashFull.date(from: raw)
    }

    /// "M/d/yyyy" or "yyyy/MM/dd" → "yyyy-MM-dd"; falls back to the raw string.
    static func isoDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        guard let date = parseDate(raw) else { return raw }
        return iso.string(from: date)
    }
}
