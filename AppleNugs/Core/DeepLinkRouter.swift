import Foundation

/// Resolves a parsed `DeepLink` to a nugs container and navigates + starts
/// playback, reusing the existing client/catalog/player/navigation surface.
/// For a track link it starts at that track; for a show link it plays from the
/// top; for a video it opens the video detail (which drives its own playback).
@MainActor
enum DeepLinkRouter {

    /// Entry point. Resolve + act; surface failures as a toast rather than
    /// throwing into the UI. The user arrived from a "Listen"/"Watch" link, so
    /// the show is navigated to AND playback starts.
    static func handle(_ link: DeepLink, app: AppModel, ui: UIState) async {
        do {
            switch link.media {
            case .audio: try await openAudio(link, app: app, ui: ui)
            case .video: try await openVideo(link, app: app, ui: ui)
            }
        } catch {
            ui.showToast("Couldn't open that show on nugs")
        }
    }

    // MARK: - audio

    private static func openAudio(_ link: DeepLink, app: AppModel, ui: UIState) async throws {
        guard let containerId = try await resolveContainerId(link, app: app) else {
            ui.showToast("That show isn't on nugs")
            return
        }
        // Do the fallible fetch + queue build BEFORE touching navigation, so a
        // failure leaves the UI untouched (just the catch's toast) rather than
        // stranding the user on an empty album detail.
        let album = Catalog.album(from: try await app.client.album(id: containerId), id: containerId)
        let queue = album.tracks.map {
            QueueTrack(trackId: $0.id, title: $0.title, artist: album.artistName,
                       show: album.title, artworkPath: album.imagePath, showId: album.id)
        }
        ui.open(.album(id: containerId, title: nil))      // now navigate…
        guard !queue.isEmpty else { return }
        // …and start playback (the user came from a "Listen" link).
        if let song = link.song,
           let idx = DeepLinkMatch.bestTrackIndex(matching: song, inTitles: album.tracks.map(\.title)) {
            app.player.play(queue, startAt: idx)          // jump to the linked performance
        } else {
            app.player.play(queue)                        // play the whole show
        }
    }

    /// Find the live container for artist+date (venue tie-breaks), paging the
    /// artist's shows like the video path, then falling back to catalog search.
    private static func resolveContainerId(_ link: DeepLink, app: AppModel) async throws -> String? {
        guard let artistId = try await artistId(matching: link.artist, app: app) else {
            return try await searchContainerId(link, app: app)
        }
        if let id = try await pagedContainerId(artistId: artistId, link: link, app: app) { return id }
        return try await searchContainerId(link, app: app)
    }

    /// Page through the artist's shows (bounded) for a live container matching the
    /// date. The UI only ever loads the first page, so a deep link to an older show
    /// would otherwise miss; mirror openVideo's bounded paging.
    private static func pagedContainerId(artistId: String, link: DeepLink, app: AppModel) async throws -> String? {
        let pageSize = 100
        let maxPages = 10                                 // safety cap (≤1000 shows)
        var offset = 1
        for _ in 0..<maxPages {
            let page = Catalog.containers(
                from: try await app.client.artistShows(id: artistId, offset: offset, limit: pageSize))
            let sameDay = page.filter { $0.isLiveShow && $0.dateText == link.date }
            if let hit = pick(sameDay, venue: link.venue) { return hit.id }
            if page.count < pageSize { break }            // last page
            offset += page.count
        }
        return nil
    }

    private static func searchContainerId(_ link: DeepLink, app: AppModel) async throws -> String? {
        let model = Catalog.search(from: try await app.client.search("\(link.artist) \(link.date)"))
        for section in model.sections {
            for item in section.items {
                guard case .container(let id) = item.kind, item.dateText == link.date else { continue }
                if let v = link.venue, !DeepLinkMatch.venueMatches(item.venue, v) { continue }
                return id
            }
        }
        return nil
    }

    // MARK: - video

    /// Per-artist video list isn't searchable (catalog.search has no video kind)
    /// and the UI only ever loads its first page, so a deep link to an older show
    /// would miss. Page through (bounded) until the date is found or the list ends.
    private static func openVideo(_ link: DeepLink, app: AppModel, ui: UIState) async throws {
        guard let artistId = try await artistId(matching: link.artist, app: app) else {
            ui.showToast("That show isn't on nugs"); return
        }
        let pageSize = 100
        let maxPages = 10                                 // safety cap (≤1000 videos)
        var offset = 1
        for _ in 0..<maxPages {
            let page = try await app.client.artistVideos(id: artistId, offset: offset, limit: pageSize)
            // VideoSummary has no venue field, so disambiguation is date-only.
            if let hit = page.first(where: { $0.dateText == link.date }) {
                ui.open(.video(id: hit.id, title: hit.title))   // VideoDetailView drives playback
                return
            }
            if page.count < pageSize { break }            // last page
            offset += page.count
        }
        ui.showToast("No video for that show on nugs")
    }

    // MARK: - helpers

    private static func artistId(matching name: String, app: AppModel) async throws -> String? {
        try await app.artists().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
    }

    /// Date already filtered. With a venue hint, REQUIRE a venue match — return
    /// nil on mismatch so the caller keeps paging / falls back to search rather
    /// than silently autoplaying the wrong show on a two-show day. Without a hint,
    /// take the first same-day show. (Matches searchContainerId's venue semantics.)
    private static func pick(_ cs: [ContainerSummary], venue: String?) -> ContainerSummary? {
        guard let venue else { return cs.first }
        return cs.first { DeepLinkMatch.venueMatches($0.venue, venue) }
    }
}
