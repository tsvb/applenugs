# Videos — Design

**Date:** 2026-06-14
**Status:** Approved (design); pending implementation plan
**Component:** AppleNugs (native macOS SwiftUI nugs.net client)

## Goal

Let the user browse and watch the **videos** nugs.net offers — pre-recorded
concert **VOD** and **live webcasts** — inside AppleNugs, reusing the existing
catalog, session, and AVPlayer infrastructure. Today the app is audio-only; the
player engine is already `AVQueuePlayer` (video-capable) but its image is never
drawn. This feature adds the missing video *surface*, a small video
*stream-resolution* path, and a *browse* experience, while leaving audio
playback untouched.

## Scope

**In scope (v1):**
- A dedicated **Videos** sidebar section: a VOD grid + a **Live & Upcoming**
  webcasts area + a **Continue Watching** strip.
- A **VideoDetailView** with an **inline player** at the top (native macOS
  controls + fullscreen), metadata, and a tappable **chapter** list.
- A **separate video playback context**: video plays in its own `AVPlayer`; the
  audio queue is paused and left intact, then resumes when the user leaves the
  video. Only one of audio/video owns Now Playing / remote commands at a time.
- **Live webcasts**: live-edge playback, a LIVE badge, and pre-event / live /
  ended states driven by the event schedule.
- **Per-artist Videos** section in `ArtistDetailView`.
- **Search** surfaces videos; **Favorites** can save videos.
- **Resume / Continue Watching**: per-video playback position persisted locally.
- **Quality**: automatic HLS ABR by default, **plus a manual quality override**
  (Auto / 1080p / 720p / …) capped via AVPlayer, not by swapping playlists.

**Out of scope (v1):**
- **Downloading / offline** video (this is a viewer, not a downloader).
- A **Home** video strip (Videos lives in the sidebar; Home is unchanged).
- **4K-specific** UX beyond "play what the master playlist offers" — 4K is a
  Hi-Res-tier entitlement we cannot force.
- **PPV purchasing** flow. We *play* an already-owned PPV webcast when the
  legacy `vidPlayer.aspx` path + UGUID are available; buying happens on nugs.net.
- **Cross-device sync** (local to this Mac, like the session and favorites).
- **Picture-in-Picture as a designed feature** — if `AVPlayerView` offers its
  PiP button for free we keep it, but it is not a v1 requirement.

## Top risk — FairPlay DRM (resolve in Step 1, before building playback)

nugs has **two** video stream paths:

1. **Modern** `catalog.nugs.net/api/v1/video/video-stream-link` → an HLS/DASH URL
   protected by **FairPlay** (license server `playback.nugs.net/api/v1/license/fairplay`).
   Supporting this means `AVContentKeySession` + a FairPlay certificate/license
   proxy — a large, uncertain lift.
2. **Legacy** `bigriver/subPlayer.aspx` (subscription) / `bigriver/vidPlayer.aspx`
   (owned/PPV) → an **HLS master `.m3u8`** with at most **AES-128** segment
   encryption (key URI in the playlist). Third-party downloaders consume this
   path without a DRM client, and `AVFoundation` plays AES-128 HLS natively.

**Plan: browse via the modern REST API, but *play* via the legacy bigriver
path** (the same `subPlayer.aspx` the app already uses for audio). This avoids
FairPlay entirely.

**This assumption is the single highest-value thing the approved Step-1 live
probe must confirm:** fetch one known VOD container, resolve its stream via
`subPlayer.aspx` with the video param set, and confirm the returned `.m3u8`
plays in a bare `AVPlayer` with no FairPlay challenge. If the legacy path turns
out to be FairPlay-gated too, we stop and re-scope (FairPlay support becomes its
own design) rather than silently expanding v1.

## Two API surfaces

The client gains a second base host. Both reuse the existing Bearer token.

