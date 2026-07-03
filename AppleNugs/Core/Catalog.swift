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

// --- video catalog models -----------------------------------------------------
// Purpose-built presentation types for the Videos feature. Kept distinct from
// ContainerSummary/AlbumDetailModel so the audio catalog path is untouched.

/// A browse-grid / row item: VOD or a live/upcoming webcast.
struct VideoSummary: Identifiable, Hashable {
    let id: String              // containerID (legacy) or release id (REST)
    let title: String
    let artistName: String?
    let performanceDate: String?
    let imagePath: String?
    let isLive: Bool            // LIVE HD VIDEO vs VIDEO ON DEMAND
    let eventStart: Date?       // upcoming/live webcasts only
    let has4K: Bool

    var imageURL: URL? { imagePath.flatMap { NugsConstants.imageURL(path: $0) } }
    var dateText: String? { Catalog.isoDate(performanceDate) }
}

extension VideoSummary: WebcastLike {}

/// One tappable chapter marker inside a VideoDetail.
struct VideoChapter: Identifiable, Hashable {
    let id: String
    let title: String
    let startSeconds: Double
}

/// Live-webcast scheduling, used to drive pre-event / live / ended states.
struct LiveEventInfo: Hashable {
    var startsAt: Date?
    var endsAt: Date?
    var isEventLive: Bool
}

/// VideoDetailView payload, parsed from `catalog.container&vdisp=1`.
struct VideoDetail {
    var id: String
    var videoSku: Int
    var isLive: Bool
    var title: String
    var artistName: String
    var venue: String?
    var dateText: String?
    var description: String?
    var imagePath: String?
    var chapters: [VideoChapter]
    var liveEvent: LiveEventInfo?

    var imageURL: URL? { imagePath.flatMap { NugsConstants.imageURL(path: $0) } }
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

    // --- video parsers ------------------------------------------------------

    /// REST `GET /releases/recent?contentType=video` → recently-added VOD.
    /// Items may be wrapped in `items`/`releases`; each item is a release object
    /// (sometimes nested under `release`).
    static func recentVideos(from json: JSON) -> [VideoSummary] {
        let items = json.arr("items", "Items", "releases", "Releases", "data")
        return items.compactMap { videoSummary(fromRelease: $0, isLiveDefault: false) }
    }

    /// REST `GET /livestreams?itemTypes=sel` → `{ items, offset, limit, total }`.
    /// Each item carries `skuId`, `startDate`/`endDate`, `has4KOption`, and a
    /// nested `release { id, title, performanceDate, coverImage, artist{...} }`.
    static func liveWebcasts(from json: JSON) -> [VideoSummary] {
        json.arr("items", "Items", "data").compactMap { item in
            let release = item["release"].raw != nil ? item["release"] : item
            // Never fall back to the live `skuId` as the container id — it's a
            // different namespace and would mis-route videoDetail/resolve.
            guard let id = release.str("id", "ID", "containerID", "releaseId")
                    ?? item.str("id", "ID") else { return nil }
            let start = Catalog.parseTimestamp(item.str("startDate", "StartDate", "eventStartDateStr"))
            let has4K = (item["has4KOption"].raw as? Bool) ?? (item.int("has4KOption") == 1)
            return VideoSummary(
                id: id,
                title: release.str("title", "Title", "containerInfo") ?? "(untitled)",
                artistName: release["artist"].str("name", "artistName")
                    ?? release.str("artistName", "ArtistName"),
                performanceDate: release.str("performanceDate", "PerformanceDate"),
                imagePath: videoImagePath(release),
                isLive: true,
                eventStart: start,
                has4K: has4K)
        }
    }

