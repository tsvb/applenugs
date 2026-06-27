# Artist library outline ("The Crate") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the artist detail page's three stacked grids (a 100-item video poster wall that buries shows) with a Winamp-style expandable library outline: Albums / Videos / Shows as collapsible nodes, Videos & Shows nested by year, dense leaf rows under a VU + LCD-marquee player header.

**Architecture:** A new `CrateItem` value type unifies the existing `ContainerSummary` (releases + shows) and `VideoSummary` into one row model. Small focused SwiftUI views compose bottom-up — `CrateThumb` → `CrateRow` → `CrateOutline` (nested `DisclosureGroup`-style state in a `LazyVStack`) and a `CrateHeader`. `ArtistDetailView` keeps all its existing data-loading and is reworked to render header + outline. No API, routing-target, or favorites-model changes.

**Tech Stack:** Swift 5 language mode (strict concurrency = complete), SwiftUI (macOS 14), AVFoundation already in place. XcodeGen-generated project. No third-party deps.

## Global Constraints

- **Swift 5 mode, `SWIFT_STRICT_CONCURRENCY = complete`** — the codebase must stay warning- and error-free under it (it currently is). New `@MainActor`/SwiftUI views inherit main-actor isolation; pure model code (`CrateItem`) must be `Sendable`-safe (value types only).
- **XcodeGen owns the project** — `AppleNugs.xcodeproj`, `Info.plist`, `AppleNugs.entitlements` are generated and git-ignored. After adding/removing any source file, run `xcodegen generate` before building. Never hand-edit the project.
- **The target globs the `AppleNugs/` folder** (`sources: [AppleNugs]`), so new files only need `xcodegen generate` to be picked up — no manual project membership.
- **No XCTest target exists** (known gap; the approved spec keeps it that way). The per-task gate is therefore: **the app compiles** + a SwiftUI `#Preview` for visual check where practical. The final task is a strict-concurrency clean build + a manual run checklist. The `\.theme` environment defaults to `Theme.tapeRoom` and `\.artColor` defaults to `nil`, so previews render without injecting environment.
- **Theming via tokens only** — `theme.palette.{base,raised,hairline,textPrimary,textSecondary,accent}`, `theme.type.{numeric,body,section}(_:)`, `theme.caps.contains(.condensedHeaders)`. No hard-coded colors. Themed/accent-tinted homage — **no literal Winamp green**.
- **Build (compile) command** used by every task's verify step:
  ```sh
  cd /Users/tim/applenugs && xcodegen generate && \
  xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs \
    -configuration Debug -destination 'platform=macOS' build
  ```
  Expected tail: `** BUILD SUCCEEDED **`
- **Branch:** all work lands on `artist-library-outline` (already checked out). Commit after each task.

## File Structure

New group `AppleNugs/Views/ArtistLibrary/`:

| File | Responsibility |
| --- | --- |
| `CrateItem.swift` | `CrateKind` enum, `CrateItem` row model, builders from `ContainerSummary`/`VideoSummary`, `groupedByYear()` helper. Pure value types. |
| `CrateThumb.swift` | Tiny thumbnail view — 16:9 for video, square for album/show, with placeholder. |
| `CrateRow.swift` | One dense leaf row: index · thumb · title · `LIVE`/`4K` badges · date; navigation + per-kind favorites context menu. |
| `CrateHeader.swift` | Player chrome: reused `EqualizerBars` VU + LCD summary panel + Follow button. |
| `CrateOutline.swift` | The expandable tree: category nodes → year nodes → `CrateRow`; expansion state; shows pagination footer. |

Modified:

| File | Change |
| --- | --- |
| `AppleNugs/Views/ArtistDetailView.swift` | Body reworked to `CrateHeader` + `CrateOutline`; removes the old header/`sectionTitle`/`releaseGrid`/`videoGrid`/`yearSection`/`yearBinding`/`expandedYears`/`showsByYear`; keeps `load`/`loadVideos`/state. `CoverArt` removed if unused. |