| Purpose | Host / shape | In client |
|---|---|---|
| **Browse** video catalog & live schedule | `https://catalog.nugs.net/api/v1` — REST, `GET /path?limit=&offset=&contentType=` | **new** `catalogV1Get(path:query:)` |
| **Per-artist** video list, single container detail | `https://streamapi.nugs.net/api.aspx?method=…` | existing `catalogGet` |
| **Resolve stream** (playback) | `https://streamapi.nugs.net/bigriver/{subPlayer,vidPlayer}.aspx` | **new** `resolveVideoStream`, mirrors existing `streamURL` |

### Browse endpoints (modern REST)

- **VOD grid** — `GET /releases/recent?contentType=video&catalogFilterMode=any&limit=&offset=`
  (a *recently-added* feed — the only artist-independent global video listing;
  not a full-catalog dump).
- **Featured hero** (optional) — `GET /releases/featured?contentType=video`.
- **Live & Upcoming** — `GET /livestreams?itemTypes=sel&startDate=<now ISO8601>&limit=&offset=`
  → `{ items, offset, limit, total }`. Each item carries
  `{ skuId, eventType, contentType, startDate, endDate, has4KOption, freeVideo,
  release{ id, status, title, performanceDate, coverImage, artist{id,name},
  videoFormatTypes } }`. Split client-side into upcoming/live vs. recent.

### Per-artist videos (legacy)

`artistShows` already sends `vdisp=1&availType=1`; add `videoReleaseType=6` (the
video-only discriminator) for a video variant:
`catalog.containersAll&artistList=<id>&videoReleaseType=6&vdisp=1&availType=1`.
(`catalog.artists.svod` lists artists that *have* video, if we ever want a
video-artist index — not required for v1.)

### Video detection on a container (legacy detail)

`catalog.container&containerID=<id>&vdisp=1` returns product arrays. A container
is video when a product's `formatStr` is `"VIDEO ON DEMAND"` (VOD) or
`"LIVE HD VIDEO"` (live); **that product's `skuID` is the video SKU**. Also
present: `videoTitle`, `videoDesc`, `videoImage`, `vodPlayerImage`, `svodskuID`,
`containsPreviewVideo`, `videoChapters[]`, and live event info
(`isEventLive`, `eventStartDateStr`, `eventEndDateStr`).

### Stream resolution (playback — legacy bigriver)

A new `resolveVideoStream` modeled directly on the existing `streamURL`
(`NugsClient.swift:173`), reusing `Session` (`subscriptionId`, `planId`,
`userId`, `startStamp`, `endStamp`, `accessToken`) and `legacyUserAgent`:

- **Subscription VOD / sub livestream** → `bigriver/subPlayer.aspx` with
  `skuId=<videoSku>&containerID=<id>&chap=1&app=1` + the same subscription/date
  params `streamURL` already sends; read **`streamLink`**.
- **Owned / PPV** → `bigriver/vidPlayer.aspx` with
  `skuId&showId&uguid=<legacyUGUID>&nn_userID&app=1`; read **`fileURL`**.
  (UGUID is decoded from the JWT; if unavailable, treat as "not owned".)

The resolved URL is a master `.m3u8` handed straight to `AVPlayer`. No platform
probing (that is audio-only); no ffmpeg/muxing (that is downloader-only).

## Data model & persistence

### Catalog model additions (`Catalog.swift`)

Rather than overloading `ContainerSummary`, add purpose-built presentation
types, parsed by new `Catalog` functions, so the audio path is untouched:

```
struct VideoSummary: Identifiable, Hashable {     // a browse-grid / row item
    let id: String              // containerID (legacy) or release id (REST)
    let title: String
    let artistName: String?
    let performanceDate: String?
    let imagePath: String?
    let isLive: Bool            // LIVE HD VIDEO vs VIDEO ON DEMAND
    let eventStart: Date?       // upcoming/live webcasts only
    let has4K: Bool
    // imageURL via NugsConstants.imageURL, dateText/year mirror ContainerSummary
}

struct VideoDetail {                              // VideoDetailView payload
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
    var liveEvent: LiveEventInfo?                 // start/end/isEventLive, live only
}

struct VideoChapter: Identifiable, Hashable { let id: String; let title: String; let startSeconds: Double }
struct LiveEventInfo { var startsAt: Date?; var endsAt: Date?; var isEventLive: Bool }
```