    /// Per-artist legacy `catalog.containersAll&videoReleaseType=6` → video
    /// containers. Mirrors `containers(from:)` but tags each as a video item.
    static func videoContainers(from json: JSON) -> [VideoSummary] {
        json.unwrapped.arr("containers", "Containers").compactMap { c in
            guard let id = c.str("containerID", "ContainerID", "id") else { return nil }
            return VideoSummary(
                id: id,
                title: c.str("containerInfo", "ContainerInfo", "title") ?? "(untitled)",
                artistName: c.str("artistName", "ArtistName"),
                performanceDate: c.str("performanceDate", "PerformanceDate"),
                imagePath: videoImagePath(c) ?? c["img"].str("url"),
                isLive: false,
                eventStart: nil,
                has4K: false)
        }
    }

    /// Legacy `catalog.container&containerID=<id>&vdisp=1` → full video detail.
    /// The video SKU is the `skuID` of the product whose `formatStr` is
    /// `"VIDEO ON DEMAND"` (VOD) or, in `productFormatList`, `"LIVE HD VIDEO"`.
    static func videoDetail(from json: JSON, id: String) -> VideoDetail {
        let r = json.unwrapped
        let (sku, isLive) = videoSku(in: r)

        let rawDate = r.str("performanceDateFormatted") ?? r.str("performanceDate", "PerformanceDate")

        let chapters = r.arr("videoChapters", "VideoChapters", "chapters").enumerated().compactMap {
            (idx, ch) -> VideoChapter? in
            let title = ch.str("chaptername", "chapterName", "title", "chapterTitle", "name", "songTitle")
                ?? "Chapter \(idx + 1)"
            let start = chapterSeconds(ch)
            return VideoChapter(id: ch.str("id", "chapterID") ?? "\(idx)", title: title, startSeconds: start)
        }

        var liveEvent: LiveEventInfo? = nil
        if isLive {
            liveEvent = LiveEventInfo(
                startsAt: Catalog.parseTimestamp(r.str("eventStartDateStr", "eventStartDate")),
                endsAt: Catalog.parseTimestamp(r.str("eventEndDateStr", "eventEndDate")),
                isEventLive: (r["isEventLive"].raw as? Bool) ?? (r.int("isEventLive") == 1))
        }

        return VideoDetail(
            id: id,
            videoSku: sku,
            isLive: isLive,
            title: r.str("containerInfo", "ContainerInfo", "videoTitle", "title") ?? "(video)",
            artistName: r.str("artistName", "ArtistName") ?? "",
            venue: r.str("venue")?.trimmingCharacters(in: .whitespaces),
            dateText: isoDate(rawDate),
            description: r.str("videoDesc", "VideoDesc", "description")
                ?? joinedNotes(r),
            imagePath: videoImagePath(r),
            chapters: chapters,
            liveEvent: liveEvent)
    }

    // --- video parsing helpers ----------------------------------------------

    /// Shared release→summary mapping for the REST `/releases/*` shapes.
    private static func videoSummary(fromRelease item: JSON, isLiveDefault: Bool) -> VideoSummary? {
        let release = item["release"].raw != nil ? item["release"] : item
        guard let id = release.str("id", "ID", "containerID", "releaseId")
                ?? item.str("id", "ID", "containerID") else { return nil }
        let has4K = (item["has4KOption"].raw as? Bool)
            ?? (release["has4KOption"].raw as? Bool)
            ?? (item.int("has4KOption") == 1)
        return VideoSummary(
            id: id,
            title: release.str("title", "Title", "containerInfo") ?? "(untitled)",
            artistName: release["artist"].str("name", "artistName")
                ?? release.str("artistName", "ArtistName"),
            performanceDate: release.str("performanceDate", "PerformanceDate"),
            imagePath: videoImagePath(release),
            isLive: isLiveDefault,
            eventStart: Catalog.parseTimestamp(item.str("startDate", "StartDate")),
            has4K: has4K)
    }

    /// Resolve a video poster from the several keys nugs uses across shapes.
    /// REST shapes nest the absolute URL under `image.url` (preferred);
    /// `NugsConstants.imageURL(path:)` passes absolute URLs through unchanged.
    private static func videoImagePath(_ j: JSON) -> String? {
        j["image"].str("url", "path")
            ?? j.str("videoImage", "VideoImage", "vodPlayerImage", "coverImage", "CoverImage")
            ?? j["coverImage"].str("url", "path")
            ?? j["img"].str("url")
    }