---

### Task 1: `CrateItem` model, builders, grouping

**Files:**
- Create: `AppleNugs/Views/ArtistLibrary/CrateItem.swift`

**Interfaces:**
- Consumes: `ContainerSummary`, `VideoSummary` (Catalog.swift), `Route` (UIState.swift), `Catalog.parseDate(_:)`.
- Produces:
  - `enum CrateKind { case album, video, show }` with `var icon: String`, `var label: String`, `var word: String`.
  - `struct CrateItem: Identifiable, Hashable` with `rawID, kind, title, artistName, venue, dateText, date, imageURL, isLive, has4K, route`, computed `id`, computed `year: Int?`.
  - `static func album(_:artist:)`, `show(_:artist:)`, `video(_:artist:)` builders.
  - `Array<CrateItem>.groupedByYear() -> [(year: Int?, items: [CrateItem])]`.

- [ ] **Step 1: Write `CrateItem.swift`**

```swift
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
    static func album(_ c: ContainerSummary, artist: String) -> CrateItem {
        CrateItem(rawID: c.id, kind: .album, title: c.title,
                  artistName: c.artistName ?? artist, venue: c.venue,
                  dateText: c.dateText, date: c.date, imageURL: c.imageURL,
                  isLive: false, has4K: false,
                  route: .album(id: c.id, title: c.title))
    }

    static func show(_ c: ContainerSummary, artist: String) -> CrateItem {
        let display = c.venue ?? c.title
        return CrateItem(rawID: c.id, kind: .show, title: display,
                  artistName: c.artistName ?? artist, venue: c.venue,
                  dateText: c.dateText, date: c.date, imageURL: c.imageURL,
                  isLive: false, has4K: false,
                  route: .album(id: c.id, title: display))
    }

    static func video(_ v: VideoSummary, artist: String) -> CrateItem {
        let d = Catalog.parseDate(v.performanceDate) ?? v.eventStart
        return CrateItem(rawID: v.id, kind: .video, title: v.title,
                  artistName: v.artistName ?? artist, venue: nil,
                  dateText: v.dateText, date: d, imageURL: v.imageURL,
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
```

- [ ] **Step 2: Generate + build**

Run the Global Constraints build command.
Expected: `** BUILD SUCCEEDED **`. (Open the "CrateItem mapping" preview in Xcode: the album row shows "—" for year, the show shows 2024, the video shows 2026.)

- [ ] **Step 3: Commit**

```sh
git add AppleNugs/Views/ArtistLibrary/CrateItem.swift
git commit -m "Add CrateItem model + ContainerSummary/VideoSummary mapping"
```

---

### Task 2: `CrateThumb` tiny thumbnail

**Files:**
- Create: `AppleNugs/Views/ArtistLibrary/CrateThumb.swift`

**Interfaces:**
- Consumes: `CrateKind` (Task 1), `\.theme`.
- Produces: `struct CrateThumb: View { let url: URL?; let kind: CrateKind }` — fixed-size (video 40×24, others 24×24), rounded, with placeholder.

- [ ] **Step 1: Write `CrateThumb.swift`**

```swift
import SwiftUI

/// Tiny row thumbnail. Videos are 16:9-ish (wider); albums/shows are square.
/// A miss/placeholder shows a kind glyph so empty rows still read.
struct CrateThumb: View {
    let url: URL?
    let kind: CrateKind

    @Environment(\.theme) private var theme

    private var isWide: Bool { kind == .video }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: isWide ? 40 : 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(theme.palette.raised)
            .overlay(
                Image(systemName: kind == .video ? "play.fill" : "music.note")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.palette.accent.opacity(0.7))
            )
    }
}

#Preview("CrateThumb") {
    HStack(spacing: 12) {
        CrateThumb(url: nil, kind: .video)
        CrateThumb(url: nil, kind: .album)
        CrateThumb(url: nil, kind: .show)
    }
    .padding()
}
```