New `Catalog` parsers: `recentVideos(from:)` and `livestreams(from:)` for the
REST shapes; `videoContainers(from:)` for the per-artist legacy list; and
`videoDetail(from:id:)` for `catalog.container&vdisp=1`. The existing tolerant
`JSON` accessor handles casing variance; exact keys are confirmed in Step 1.

### Favorites (`FavoritesStore.swift`)

Add a third collection mirroring `FavShow` (same persistence file/idiom):

```
struct FavVideo: Codable, Identifiable {
    var id: String          // container/release id
    var videoSku: Int
    var title: String
    var artistName: String
    var dateText: String?
    var isLive: Bool
    var imagePath: String?
    var savedAt: Date
}
```

Plus `isVideoFavorited(_:)`, `toggleVideo(_:)`, `videos: [FavVideo]`.

### Resume position (`VideoProgressStore.swift`, new — `Player/`)

Mirrors `PlaybackStateStore`: a `@MainActor @Observable` store persisting a small
map to `~/Library/Application Support/AppleNugs/videoprogress.json`:

```
struct VideoProgress: Codable, Identifiable {
    var id: String          // container/release id
    var videoSku: Int
    var title: String
    var artistName: String
    var imagePath: String?
    var positionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date
}
```

API: `progress(for:) -> VideoProgress?`, `record(_:)` (throttled while playing),
`markFinished(_:)` (clears near-completion), `recent: [VideoProgress]` (newest
first, finished items excluded) for the Continue Watching strip. Livestreams are
**not** recorded (no meaningful resume).

## Player & audio/video coordination (`Player/`)

New **`VideoPlayerService`** — `@MainActor @Observable final class`, created in
`AppModel` (`let video = VideoPlayerService(audio: player, client: client,
progress: videoProgress)`), reached via the existing `@Environment(AppModel.self)`.

- Owns its **own** `AVPlayer` (single item; no queue). State: `current:
  VideoDetail?`, `isPlaying`, `currentTime`, `duration`, `isLive`, `atLiveEdge`,
  `status`, `error`, `availableQualities`, `selectedQuality`.
- `play(_ video: VideoDetail)`: resolve the stream (`resolveVideoStream`), build
  an `AVURLAsset` with the existing `User-Agent`/`Referer` headers, set the item,
  seek to a resume position (VOD) or the live edge (live), play. On start it
  **pauses the audio `PlayerService`** (remembering whether it was playing) via a
  small **arbiter** and takes over `MPNowPlayingInfoCenter` /
  `MPRemoteCommandCenter`. On stop/close it relinquishes Now Playing and
  **resumes audio** if it had been playing.
- Transport: `togglePlayPause`, `seek(to:)`, `seek(by:)`, `seekToLiveEdge()`.
- **Quality override**: parse the master `.m3u8` variants once for the menu;
  apply a cap via `AVPlayerItem.preferredMaximumResolution` /
  `preferredPeakBitRate` (Auto = unset). No playlist swapping.
- **Live webcasts**: render pre-event ("starts in …" from `eventStart`),
  live (LIVE badge + jump-to-live), and ended states; use `isEventLive` +
  event timestamps. PPV webcasts resolve via `vidPlayer.aspx`.
- Position recording into `VideoProgressStore` (throttled ~5 s; on pause/close;
  `markFinished` past ~95 %).

The **arbiter** is the only new cross-cutting concern: a tiny rule that whoever
starts pauses the other and claims Now Playing, so the two services never both
push to `MPNowPlayingInfoCenter`. `TransportBar` stays audio-only and is never
asked to render video (the Receiver faceplate VU is therefore never an issue).

## Surface (`Views/` + `Theme/`)

- **`Theme/Components/VideoPlayerSurface.swift`** (new) — an `NSViewRepresentable`
  wrapping AppKit **`AVPlayerView`** bound to `VideoPlayerService`'s `AVPlayer`.
  This gives native scrubber, volume, **fullscreen**, AirPlay, and (free) PiP, so
  we do not rebuild video transport.