    /// Scan product arrays for the video product and return (skuID, isLive).
    /// VOD: a `products[]` entry with `formatStr == "VIDEO ON DEMAND"`.
    /// Live: a `productFormatList[]` entry with `formatStr == "LIVE HD VIDEO"`.
    private static func videoSku(in r: JSON) -> (sku: Int, isLive: Bool) {
        for p in r.arr("products", "Products") {
            if p.str("formatStr", "FormatStr") == "VIDEO ON DEMAND",
               let sku = p.int("skuID", "skuId", "SkuID") {
                return (sku, false)
            }
        }
        for p in r.arr("productFormatList", "ProductFormatList") {
            if p.str("formatStr", "FormatStr") == "LIVE HD VIDEO",
               let sku = p.int("skuID", "skuId", "SkuID") {
                return (sku, true)
            }
        }
        // Some payloads expose the sub video SKU directly.
        if let sku = r.int("svodskuID", "svodSkuID", "videoSkuID") {
            let live = (r["isEventLive"].raw as? Bool) ?? (r.int("isEventLive") == 1)
            return (sku, live)
        }
        return (0, false)
    }

    /// Chapter start time: a numeric `chapterSeconds`/`startSeconds`/`offset`, or
    /// "h:mm:ss" / "mm:ss" / "m:ss" text in `startTime`.
    private static func chapterSeconds(_ ch: JSON) -> Double {
        if let n = ch["chapterSeconds"].raw as? NSNumber { return n.doubleValue }
        if let n = ch["startSeconds"].raw as? NSNumber { return n.doubleValue }
        if let n = ch["offset"].raw as? NSNumber { return n.doubleValue }
        if let n = ch["startTimeSeconds"].raw as? NSNumber { return n.doubleValue }
        if let s = ch.str("startTime", "start", "time") {
            let parts = s.split(separator: ":").compactMap { Double($0) }
            guard !parts.isEmpty else { return 0 }
            return parts.reduce(0) { $0 * 60 + $1 }
        }
        return 0
    }

    /// Fallback description: join the legacy `notes[].note` strings.
    private static func joinedNotes(_ r: JSON) -> String? {
        let notes = r.arr("notes", "Notes").compactMap { $0.str("note", "Note") }
        return notes.isEmpty ? nil : notes.joined(separator: "\n")
    }

    /// Full timestamp parsing for REST `/livestreams` event times. Tolerates
    /// both fractional and whole-second ISO-8601 (with or without "Z"). A
    /// computed property rather than a shared `static let`: `ISO8601DateFormatter`
    /// isn't `Sendable`, and this is called rarely enough (a handful of event
    /// times per livestream load) that a fresh formatter per call is free.
    private static var isoTimestamp: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = isoTimestamp.date(from: raw) { return d }
        // Retry without fractional seconds.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    // --- dates --------------------------------------------------------------

    private static let slashShort: DateFormatter = makeFormatter("M/d/yyyy")
    private static let slashFull: DateFormatter = makeFormatter("yyyy/MM/dd")
    private static let iso: DateFormatter = makeFormatter("yyyy-MM-dd")
    // REST shapes (/releases/recent, /livestreams.release) carry performanceDate
    // as a zoneless ISO datetime ("2026-05-30T00:00:00"); the legacy paths use
    // the slash forms. Parse both so isoDate() always returns a clean date.
    private static let dashDateTime: DateFormatter = makeFormatter("yyyy-MM-dd'T'HH:mm:ss")
    private static let dashFull: DateFormatter = makeFormatter("yyyy-MM-dd")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return slashShort.date(from: raw)
            ?? slashFull.date(from: raw)
            ?? dashDateTime.date(from: raw)
            ?? dashFull.date(from: raw)
    }

    /// "M/d/yyyy" or "yyyy/MM/dd" → "yyyy-MM-dd"; falls back to the raw string.
    static func isoDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        guard let date = parseDate(raw) else { return raw }
        return iso.string(from: date)
    }
}
