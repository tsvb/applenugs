# Favorites / Library — Design

**Date:** 2026-06-13
**Status:** Approved (design); pending implementation plan
**Component:** AppleNugs (native macOS SwiftUI nugs.net client)

## Goal

Let the user build a personal library on top of the catalog: follow **artists**
and save **shows**, then reach them again from a dedicated Favorites view and
from the Home landing. This turns the app from a browser of someone else's
catalog into "my" library.

## Scope

**In scope (v1):**
- Favorite (follow) artists.
- Favorite (save) shows.
- A persisted, local store of favorites.
- A dedicated **Favorites** view in the sidebar.
- A **Favorites strip** on Home.
- Favoriting from: artist detail header, show detail header, the now-playing
  block, and right-click context menus on rows.

**Out of scope (v1):**
- Favoriting individual tracks (no clean per-track UI today; complicates the
  queue).
- Cross-device sync (favorites are local to this Mac, like the login session).
- Reordering, folders, smart playlists, or tags. Two flat collections only.

## Data model & persistence

A new `FavoritesStore` — `@MainActor @Observable final class` — persisting to
`~/Library/Application Support/AppleNugs/favorites.json` (atomic write, chmod
600), mirroring the existing `SessionStore` idiom. It is created in `AppModel`
as `let favorites: FavoritesStore` so views reach it through the
`@Environment(AppModel.self)` they already hold. Being `@Observable`, a toggle
updates every star and the Favorites view reactively.

Two collections, each entry storing enough to render and navigate without a
re-fetch, ordered newest-saved-first via `savedAt`:

```
struct FavArtist: Codable, Identifiable { var id: String; var name: String; var savedAt: Date }
struct FavShow:   Codable, Identifiable {
    var id: String          // catalog container id
    var title: String       // e.g. "03/12/20 Park Theater, Las Vegas, NV"
    var artistName: String
    var dateText: String?
    var venue: String?
    var imagePath: String?  // resolves via NugsConstants.imageURL
    var savedAt: Date
}
```

`FavoritesStore` API:
- `isArtistFavorited(_ id: String) -> Bool`
- `toggleArtist(_ entry: FavArtist)` (add if absent, remove if present)
- `isShowFavorited(_ id: String) -> Bool`
- `toggleShow(_ show: FavShow)`
- `artists: [FavArtist]` (alphabetical accessor) / `shows: [FavShow]` (newest first)

Favorites **persist across logout** (they are catalog references, not account
secrets). Single-user app, so no per-account partitioning.

### Required change: carry the show id on the queue

The now-playing star saves the *show currently playing*, which needs the show's
container id. `QueueTrack` today is `{ trackId, title, artist, show, artworkPath }`
with no container id. Add `var showId: String? = nil` to `QueueTrack` and
populate it where tracks are built from a show (`AlbumDetailView.queueTracks`,
and any other album-originated enqueue). A `FavShow` is then reconstructable
from the now-playing track: `id = showId`, `title = show`, `artistName = artist`,
`imagePath = artworkPath` (date/venue already live inside the nugs show title).
The now-playing star is **disabled when `showId` is nil** (e.g. a single-track
search hit played in place).

## Interactions (no per-row star icons)

Per the clean/no-icon direction, stars do **not** appear on every list row.

- **Artist detail header** (`ArtistDetailView`): a star toggle that follows /
  unfollows the artist. Filled in the theme accent when followed.
- **Show detail header** (`AlbumDetailView`): a star toggle beside "Play all"
  that saves / unsaves the show (built from `AlbumDetailModel`, which has full
  metadata).