- **`Views/VideoDetailView.swift`** (new; clones `AlbumDetailView`) — inline
  `VideoPlayerSurface` at the top; title / artist / date / venue / description;
  a tappable **chapter** list (seek on tap); a save (favorite) star; a resume
  affordance ("Resume from MM:SS"); a quality menu. Loads via `.task`.
- **`Theme/Components/VideoThumbnail.swift`** (new; clones `ShowCard`) — 16:9
  poster (`videoImage`/`vodPlayerImage`) + play-circle overlay (theme accent) +
  LIVE / duration / 4K badges. Falls back to the themed `CoverArt` placeholder.
- **`Views/VideosView.swift`** (new) — the sidebar destination:
  - **Continue Watching** strip (when `videoProgress.recent` is non-empty),
  - **Live & Upcoming** (webcasts, when any),
  - **On-Demand** grid (`LazyVGrid` of `VideoThumbnail`, paged from
    `/releases/recent?contentType=video`),
  - themed empty state when nothing loads.

All themed via the existing token system (all four themes).

## Search & per-artist integration

- **Search** (`SearchView` / `SearchModel`): add a `.video(id:, sku:)` case to
  `SearchModel.Item.Kind` (or a `hasVideo` flag on container items derived from
  `vdisp=1` product info), routed to `Route.video`. A "Videos" results section
  when present; right-click "Add to Favorites" like other rows.
- **Per-artist** (`ArtistDetailView`): a "Videos" disclosure section alongside
  Releases / Shows, sourced from the per-artist legacy call and rendered with
  `VideoThumbnail`. Right-click save on rows.

## Navigation (`App/`)

- `UIState.swift`: add `SidebarItem.videos`; add `Route.video(id: String, title:
  String?, sku: Int, isLive: Bool)`.
- `RootView.swift`: a text-only **Videos** sidebar entry (matching the existing
  no-icon sidebar); `detailRoot` branch → `VideosView`;
  `navigationDestination(Route.video)` → `VideoDetailView`.
- `AppModel.swift`: own `VideoPlayerService` + `VideoProgressStore`; inject via
  environment; wire the audio/video arbiter; extend `FavoritesStore` use.

## Files

**New**
- `AppleNugs/Player/VideoPlayerService.swift` — own `AVPlayer`, arbiter, quality, live, resume recording.
- `AppleNugs/Player/VideoProgressStore.swift` — Continue Watching persistence.
- `AppleNugs/Views/VideosView.swift` — sidebar Videos destination.
- `AppleNugs/Views/VideoDetailView.swift` — inline player + metadata + chapters.
- `AppleNugs/Theme/Components/VideoPlayerSurface.swift` — `AVPlayerView` wrapper.
- `AppleNugs/Theme/Components/VideoThumbnail.swift` — 16:9 video card.

**Changed**
- `AppleNugs/Core/NugsConstants.swift` — add `catalogV1Base = "https://catalog.nugs.net/api/v1"`.
- `AppleNugs/Core/NugsClient.swift` — `catalogV1Get`; `resolveVideoStream`; per-artist video call (`videoReleaseType=6`); video catalog/livestream/featured fetchers.
- `AppleNugs/Core/Catalog.swift` — `VideoSummary`/`VideoDetail`/`VideoChapter`/`LiveEventInfo` + parsers.
- `AppleNugs/Core/FavoritesStore.swift` — `FavVideo` collection + API.
- `AppleNugs/App/UIState.swift` — `SidebarItem.videos`, `Route.video`.
- `AppleNugs/App/AppModel.swift` — own video services; arbiter wiring.
- `AppleNugs/Views/RootView.swift` — sidebar entry + routes.
- `AppleNugs/Views/ArtistDetailView.swift` — per-artist Videos section.
- `AppleNugs/Views/SearchView.swift` — video results + context menu.
- `AppleNugs/Views/FavoritesView.swift` — Videos subsection.
- (xcodegen picks up new files via `project.yml` source globs; run `xcodegen generate`.)

