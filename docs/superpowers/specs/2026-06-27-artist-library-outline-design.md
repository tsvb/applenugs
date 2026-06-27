# Artist page redesign — "The Crate" library outline

- **Date:** 2026-06-27
- **Status:** Approved design, pre-implementation
- **Branch:** `artist-library-outline`
- **Touches:** `AppleNugs/Views/ArtistDetailView.swift` (rework) + new view files

## Problem

The artist detail page ([ArtistDetailView.swift](../../../AppleNugs/Views/ArtistDetailView.swift))
is a single vertical scroll of three stacked sections in a fixed order: a
**Releases** cover grid, then a **Videos** poster grid, then **Shows** grouped
by year. When an artist has many videos (e.g. Goose: 2 releases, 100 videos, 98
shows) the 16:9 video grid becomes a ~100-item wall that dominates the page —
the releases read as a tiny preamble and the 98 shows are buried far below the
video wall, effectively unreachable by scroll. Three rich content types compete
in one column and whichever is largest wins.

## Goals

- No single content type can wall off the others; all are reachable at a glance.
- Fast access to **all three** types (the user visits for different reasons each
  time).
- A distinctive, on-brand screen — lean into the app's existing media-player DNA
  (the REELS playlist column, the EQ/VU meters) rather than a generic poster grid.
- Scale to any artist (2 items or 500) with no performance cost.

## Non-goals

- No new API endpoints or data sources (reuse `artistShows` + `artistVideos`).
- No content downloading/offline (out of scope for the whole app).
- No change to playback, routing targets, or the favorites model.

## Direction (decided in brainstorming)

A **Winamp-style media library outline**: the artist page becomes a single
expandable tree. Top-level category nodes (**Albums / Videos / Shows**) expand in
place; Videos and Shows nest a second level by **year**; leaf rows are dense,
single-line "crate" rows (tiny thumbnail · title · `LIVE`/`4K` badges · date).
The whole thing sits under **player chrome**: a reused `EqualizerBars` VU strip +
an LCD-style marquee header + the Follow control.

Locked decisions:

| Decision | Choice |
| --- | --- |
| Layout | Single expandable outline (one column), not a two-pane selector |
| Default expansion on load | **All collapsed** — category headers + counts only |
| Videos grouping | **By year**, mirroring Shows |
| Albums grouping | Flat (usually few) |
| Row tap | Navigate to detail (existing routes) — *not* double-click-to-play |
| Homage level | Themed / accent-tinted (no literal Winamp green) |
| Column sorting | Deferred (nice-to-have) |
| Shows pagination | Load next page on scroll to the end of Shows |

## Anatomy

The diagram below shows the outline with several nodes **expanded** to illustrate
the full hierarchy. On load the page is **all collapsed** — only the three
category rows (Albums / Videos / Shows) with their counts are visible.

```
┌──────────────────────────────────────────────┐
│ ▮▮▯  GOOSE — 100 VIDEOS · 98 SHOWS · 2 ALBUMS ★│  player header: VU + LCD marquee + Follow
├──────────────────────────────────────────────┤
│ ▸  ◉ Albums                                  2 │  category node (collapsed)
│ ▾  ▶ Videos                                 100 │  category node (expanded)
│      ▾ 2026                                  18 │    year node (expanded)
│         1  ▦  Live from MSG            4K  06/19│      leaf rows (dense)
│         2  ▦  RBC Amphitheatre             06/13│
│      ▸ 2025                                  40 │    year node (collapsed)
│      ▸ 2024                                  42 │
│ ▾  🎤 Shows                                  98 │
│      ▾ 2024                                  31 │
│         1  ▣  Solid Sound Festival         06/29│
│      ▸ 2023                                  42 │
└──────────────────────────────────────────────┘
```

(Icons above are placeholders for SF Symbols — see Components.)

## Components & files

All new view files live under a new group `AppleNugs/Views/ArtistLibrary/`.
Theming uses existing tokens only (`palette.*`, `type.*`, `caps`,
`effectiveAccent(art:)`).

### `CrateItem.swift` — model + mapping (new)