- **Now-playing block** (`TransportBar`, and the faceplate's `FaceplateTransport`):
  a small star to save the playing show; disabled when `showId` is nil.
- **Right-click context menus**: "Add to Favorites" / "Remove from Favorites"
  on artist rows (`ArtistListView`), show rows (`ArtistDetailView`), and search
  results (`SearchView`) — quick saving without drilling in.

## Favorites view (new sidebar destination)

Sidebar becomes **Home · Artists · Favorites · Search**, rendered as **text-only
labels with no leading icons** (drop the existing SF Symbols from Home/Artists/
Search too, for consistency). New `UIState.SidebarItem.favorites`; `RootView`
`detailRoot` routes it to a new `FavoritesView`.

Layout (the approved "stacked sections"):
- **Artists** — a wrapped grid of text chips (alphabetical). Tap → `Route.artist`
  (reconstruct `ArtistEntry(id:name:)` from `FavArtist`).
- **Saved shows** — a cover-art grid (newest saved first) using a reusable
  `ShowCard` (cover via existing `CoverArt` + caption). Tap →
  `Route.album(id:title:)`.
- **Empty state** — themed `ContentUnavailableView`-style message: "Nothing
  saved yet — star an artist or a show to keep it here."

All themed via the existing token system (works across all four themes).

## Home strip

When favorites exist, a **"Favorites · See all ›"** section appears on Home,
placed right after the Continue-listening hero:

```
greeting → resume hero → Favorites strip (See all ›) → entry tiles → From the crate
```

The strip shows a few followed artists (chips) and the most recent saved shows
(`ShowCard`s); "See all ›" selects the Favorites sidebar destination. The random
"From the crate" sampler stays below as discovery. When there are no favorites,
the strip is hidden and Home looks as it does today.

## Files

**New**
- `AppleNugs/Core/FavoritesStore.swift` — store + `FavArtist` / `FavShow` + persistence.
- `AppleNugs/Views/FavoritesView.swift` — the stacked Favorites destination.
- `AppleNugs/Theme/Components/ShowCard.swift` — reusable cover-art show card (Favorites grid + Home strip).

**Changed**
- `AppleNugs/Player/PlayerService.swift` — add `showId` to `QueueTrack`; populate at album-originated enqueue sites.
- `AppleNugs/App/AppModel.swift` — add `let favorites = FavoritesStore()`.
- `AppleNugs/App/UIState.swift` — add `SidebarItem.favorites`.
- `AppleNugs/Views/RootView.swift` — text-only sidebar incl. Favorites; route `.favorites` → `FavoritesView`.
- `AppleNugs/Views/ArtistDetailView.swift` — header follow star; context menu on show rows.
- `AppleNugs/Views/AlbumDetailView.swift` — header save star; pass `showId` into `queueTracks`.
- `AppleNugs/Views/ArtistListView.swift` — context menu on artist rows.
- `AppleNugs/Views/SearchView.swift` — context menu on artist + show results.
- `AppleNugs/Views/TransportBar.swift` (+ `Theme/Transport/FaceplateTransport.swift`) — now-playing save star.
- `AppleNugs/Views/HomeView.swift` — Favorites strip.

## Edge cases

- **No favorites:** Favorites view shows the empty state; Home strip hidden.
- **Now-playing with no show id** (single-track search play): star disabled.
- **Favorited show/artist later unavailable in catalog:** the saved entry still
  renders (we stored the metadata); navigating may 404 — surfaced by the
  existing detail-view error states, no special handling.
- **Duplicate toggles:** `toggle*` is idempotent by id.
- **Cover art missing:** `ShowCard` falls back to the existing themed `CoverArt`
  placeholder.

## Verification

No automated test target exists; verify manually (matches how the themes/Home
were verified):
1. Build (`xcodebuild … build` succeeds, no warnings).
2. Star an artist and a show from their detail headers → stars fill; both appear
   in the Favorites view and the Home strip.
3. Save the playing show from the now-playing star; confirm it disables for a
   single-track search play.
4. Right-click an artist row and a search result → add/remove works.
5. Relaunch the app → favorites persist; toggling in one place updates
   everywhere (reactive).
6. Switch themes → Favorites view and strip adopt each theme.