## Build order (de-risked)

1. **Live API probe** (Step 1, user's account): confirm (a) the **legacy
   bigriver video stream plays DRM-free in `AVPlayer`** — the gating risk; (b)
   `catalog.container&vdisp=1` field casing + video SKU; (c)
   `/releases/recent?contentType=video` and `/livestreams` item shapes.
2. Constants + `catalogV1Get` + `resolveVideoStream` + `Catalog` video parsers.
3. `VideoPlayerService` + `VideoPlayerSurface` + audio/video arbiter (play one
   known VOD end to end, fullscreen, audio pauses/resumes).
4. `VideoDetailView` (inline player, chapters, quality menu, resume).
5. `VideosView` (Continue Watching + Live & Upcoming + On-Demand grid) + sidebar/route.
6. Per-artist Videos section.
7. Search + Favorites integration.
8. Resume / Continue Watching store wiring.
9. Live-webcast specifics (live edge, pre/post states, PPV via `vidPlayer.aspx`).

## Edge cases

- **No video access in plan** (`subPlayer.aspx` returns no `streamLink` / access
  flag denies): themed "not included in your plan — available on nugs.net" state.
- **PPV without UGUID / not owned**: "purchase on nugs.net" state; no buy flow.
- **Stream URL expired** (signed, time-bound): on `AVPlayer` failure, re-resolve
  once before surfacing an error (mirrors audio's self-heal).
- **Upcoming webcast not started**: countdown state, play disabled until live.
- **Webcast ended / replay window expired**: ended state; if it converted to
  time-limited VOD it simply appears as VOD.
- **Resume past end / finished**: cleared by `markFinished`; no stale resume.
- **Switching to a video while audio plays**: audio pauses; on leaving the video
  it resumes if it was playing. Starting audio while a video plays stops the video.
- **4K requested but plan/title lacks it**: quality menu only lists variants the
  master playlist actually advertises.
- **Empty browse feed / network error**: themed empty/error state in `VideosView`.

## Verification

No automated test target exists; verify manually (as themes / Favorites were):
1. Build succeeds (`xcodegen generate && xcodebuild … build`), no warnings.
2. **Step-1 gate:** a known VOD `.m3u8` from `subPlayer.aspx` plays in `AVPlayer`
   with no FairPlay error. (If it fails, halt and re-scope.)
3. Videos sidebar: On-Demand grid loads; a video opens in `VideoDetailView` and
   plays inline; fullscreen works; chapters seek.
4. Starting a video pauses audio; leaving it resumes audio; Now Playing reflects
   whichever is active (never both).
5. Quality menu lists real variants; selecting one caps resolution; Auto adapts.
6. Live & Upcoming lists webcasts with correct upcoming/live/ended states; a live
   webcast plays at the live edge with a LIVE badge.
7. Save a video → appears in Favorites; relaunch → persists.
8. Resume: leave a VOD partway, reopen → offered/resumes; Continue Watching strip
   shows it; finishing clears it.
9. Switch themes → Videos grid, detail, and badges adopt each theme.

## Open questions to confirm in Step 1 (none block the design)

- Exact JSON casing/keys for `catalog.container&vdisp=1` video fields and for the
  REST `/releases/recent` & `/livestreams` items.
- The exact REST **base host** for the `/releases/*` endpoints: `/livestreams`
  was verified live at `catalog.nugs.net/api/v1`, but the bundle showed
  `/releases/recent` against a sibling host (`api.nugs.net`). Confirm whether all
  v1 browse paths share `catalogV1Base` or `/releases/*` needs its own constant.
- Whether `vdisp=1` alone suffices or `HLS=1` is also needed on this account.
- Whether the legacy bigriver `.m3u8` needs any header/cookie beyond the URL
  token for `AVPlayer` (and the definitive DRM answer).
- `/releases/recent` paging behavior (does it terminate / expose a total) and how
  deep the "recent" video window goes, to decide if the per-artist legacy
  aggregation is needed for completeness in a later version.