```swift
enum CrateKind { case album, video, show }

struct CrateItem: Identifiable, Hashable {
    let id: String
    let kind: CrateKind
    let title: String
    let dateText: String?   // short form for the trailing cell, e.g. "06/19/26"
    let date: Date?         // sort key
    let year: Int?          // grouping key; nil → "Unknown" bucket
    let imageURL: URL?
    let isLive: Bool
    let has4K: Bool
    let route: Route        // .album for album/show, .video for video
}
```

Mapping (pure functions, no I/O):

- **Albums** ← `containers.filter { !$0.isLiveShow }` → `kind: .album`,
  `route: .album(id:title:)`, no year grouping (flat, original order).
- **Shows** ← `containers.filter(\.isLiveShow)` → `kind: .show`,
  `route: .album(id:venue ?? title)`, `year` from `ContainerSummary.year`.
- **Videos** ← `videos` (`VideoSummary`) → `kind: .video`,
  `route: .video(id:title:)`, `year` from the video's `performanceDate`/
  `eventStart`, `isLive`/`has4K` carried through.

### `CrateHeader.swift` — player chrome (new)

`HStack` of:

1. `EqualizerBars(isPlaying: app.player.isPlaying)` — reused as-is (themed,
   animates only while audio plays, free when idle). *Optional* generalization to
   accept a bar count for a wider strip is a nice-to-have, not required.
2. **LCD marquee**: an inset dark panel (a `RoundedRectangle` filled darker than
   `palette.raised`) holding a mono (`type.numeric`) accent-colored line:
   `"<ARTIST> — N VIDEOS · N SHOWS · N ALBUMS"`. v1 truncates if it overflows;
   the horizontal scrolling animation is a deferred nice-to-have.
3. The existing **Follow** button (unchanged behavior; restyled compact to fit).

### `CrateOutline.swift` — the tree (new)

Renders the nested disclosure tree inside the page's `ScrollView` +
`LazyVStack(alignment: .leading)`, following the existing `yearSection` pattern
(nested `DisclosureGroup`s rather than `List`/`OutlineGroup`, to keep full theme
control and match current code).

Expansion state owned here (or hoisted to `ArtistDetailView`):

```swift
@State private var expandedCategories: Set<CrateKind> = []        // empty = all collapsed
struct YearKey: Hashable { let kind: CrateKind; let year: Int }
@State private var expandedYears: Set<YearKey> = []               // disambiguates Videos 2024 vs Shows 2024
```

Node hierarchy:

- **Category node** — chevron + SF Symbol + name (uppercased when
  `caps.contains(.condensedHeaders)`) + right-aligned mono count. Tap toggles
  `expandedCategories`. Icons: Albums `opticaldisc`, Videos `play.rectangle`,
  Shows `music.mic`.
- **Year node** (Videos, Shows) — indented; chevron + year + mono count. Tap
  toggles `expandedYears`. Albums skip this level (leaf rows directly).
- **Leaf row** → `CrateRow`.

A category/year with 0 items is omitted entirely.

### `CrateRow.swift` + `CrateThumb.swift` — dense leaf row (new)

`CrateRow`: `NavigationLink(value: item.route)` wrapping an `HStack`:

- index (mono, 1…n within its group) — Winamp numbering;
- `CrateThumb(url:kind:)` — tiny `AsyncImage`, **16:9 (~40×24)** for `.video`,
  **square (~24×24)** for `.album`/`.show`; rounded 2–3pt; placeholder = raised
  fill + SF Symbol; reuses the phase handling from the current `CoverArt`;
- title (`type.body`, `lineLimit(1)`, truncation + `.help(title)`);
- inline badges: `LIVE` (when `isLive`), `4K` (when `has4K`) — accent pills;
- `Spacer`;
- trailing date (`dateText`, `type.numeric`, secondary).

`buttonStyle(.plain)`. Context menu **per kind** (matches today):

- `.show` → `app.favorites.toggleShow(...)` / `isShowFavorited`;
- `.video` → `app.favorites.toggleVideo(FavVideo(... videoSku: 0 ...))` /
  `isVideoFavorited`;