- [ ] **Step 2: Generate + build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`. (Preview shows one wide + two square placeholder tiles with glyphs.)

- [ ] **Step 3: Commit**

```sh
git add AppleNugs/Views/ArtistLibrary/CrateThumb.swift
git commit -m "Add CrateThumb tiny row thumbnail"
```

---

### Task 3: `CrateRow` dense leaf row

**Files:**
- Create: `AppleNugs/Views/ArtistLibrary/CrateRow.swift`

**Interfaces:**
- Consumes: `CrateItem`, `CrateKind` (Task 1), `CrateThumb` (Task 2), `AppModel` (`app.favorites`), `FavVideo` (FavoritesStore.swift), `\.theme`.
- Produces: `struct CrateRow: View { let item: CrateItem; let index: Int }`.

- [ ] **Step 1: Write `CrateRow.swift`**

```swift
import SwiftUI

/// One dense library row: number · thumbnail · title · LIVE/4K badges · date.
/// Tapping navigates via the item's route; the context menu mirrors the
/// existing per-kind favorites behavior (albums aren't favoritable).
struct CrateRow: View {
    let item: CrateItem
    let index: Int

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationLink(value: item.route) {
            HStack(spacing: 9) {
                Text("\(index)")
                    .font(theme.type.numeric(11))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 22, alignment: .trailing)
                CrateThumb(url: item.imageURL, kind: item.kind)
                Text(item.title)
                    .font(theme.type.body(13))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)
                if item.isLive { badge("LIVE") }
                if item.has4K { badge("4K") }
                Spacer(minLength: 8)
                if let dateText = item.dateText {
                    Text(dateText)
                        .font(theme.type.numeric(11))
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel("\(item.title), \(item.kind.word), \(item.dateText ?? "")")
        .contextMenu { favoriteButton }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(theme.type.numeric(10))
            .foregroundStyle(theme.palette.base)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(theme.palette.accent, in: RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder private var favoriteButton: some View {
        switch item.kind {
        case .show:
            let fav = app.favorites.isShowFavorited(item.rawID)
            Button(fav ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: fav ? "star.slash" : "star") {
                app.favorites.toggleShow(
                    id: item.rawID, title: item.title, artistName: item.artistName,
                    dateText: item.dateText, venue: item.venue,
                    imageURL: item.imageURL?.absoluteString)
            }
        case .video:
            let fav = app.favorites.isVideoFavorited(item.rawID)
            Button(fav ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: fav ? "star.slash" : "star") {
                app.favorites.toggleVideo(
                    FavVideo(id: item.rawID, videoSku: 0, title: item.title,
                             artistName: item.artistName, dateText: item.dateText,
                             isLive: item.isLive,
                             imageURL: item.imageURL?.absoluteString, savedAt: Date()))
            }
        case .album:
            EmptyView()
        }
    }
}
```

- [ ] **Step 2: Generate + build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

(No `#Preview` here: `CrateRow` needs an injected `AppModel`, which is heavy to construct; it is exercised live in Task 6's manual run.)

- [ ] **Step 3: Commit**

```sh
git add AppleNugs/Views/ArtistLibrary/CrateRow.swift
git commit -m "Add CrateRow dense library row with per-kind favorites menu"
```

---

### Task 4: `CrateHeader` player chrome

**Files:**
- Create: `AppleNugs/Views/ArtistLibrary/CrateHeader.swift`

**Interfaces:**
- Consumes: `ArtistEntry` (Catalog.swift), `AppModel` (`app.player.isPlaying`, `app.favorites`), `EqualizerBars` (Theme/Components), `\.theme`.
- Produces: `struct CrateHeader: View { let artist: ArtistEntry; let albumCount: Int; let videoCount: Int; let showCount: Int }`.

- [ ] **Step 1: Write `CrateHeader.swift`**

```swift
import SwiftUI

/// Player-style header: a reused EQ/VU strip, an LCD-style summary panel, and
/// the Follow control. The LCD line truncates if it overflows (a scrolling
/// marquee is a deferred enhancement).
struct CrateHeader: View {
    let artist: ArtistEntry
    let albumCount: Int
    let videoCount: Int
    let showCount: Int

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            EqualizerBars(isPlaying: app.player.isPlaying)
            lcd
            followButton
        }
    }

    private var lcd: some View {
        Text(summary)
            .font(theme.type.numeric(12))
            .foregroundStyle(theme.palette.accent)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.palette.base.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.palette.hairline, lineWidth: 0.5))
            .accessibilityLabel(summary)
    }

    private var summary: String {
        let name = theme.caps.contains(.condensedHeaders) ? artist.name.uppercased() : artist.name
        var parts: [String] = []
        if videoCount > 0 { parts.append("\(videoCount) videos") }
        if showCount > 0 { parts.append("\(showCount) shows") }
        if albumCount > 0 { parts.append("\(albumCount) albums") }
        let tail = parts.joined(separator: " · ")
        return tail.isEmpty ? name : "\(name) — \(tail)"
    }

    private var followButton: some View {
        let fav = app.favorites.isArtistFavorited(artist.id)
        return Button {
            app.favorites.toggleArtist(id: artist.id, name: artist.name)
        } label: {
            Label(fav ? "Following" : "Follow", systemImage: fav ? "star.fill" : "star")
                .font(theme.type.body(12))
        }
        .buttonStyle(.bordered)
        .tint(fav ? theme.palette.accent : theme.palette.textSecondary)
        .help(fav ? "Unfollow artist" : "Follow artist")
    }
}
```

- [ ] **Step 2: Generate + build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```sh
git add AppleNugs/Views/ArtistLibrary/CrateHeader.swift
git commit -m "Add CrateHeader player chrome (VU + LCD summary + Follow)"
```

---

### Task 5: `CrateOutline` expandable tree

**Files:**
- Create: `AppleNugs/Views/ArtistLibrary/CrateOutline.swift`

**Interfaces:**
- Consumes: `CrateItem`, `CrateKind`, `groupedByYear()` (Task 1), `CrateRow` (Task 3), `ArtistEntry`, `\.theme`.
- Produces: `struct CrateOutline: View` with init `(albums: [CrateItem], videos: [CrateItem], shows: [CrateItem], canLoadMore: Bool, loading: Bool, loadMore: @escaping () -> Void)`.

- [ ] **Step 1: Write `CrateOutline.swift`**

```swift
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
```

- [ ] **Step 2: Generate + build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```sh
git add AppleNugs/Views/ArtistLibrary/CrateOutline.swift
git commit -m "Add CrateOutline expandable category/year library tree"
```

---

### Task 6: Rework `ArtistDetailView` onto the outline

**Files:**
- Modify: `AppleNugs/Views/ArtistDetailView.swift`

**Interfaces:**
- Consumes: `CrateHeader` (Task 4), `CrateOutline` (Task 5), `CrateItem` builders (Task 1).
- Produces: the integrated artist page (no new public symbols).

- [ ] **Step 1: Replace the body, header, and section builders**

Open `AppleNugs/Views/ArtistDetailView.swift`. Keep the stored properties `containers`, `loading`, `error`, `canLoadMore`, `videos`, `pageSize`, and the computed `releases`/`shows`. **Delete** `expandedYears`, `showsByYear`, `header`, `followButton`, `sectionTitle`, `releaseGrid`, `videoGrid`, `yearSection`, `yearBinding`. Replace the `body` and add the three item-mapping computeds so the type reads:

```swift
struct ArtistDetailView: View {
    let artist: ArtistEntry

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    @State private var containers: [ContainerSummary] = []
    @State private var loading = false
    @State private var error: String?
    @State private var canLoadMore = false
    @State private var videos: [VideoSummary] = []

    private static let pageSize = 100

    private var releases: [ContainerSummary] { containers.filter { !$0.isLiveShow } }
    private var shows: [ContainerSummary] { containers.filter(\.isLiveShow) }

    private var albumItems: [CrateItem] { releases.map { CrateItem.album($0, artist: artist.name) } }
    private var showItems: [CrateItem] { shows.map { CrateItem.show($0, artist: artist.name) } }
    private var videoItems: [CrateItem] { videos.map { CrateItem.video($0, artist: artist.name) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CrateHeader(artist: artist,
                            albumCount: releases.count,
                            videoCount: videos.count,
                            showCount: shows.count)

                CrateOutline(albums: albumItems,
                             videos: videoItems,
                             shows: showItems,
                             canLoadMore: canLoadMore,
                             loading: loading,
                             loadMore: { Task { await load(reset: false) } })
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.base)
        .navigationTitle(artist.name)
        .overlay {
            if loading && containers.isEmpty {
                ProgressView()
            } else if let error, containers.isEmpty {
                ContentUnavailableView(
                    "Couldn't load shows",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            }
        }
        .task(id: artist.id) { await load(reset: true) }
    }
```

- [ ] **Step 2: Simplify `load(reset:)` (drop the year auto-expand)**

The previous `load` auto-expanded the newest show year; with the all-collapsed default that block is removed. Replace `load(reset:)` with:

```swift
    private func load(reset: Bool) async {
        if reset {
            containers = []
            canLoadMore = false
            videos = []
            Task { await loadVideos() }
        }
        loading = true
        defer { loading = false }
        do {
            let json = try await app.client.artistShows(
                id: artist.id, offset: containers.count + 1, limit: Self.pageSize)
            let page = Catalog.containers(from: json)
            containers += page
            canLoadMore = page.count >= Self.pageSize
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
```

Leave `loadVideos()` exactly as-is.

- [ ] **Step 3: Resolve `CoverArt`**

`CoverArt` (defined at the bottom of this file) was only used by the old `releaseGrid`. Confirm it has no remaining references and delete it:

```sh
cd /Users/tim/applenugs && grep -rn "CoverArt" AppleNugs --include="*.swift"
```
Expected: matches only inside `ArtistDetailView.swift` (its own declaration). If so, delete the entire `struct CoverArt: View { … }` block at the end of the file. If `grep` shows a use in any **other** file, leave `CoverArt` in place instead.

- [ ] **Step 4: Generate + build**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual run**

```sh
cd /Users/tim/applenugs && xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath build/dd build && \
open build/dd/Build/Products/Debug/AppleNugs.app
```
Sign in, open a content-rich artist (e.g. Goose). Verify:
- loads **all collapsed** — Albums / Videos / Shows rows with correct counts; LCD summary + VU strip + Follow visible;
- expanding Videos shows year nodes; expanding a year shows dense rows with tiny 16:9 thumbs, `4K`/`LIVE` badges, dates;
- expanding Shows shows year nodes → square-thumb rows;
- Albums expands straight to rows (no year level);
- tapping a row navigates (album/show → album detail; video → video detail);
- right-click a show or video row → favorites toggle works; album rows have no favorites item;
- scrolling to the end of an expanded Shows category loads another page (footer spinner) when more exist.

- [ ] **Step 6: Commit**

```sh
git add AppleNugs/Views/ArtistDetailView.swift
git commit -m "Rework ArtistDetailView onto the CrateHeader + CrateOutline library"
```

---

### Task 7: Strict-concurrency clean build + theme/a11y verification

**Files:** none (verification + any fixes surfaced).

- [ ] **Step 1: Clean build in an isolated worktree with fresh derived data**

Per project convention (incremental builds can mask a dirty state), verify in a throwaway worktree so the check is honest:

```sh
cd /Users/tim/applenugs
git worktree add /tmp/an-verify artist-library-outline
cd /tmp/an-verify && xcodegen generate && \
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/an-verify-dd clean build 2>&1 | tee /tmp/an-build.log | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Confirm zero warnings (strict concurrency is `complete`)**

```sh
grep -iE "warning:|error:" /tmp/an-build.log || echo "CLEAN — no warnings/errors"
```
Expected: `CLEAN — no warnings/errors`. If any appear, fix them in the source (commit the fix), then re-run Steps 1–2.

- [ ] **Step 3: Theme + accessibility pass (manual)**

Run the app (`open /tmp/an-verify-dd/Build/Products/Debug/AppleNugs.app`). On the Goose artist page:
- switch through all four themes (Tape Room / Soundboard / Shoebox / The Receiver) — outline, LCD panel, badges, and chevrons stay legible and accent-coherent; condensed-header themes uppercase the category labels;
- narrow the window — the single-column outline reflows without clipping beside the REELS sidebar;
- VoiceOver (⌘F5): category/year rows announce label + count + expanded/collapsed; leaf rows announce "{title}, {kind}, {date}"; the VU strip is skipped.

- [ ] **Step 4: Remove the worktree**

```sh
cd /Users/tim/applenugs && git worktree remove /tmp/an-verify --force
```

- [ ] **Step 5: Commit any fixes** (only if Step 2 surfaced changes)

```sh
git add -A && git commit -m "Fix strict-concurrency/theming nits in the artist library"
```

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
| --- | --- |
| Single expandable outline (Albums/Videos/Shows) | 5, 6 |
| All-collapsed default | 5 (empty `expanded*` sets), 6 (removed auto-expand) |
| Videos & Shows grouped by year; Albums flat | 5 (`grouped:` flag), 1 (`groupedByYear()`) |
| Dense rows: thumb · title · badges · date | 2, 3 |
| Tiny thumbnails (16:9 video / square others) | 2 |
| Tap → existing routes | 1 (route mapping), 3 |
| Per-kind favorites menu; albums none | 3 |
| Player header: reused VU + LCD marquee + Follow | 4 |
| Themed / accent-tinted, no green | all view tasks (token-only) |
| Shows pagination on scroll | 5 (`paginationFooter`), 6 (`loadMore`) |
| Counts from loaded arrays | 4 (header), 5 (node counts), 6 |
| Edge: empty category hidden | 5 (`if !items.isEmpty`) |
| Edge: undated → "Unknown" group last | 1 (`groupedByYear` nil bucket) |
| Edge: nothing loaded → ContentUnavailableView | 6 (overlay kept) |
| Accessibility labels / VU hidden | 3, 5; VU hidden is inherited from `EqualizerBars` (decorative) — Step 3 of Task 7 verifies |
| Build clean under strict concurrency + manual run | 7 |
| Deferred (sorting, marquee animation) | intentionally absent |

No gaps.

**2. Placeholder scan:** No `TBD`/`TODO`/"handle edge cases"/"similar to". Every code step shows complete code. The one conditional ("delete `CoverArt` if unused") includes the exact `grep` to decide and both branches.

**3. Type consistency:** `CrateItem` fields (`rawID`, `kind`, `title`, `artistName`, `venue`, `dateText`, `date`, `imageURL`, `isLive`, `has4K`, `route`, computed `id`/`year`) are produced in Task 1 and consumed identically in Tasks 3/5/6. `CrateKind` cases/`icon`/`label`/`word` used consistently. `groupedByYear()` returns `[(year: Int?, items: [CrateItem])]`, iterated with `id: \.year` in Task 5. `CrateOutline.init` parameter list matches its call site in Task 6. Builder names `CrateItem.album/show/video(_:artist:)` match their uses. `EqualizerBars(isPlaying:)`, `app.player.isPlaying`, `app.favorites.{isShowFavorited,toggleShow,isVideoFavorited,toggleVideo,isArtistFavorited,toggleArtist}`, and `FavVideo(...)` all match the verified source signatures.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-27-artist-library-outline.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — I execute the tasks in this session with checkpoints for review.

Which approach?