- `.album` → **no** favorites menu (albums aren't favoritable today).

### `ArtistDetailView.swift` — rework

Keep all state and loading (`containers`, `videos`, `loading`, `error`,
`canLoadMore`, `load(reset:)`, `loadVideos()`, the `releases`/`shows`/
`showsByYear` computeds, `.task(id: artist.id)`). Replace the `body`'s three
stacked grids with: `CrateHeader` + `CrateOutline`. Keep the outer
`ScrollView`/padding/background, `navigationTitle`, and the loading/error
overlays (`ContentUnavailableView`). The standalone `CoverArt` struct is removed
if it has no remaining users after the rework (otherwise left in place).

## Data flow & pagination

- Counts in category headers come from the loaded in-memory arrays
  (`releases.count` / `videos.count` / `shows.count`) — same source as today, so
  they reflect what's loaded (honest caveat retained: `canLoadMore == true` means
  more shows exist server-side than are counted yet).
- Videos load once (`loadVideos()`), all at once — no pagination.
- Shows/releases paginate via `load(reset:false)`. **Trigger:** when the last
  rendered leaf inside the Shows category appears (`onAppear` on the final show
  row) and `canLoadMore`, kick the next page; show a small footer `ProgressView`
  while `loading`. Fallback if `onAppear`-driven loading proves awkward inside the
  disclosure: a "Load more shows" button under the Shows node (current behavior).

## Theming (themed / accent-tinted)

- Colors: `palette.base/raised/hairline/textPrimary/textSecondary`,
  `effectiveAccent(art:)` for VU bars, LCD text, badges, selected/active accents.
- Type: `type.section` for category labels, `type.body` for titles,
  `type.numeric` for index/counts/dates/LCD.
- `caps.contains(.condensedHeaders)` → uppercase category labels (as today).
- Coherent across all four themes (Tape Room / Soundboard / Shoebox / The
  Receiver). No literal green.

## Edge cases

- Empty category → node omitted. If the artist has only one non-empty category,
  only that node shows.
- Video load failure → Videos node absent (count 0), never blocks shows (as today).
- Entirely empty / load error with nothing loaded → existing
  `ContentUnavailableView` overlay.
- Item with no parseable date/year → grouped under an **"Unknown"** year node
  sorted last (rare).
- Long titles → single line, truncated, `.help` tooltip.
- Live-webcast SKU routing limitation is pre-existing and unchanged by this work.

## Accessibility

- Category/year disclosure rows: labeled "{name}, {count} items" with
  expanded/collapsed state (via `DisclosureGroup` semantics or explicit
  `accessibilityLabel`/`.isExpanded`).
- Leaf rows: `accessibilityLabel("{title}, {kind word}, {date}")`.
- VU strip: `accessibilityHidden(true)`.
- LCD marquee: static `accessibilityLabel` with the summary text.
- Preserves the VoiceOver parity established in prior a11y work.

## Performance

`LazyVStack` + `DisclosureGroup`: collapsed nodes don't build their children;
expanding a year builds only that year's rows. With all-collapsed default, the
initial page renders just three category rows. Tiny thumbnails are small
`AsyncImage`s served from the already-configured shared `URLCache`. The 100-video
wall is structurally impossible.

## Scope

**v1 (this spec):** player header (reused VU + static LCD + Follow); the
all-collapsed expandable outline (Albums flat; Videos & Shows by year); dense
leaf rows with tiny thumbnails, `LIVE`/`4K` badges, navigation, and per-kind
favorites menu; shows pagination on scroll; full theming + a11y.

**Deferred (nice-to-have, explicitly out of v1):** clickable column sorting
(title/date/kind); the LCD marquee *scrolling* animation; a wider/variable VU
strip; remembering expansion state across visits.

## Verification

No automated test target exists (known gap). Verification is:

1. **Build clean** under `SWIFT_STRICT_CONCURRENCY=complete` (must stay
   warning/error-free) — build in a worktree with a fresh `-derivedDataPath`.
2. **Manual run** against a content-rich artist (e.g. Goose):
   - loads all-collapsed showing Albums/Videos/Shows with correct counts;
   - expand/collapse categories and years; counts and grouping correct;
   - tiny thumbnails load; `LIVE`/`4K` badges appear; long titles truncate;
   - row tap navigates (album/show → album detail, video → video detail);
   - favorites context menu toggles for shows and videos; albums have none;
   - scrolling to the end of Shows loads the next page (footer spinner);
   - all four themes render coherently;
   - VoiceOver reads category counts and row labels; VU is hidden.
