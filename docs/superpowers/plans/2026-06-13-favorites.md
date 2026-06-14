# Favorites / Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user follow artists and save shows, reachable from a dedicated Favorites view and a Home strip, persisted locally.

**Architecture:** A new `@Observable FavoritesStore` persists two flat collections (artists, shows) as JSON in Application Support (same idiom as `SessionStore`), lives on `AppModel`, and is read through the existing `@Environment(AppModel.self)`. Favoriting happens via detail-header stars, a now-playing star, and right-click menus — no per-row star icons. A new text-only `Favorites` sidebar destination shows stacked sections; Home gets a favorites strip.

**Tech Stack:** Swift 5 / SwiftUI (macOS 14), Observation, xcodegen-generated project, AVFoundation player.

**Testing approach (read first):** This project has **no XCTest target** and the spec mandates manual verification. There is therefore no "write a failing test" step. Every task is verified by a real build plus targeted manual checks. The standard build command used throughout is:

```bash
cd /Users/tim/applenugs && xcodegen generate && \
xcodebuild -project AppleNugs.xcodeproj -scheme AppleNugs -configuration Debug build 2>&1 \
  | grep -E "(error:|warning: .*Swift|BUILD SUCCEEDED|BUILD FAILED)" | tail -20
```
Expected after each task: `** BUILD SUCCEEDED **` with no `error:` lines. (`xcodegen generate` is only strictly required for tasks that add new files, but running it every time is harmless.)

**Branch:** Work happens on `favorites` (already checked out). Commit after every task.

**Spec:** `docs/superpowers/specs/2026-06-13-favorites-design.md`

**One refinement vs. the spec:** `FavShow` stores `imageURL: String?` (an absolute URL string) rather than `imagePath`. The catalog sources expose covers as resolved `URL?` (`AlbumDetailModel.imageURL`, `ContainerSummary.imageURL`), while the now-playing track exposes a path resolved through `NugsConstants.imageURL(path:)`. Storing the resolved absolute string unifies all sources for `ShowCard`.

---

## File structure

**New files**
- `AppleNugs/Core/FavoritesStore.swift` — `FavArtist`, `FavShow`, and the persisted `@Observable` store.
- `AppleNugs/Theme/Components/ShowCard.swift` — reusable cover-art show card (Favorites grid + Home strip).
- `AppleNugs/Views/FavoritesView.swift` — the stacked Favorites destination.

**Modified files**
- `AppleNugs/App/AppModel.swift` — own `favorites`.
- `AppleNugs/Player/PlayerService.swift` — add `showId` to `QueueTrack`.
- `AppleNugs/Views/AlbumDetailView.swift` — populate `showId`; header save star.
- `AppleNugs/App/UIState.swift` — `SidebarItem.favorites`.
- `AppleNugs/Views/RootView.swift` — text-only sidebar + Favorites + route.
- `AppleNugs/Views/ArtistDetailView.swift` — header follow star; context menu on show rows.
- `AppleNugs/Views/ArtistListView.swift` — context menu on artist rows.
- `AppleNugs/Views/SearchView.swift` — context menus on results.
- `AppleNugs/Views/TransportBar.swift` — now-playing star.
- `AppleNugs/Theme/Transport/FaceplateTransport.swift` — now-playing star.
- `AppleNugs/Views/HomeView.swift` — favorites strip.

---

## Task 1: FavoritesStore + AppModel wiring

**Files:**
- Create: `AppleNugs/Core/FavoritesStore.swift`
- Modify: `AppleNugs/App/AppModel.swift`

- [ ] **Step 1: Create the store**

Create `AppleNugs/Core/FavoritesStore.swift`:

```swift
import Foundation
import Observation

struct FavArtist: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var savedAt: Date
}

struct FavShow: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var artistName: String
    var dateText: String?
    var venue: String?
    var imageURL: String?
    var savedAt: Date
}

/// Persists followed artists and saved shows as JSON in Application Support —
/// the same idiom as SessionStore. @Observable, so stars and the Favorites view
/// update reactively on any toggle. Favorites persist across logout (they are
/// catalog references, not account secrets).
@MainActor
@Observable
final class FavoritesStore {
    private(set) var favArtists: [FavArtist] = []
    private(set) var favShows: [FavShow] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleNugs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("favorites.json")
        load()
    }

    // --- sorted accessors ---------------------------------------------------

    var artists: [FavArtist] {
        favArtists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var shows: [FavShow] {
        favShows.sorted { $0.savedAt > $1.savedAt }
    }
    var isEmpty: Bool { favArtists.isEmpty && favShows.isEmpty }

    // --- artists ------------------------------------------------------------

    func isArtistFavorited(_ id: String) -> Bool { favArtists.contains { $0.id == id } }

    func toggleArtist(id: String, name: String) {
        if let idx = favArtists.firstIndex(where: { $0.id == id }) {
            favArtists.remove(at: idx)
        } else {
            favArtists.append(FavArtist(id: id, name: name, savedAt: Date()))
        }
        save()
    }

    // --- shows --------------------------------------------------------------

    func isShowFavorited(_ id: String) -> Bool { favShows.contains { $0.id == id } }

    func toggleShow(id: String, title: String, artistName: String,
                    dateText: String?, venue: String?, imageURL: String?) {
        if let idx = favShows.firstIndex(where: { $0.id == id }) {
            favShows.remove(at: idx)
        } else {
            favShows.append(FavShow(id: id, title: title, artistName: artistName,
                                    dateText: dateText, venue: venue,
                                    imageURL: imageURL, savedAt: Date()))
        }
        save()
    }

    // --- persistence --------------------------------------------------------

    private struct Stored: Codable {
        var artists: [FavArtist]
        var shows: [FavShow]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode(Stored.self, from: data) else { return }
        favArtists = decoded.artists
        favShows = decoded.shows
    }

    private func save() {
        guard let data = try? Self.encoder.encode(Stored(artists: favArtists, shows: favShows)) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
```

- [ ] **Step 2: Add `favorites` to AppModel**

In `AppleNugs/App/AppModel.swift`, the type has `let client` / `let player`. Add a `favorites` property right after `let player: PlayerService`:

```swift
    let client: NugsClient
    let player: PlayerService
    let favorites = FavoritesStore()
```

Do **not** clear it in `logout()` (favorites persist across logout per the spec).

- [ ] **Step 3: Build**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`, no `error:` lines.

- [ ] **Step 4: Commit**

```bash
git add AppleNugs/Core/FavoritesStore.swift AppleNugs/App/AppModel.swift
git commit -m "Add FavoritesStore and wire it into AppModel"
```

---

## Task 2: Carry the show id on the queue

So the now-playing star (Task 7) knows which show to save.

**Files:**
- Modify: `AppleNugs/Player/PlayerService.swift` (the `QueueTrack` struct)
- Modify: `AppleNugs/Views/AlbumDetailView.swift` (`queueTracks`)

- [ ] **Step 1: Add `showId` to QueueTrack**

In `AppleNugs/Player/PlayerService.swift`, the struct is:

```swift
struct QueueTrack: Identifiable, Hashable {
    let id = UUID()
    let trackId: String
    let title: String?
    let artist: String?
    let show: String?
    var artworkPath: String? = nil
}
```

Add one field:

```swift
struct QueueTrack: Identifiable, Hashable {
    let id = UUID()
    let trackId: String
    let title: String?
    let artist: String?
    let show: String?
    var artworkPath: String? = nil
    var showId: String? = nil
}
```

This is additive with a default, so existing construction sites (queue restore, single-track search play) keep compiling; their `showId` stays `nil` (now-playing star disabled there, as the spec allows).

- [ ] **Step 2: Populate `showId` from the album**

In `AppleNugs/Views/AlbumDetailView.swift`, `queueTracks` currently is:

```swift
    private func queueTracks(_ album: AlbumDetailModel) -> [QueueTrack] {
        album.tracks.map {
            QueueTrack(trackId: $0.id, title: $0.title,
                       artist: album.artistName, show: album.title,
                       artworkPath: album.imagePath)
        }
    }
```

Add `showId: album.id`:

```swift
    private func queueTracks(_ album: AlbumDetailModel) -> [QueueTrack] {
        album.tracks.map {
            QueueTrack(trackId: $0.id, title: $0.title,
                       artist: album.artistName, show: album.title,
                       artworkPath: album.imagePath, showId: album.id)
        }
    }
```

- [ ] **Step 3: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add AppleNugs/Player/PlayerService.swift AppleNugs/Views/AlbumDetailView.swift
git commit -m "Carry the show id on queued tracks for now-playing favoriting"
```

---

## Task 3: ShowCard component

A reusable cover-art card, used by both the Favorites grid and the Home strip.

**Files:**
- Create: `AppleNugs/Theme/Components/ShowCard.swift`

- [ ] **Step 1: Create ShowCard**

Create `AppleNugs/Theme/Components/ShowCard.swift`. It reuses the existing `CoverArt` view (defined in `ArtistDetailView.swift`) and the theme tokens.

```swift
import SwiftUI

/// A saved-show card: cover art (or the themed placeholder) over a title and
/// artist line. Reused by the Favorites view grid and the Home favorites strip.
struct ShowCard: View {
    @Environment(\.theme) private var theme
    let show: FavShow
    var width: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArt(url: show.imageURL.flatMap { URL(string: $0) })
                .frame(width: width)
            Text(show.title)
                .font(theme.type.body(12))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(show.artistName)
                .font(theme.type.numeric(10))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}
```

- [ ] **Step 2: Build**

Run the standard build command (adds a file — `xcodegen generate` matters here). Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add AppleNugs/Theme/Components/ShowCard.swift AppleNugs.xcodeproj
git commit -m "Add reusable ShowCard for saved-show covers"
```

(The `.xcodeproj` is regenerated by xcodegen; it is not gitignored, so include whatever `git status` shows.)

---

## Task 4: Favorites sidebar destination + view

**Files:**
- Modify: `AppleNugs/App/UIState.swift`
- Modify: `AppleNugs/Views/RootView.swift`
- Create: `AppleNugs/Views/FavoritesView.swift`

- [ ] **Step 1: Add the sidebar case**

In `AppleNugs/App/UIState.swift`, the enum is:

```swift
    enum SidebarItem: Hashable {
        case home
        case artists
        case search
    }
```

Add `favorites`:

```swift
    enum SidebarItem: Hashable {
        case home
        case artists
        case favorites
        case search
    }
```

- [ ] **Step 2: Text-only sidebar + Favorites + route**

In `AppleNugs/Views/RootView.swift`, the sidebar list currently is:

```swift
                List(selection: $ui.sidebarSelection) {
                    Label("Home", systemImage: "house")
                        .tag(UIState.SidebarItem.home)
                    Label("Artists", systemImage: "music.mic")
                        .tag(UIState.SidebarItem.artists)
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(UIState.SidebarItem.search)
                }
```

Replace with text-only labels and add Favorites:

```swift
                List(selection: $ui.sidebarSelection) {
                    Text("Home")
                        .tag(UIState.SidebarItem.home)
                    Text("Artists")
                        .tag(UIState.SidebarItem.artists)
                    Text("Favorites")
                        .tag(UIState.SidebarItem.favorites)
                    Text("Search")
                        .tag(UIState.SidebarItem.search)
                }
```

And `detailRoot` currently is:

```swift
    @ViewBuilder
    private var detailRoot: some View {
        switch ui.sidebarSelection {
        case .home:
            HomeView()
        case .search:
            SearchView()
        default:
            ArtistListView()
        }
    }
```

Add the favorites case:

```swift
    @ViewBuilder
    private var detailRoot: some View {
        switch ui.sidebarSelection {
        case .home:
            HomeView()
        case .favorites:
            FavoritesView()
        case .search:
            SearchView()
        default:
            ArtistListView()
        }
    }
```

- [ ] **Step 3: Create FavoritesView**

Create `AppleNugs/Views/FavoritesView.swift`:

```swift
import SwiftUI

/// The Favorites destination: followed artists as text chips, then saved shows
/// as a cover-art grid (newest saved first). Stacked sections, fully themed.
struct FavoritesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    private var favorites: FavoritesStore { app.favorites }

    var body: some View {
        ScrollView {
            if favorites.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                VStack(alignment: .leading, spacing: 26) {
                    if !favorites.artists.isEmpty { artistsSection }
                    if !favorites.shows.isEmpty { showsSection }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.palette.base)
        .navigationTitle("Favorites")
    }

    private func sectionTitle(_ text: String) -> some View {
        let condensed = theme.caps.contains(.condensedHeaders)
        return Text(condensed ? text.uppercased() : text)
            .font(theme.type.section(17))
            .tracking(condensed ? 1.4 : 0)
            .foregroundStyle(theme.palette.textPrimary)
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Artists")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(favorites.artists) { fav in
                    NavigationLink(value: Route.artist(ArtistEntry(id: fav.id, name: fav.name))) {
                        HStack {
                            Text(fav.name)
                                .font(theme.type.body(13))
                                .foregroundStyle(theme.palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(theme.palette.raised)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Favorites", systemImage: "star.slash") {
                            app.favorites.toggleArtist(id: fav.id, name: fav.name)
                        }
                    }
                }
            }
        }
    }

    private var showsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Saved shows")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)],
                      alignment: .leading, spacing: 16) {
                ForEach(favorites.shows) { show in
                    NavigationLink(value: Route.album(id: show.id, title: show.title)) {
                        ShowCard(show: show, width: 150)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Favorites", systemImage: "star.slash") {
                            app.favorites.toggleShow(id: show.id, title: show.title,
                                                     artistName: show.artistName,
                                                     dateText: show.dateText, venue: show.venue,
                                                     imageURL: show.imageURL)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 34))
                .foregroundStyle(theme.palette.accent)
            Text("Nothing saved yet")
                .font(theme.type.hero(22))
                .foregroundStyle(theme.palette.textPrimary)
            Text("Star an artist or a show to keep it here.")
                .font(theme.type.body(13))
                .foregroundStyle(theme.palette.textSecondary)
        }
    }
}
```

- [ ] **Step 4: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual check**

Run the app. The sidebar reads `Home / Artists / Favorites / Search` with **no icons**. Click **Favorites** → the empty state ("Nothing saved yet…") shows.

- [ ] **Step 6: Commit**

```bash
git add AppleNugs/App/UIState.swift AppleNugs/Views/RootView.swift AppleNugs/Views/FavoritesView.swift AppleNugs.xcodeproj
git commit -m "Add text-only sidebar Favorites destination with empty state"
```

---

## Task 5: Detail-header stars (artist + show)

**Files:**
- Modify: `AppleNugs/Views/ArtistDetailView.swift`
- Modify: `AppleNugs/Views/AlbumDetailView.swift`

- [ ] **Step 1: Follow star on the artist header**

In `AppleNugs/Views/ArtistDetailView.swift`, the header is:

```swift
    private var header: some View {
        HStack(spacing: 12) {
            if !releases.isEmpty {
                Text("^[\(releases.count) release](inflect: true)")
            }
            if !shows.isEmpty {
                Text("^[\(shows.count) show](inflect: true)")
            }
        }
        .font(theme.type.numeric(12))
        .foregroundStyle(theme.palette.textSecondary)
    }
```

Add a leading follow button:

```swift
    private var header: some View {
        HStack(spacing: 12) {
            followButton
            if !releases.isEmpty {
                Text("^[\(releases.count) release](inflect: true)")
            }
            if !shows.isEmpty {
                Text("^[\(shows.count) show](inflect: true)")
            }
        }
        .font(theme.type.numeric(12))
        .foregroundStyle(theme.palette.textSecondary)
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
```

(`ArtistDetailView` already has `@Environment(AppModel.self) private var app` and `@Environment(\.theme) private var theme`.)

- [ ] **Step 2: Save star on the show header**

In `AppleNugs/Views/AlbumDetailView.swift`, `actions` is:

```swift
    private func actions(_ album: AlbumDetailModel) -> some View {
        HStack(spacing: 8) {
            Button {
                app.player.play(queueTracks(album))
            } label: {
                Label("Play all", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(album.tracks.isEmpty)

            Button {
                if app.player.playNext(queueTracks(album)) {
                    ui.showToast("Playing next")
                }
            } label: {
                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .disabled(album.tracks.isEmpty)

            Button {
                if app.player.enqueue(queueTracks(album)) {
                    ui.showToast("Added to queue")
                }
            } label: {
                Label("Queue", systemImage: "plus")
            }
            .disabled(album.tracks.isEmpty)
        }
    }
```

Add a save button at the end of the `HStack`:

```swift
            Button {
                if app.player.enqueue(queueTracks(album)) {
                    ui.showToast("Added to queue")
                }
            } label: {
                Label("Queue", systemImage: "plus")
            }
            .disabled(album.tracks.isEmpty)

            saveButton(album)
        }
    }

    private func saveButton(_ album: AlbumDetailModel) -> some View {
        let fav = app.favorites.isShowFavorited(albumId)
        return Button {
            app.favorites.toggleShow(id: albumId, title: album.title,
                                     artistName: album.artistName,
                                     dateText: album.dateText, venue: album.venue,
                                     imageURL: album.imageURL?.absoluteString)
        } label: {
            Label(fav ? "Saved" : "Save", systemImage: fav ? "star.fill" : "star")
        }
        .tint(fav ? theme.palette.accent : nil)
        .help(fav ? "Remove from Favorites" : "Save show to Favorites")
    }
```

(`AlbumDetailView` already has `app`, `ui`, `theme`, the `albumId` property, and `album.imageURL` is a `URL?`.)

- [ ] **Step 3: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check**

Open an artist → tap **Follow** (fills to "Following" in the accent). Open one of its shows → tap **Save** (fills to "Saved"). Go to **Favorites** → the artist chip and the show card both appear. Toggle each off from the headers → they leave Favorites.

- [ ] **Step 5: Commit**

```bash
git add AppleNugs/Views/ArtistDetailView.swift AppleNugs/Views/AlbumDetailView.swift
git commit -m "Add follow/save stars to artist and show detail headers"
```

---

## Task 6: Right-click context menus

**Files:**
- Modify: `AppleNugs/Views/ArtistListView.swift`
- Modify: `AppleNugs/Views/ArtistDetailView.swift`
- Modify: `AppleNugs/Views/SearchView.swift`

- [ ] **Step 1: Artist-list rows**

In `AppleNugs/Views/ArtistListView.swift`, the row is:

```swift
                        NavigationLink(value: Route.artist(artist)) {
                            Text(artist.name)
                                .font(theme.type.body(14))
                                .foregroundStyle(theme.palette.textPrimary)
                                .padding(.vertical, 1)
                        }
                        .listRowSeparator(.hidden)
```

Add a context menu:

```swift
                        NavigationLink(value: Route.artist(artist)) {
                            Text(artist.name)
                                .font(theme.type.body(14))
                                .foregroundStyle(theme.palette.textPrimary)
                                .padding(.vertical, 1)
                        }
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            let fav = app.favorites.isArtistFavorited(artist.id)
                            Button(fav ? "Remove from Favorites" : "Add to Favorites",
                                   systemImage: fav ? "star.slash" : "star") {
                                app.favorites.toggleArtist(id: artist.id, name: artist.name)
                            }
                        }
```

(`ArtistListView` already has `app`.)

- [ ] **Step 2: Show rows on the artist page**

In `AppleNugs/Views/ArtistDetailView.swift`, inside `yearSection`, the show row is:

```swift
                    NavigationLink(value: Route.album(id: show.id, title: show.venue ?? show.title)) {
                        HStack(spacing: 10) {
                            Text(show.dateText ?? "")
                                .font(theme.type.numeric(12))
                                .foregroundStyle(theme.palette.textSecondary)
                                .frame(width: 86, alignment: .leading)
                            Text(show.venue ?? show.title)
                                .font(theme.type.body(13))
                                .foregroundStyle(theme.palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
```

Add a context menu after `.padding(.vertical, 3)`:

```swift
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                    .contextMenu {
                        let fav = app.favorites.isShowFavorited(show.id)
                        Button(fav ? "Remove from Favorites" : "Add to Favorites",
                               systemImage: fav ? "star.slash" : "star") {
                            app.favorites.toggleShow(id: show.id, title: show.venue ?? show.title,
                                                     artistName: artist.name,
                                                     dateText: show.dateText, venue: show.venue,
                                                     imageURL: show.imageURL?.absoluteString)
                        }
                    }
```

(`ContainerSummary` exposes `id`, `title`, `venue`, `dateText`, and `imageURL: URL?`.)

- [ ] **Step 3: Search results**

In `AppleNugs/Views/SearchView.swift`, the artists section row is:

```swift
                    ForEach(results.artists) { artist in
                        NavigationLink(value: Route.artist(artist)) {
                            Label(artist.name, systemImage: "music.mic")
                        }
                    }
```

Add a context menu:

```swift
                    ForEach(results.artists) { artist in
                        NavigationLink(value: Route.artist(artist)) {
                            Label(artist.name, systemImage: "music.mic")
                        }
                        .contextMenu {
                            let fav = app.favorites.isArtistFavorited(artist.id)
                            Button(fav ? "Remove from Favorites" : "Add to Favorites",
                                   systemImage: fav ? "star.slash" : "star") {
                                app.favorites.toggleArtist(id: artist.id, name: artist.name)
                            }
                        }
                    }
```

Then, in the same file, the container row begins:

```swift
        case .container(let id):
            NavigationLink(value: Route.album(id: id, title: item.venue ?? item.name)) {
                HStack(spacing: 10) {
```

Attach a context menu to that `NavigationLink`. Find the end of the `.container` case's `NavigationLink { ... }` block and add `.contextMenu` to it:

```swift
        case .container(let id):
            NavigationLink(value: Route.album(id: id, title: item.venue ?? item.name)) {
                HStack(spacing: 10) {
                    if let date = item.dateText {
                        Text(date)
                            .font(theme.type.numeric(12))
                            .foregroundStyle(theme.palette.textSecondary)
                        Text(item.venue ?? item.name).lineLimit(1)
                    } else {
                        Text(item.name).lineLimit(1)
                        if let artist = item.artistName {
                            Text("— \(artist)").foregroundStyle(theme.palette.textSecondary).lineLimit(1)
                        }
                    }
                }
            }
            .contextMenu {
                let fav = app.favorites.isShowFavorited(id)
                Button(fav ? "Remove from Favorites" : "Add to Favorites",
                       systemImage: fav ? "star.slash" : "star") {
                    app.favorites.toggleShow(id: id, title: item.venue ?? item.name,
                                             artistName: item.artistName ?? "",
                                             dateText: item.dateText, venue: item.venue,
                                             imageURL: nil)
                }
            }
```

(Search items carry no cover path, so `imageURL` is `nil`; `ShowCard` falls back to the themed placeholder. `SearchView` already has `app`.)

- [ ] **Step 4: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual check**

Right-click an artist in the Artists list → "Add to Favorites" → appears in Favorites. Right-click a show on an artist page, and an artist/show in Search results → same. Re-open the menu on a saved item → it reads "Remove from Favorites".

- [ ] **Step 6: Commit**

```bash
git add AppleNugs/Views/ArtistListView.swift AppleNugs/Views/ArtistDetailView.swift AppleNugs/Views/SearchView.swift
git commit -m "Add favorite/unfavorite context menus to artist, show, and search rows"
```

---

## Task 7: Now-playing star

**Files:**
- Modify: `AppleNugs/Views/TransportBar.swift`
- Modify: `AppleNugs/Theme/Transport/FaceplateTransport.swift`

- [ ] **Step 1: Shared star in TransportBar**

In `AppleNugs/Views/TransportBar.swift`, the `standardBar` ends its `HStack` with the format badge block, then padding/background:

```swift
            if let pick = player.nowPick {
                Text(pick.format.badge)
                    .font(theme.type.numeric(10).weight(.semibold))
                    .foregroundStyle(badgeColor(for: pick.format))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.palette.hairline, in: RoundedRectangle(cornerRadius: 4))
                    .help(pick.format.qualityLabel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
```

Insert the star before the format-badge block (so it sits just left of the badge):

```swift
            nowPlayingStar

            if let pick = player.nowPick {
                Text(pick.format.badge)
                    .font(theme.type.numeric(10).weight(.semibold))
                    .foregroundStyle(badgeColor(for: pick.format))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.palette.hairline, in: RoundedRectangle(cornerRadius: 4))
                    .help(pick.format.qualityLabel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
```

Then add the `nowPlayingStar` view and a shared helper as members of `TransportBar` (place after the `badgeColor(for:)` function):

```swift
    private var nowPlayingStar: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 13))
                .foregroundStyle(saved ? theme.palette.accent : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .help("Save this show to Favorites")
    }
```

- [ ] **Step 2: Shared favorite helper (avoid duplication)**

So the standard bar and the faceplate share one implementation, add this small helper to the bottom of `AppleNugs/Views/TransportBar.swift` (outside the `TransportBar` struct):

```swift
/// Shared now-playing → FavShow bridge used by both the standard transport and
/// the faceplate. A track is favoritable only when it carries a `showId`
/// (i.e. it was queued from a show, not a single-track search hit).
enum NowPlayingFavorite {
    static func isSaved(_ track: QueueTrack?, favorites: FavoritesStore) -> Bool {
        guard let id = track?.showId else { return false }
        return favorites.isShowFavorited(id)
    }

    static func toggle(_ track: QueueTrack?, favorites: FavoritesStore) {
        guard let track, let id = track.showId else { return }
        favorites.toggleShow(
            id: id,
            title: track.show ?? track.title ?? "Show",
            artistName: track.artist ?? "",
            dateText: nil,
            venue: nil,
            imageURL: track.artworkPath.flatMap { NugsConstants.imageURL(path: $0)?.absoluteString })
    }
}
```

- [ ] **Step 3: Star in the faceplate**

In `AppleNugs/Theme/Transport/FaceplateTransport.swift`, the body `HStack` ends with `qualityReadout`:

```swift
            seekBlock
            volumeLadder
            qualityReadout
                .frame(width: 130, alignment: .trailing)
        }
```

Add the star after `qualityReadout`:

```swift
            seekBlock
            volumeLadder
            qualityReadout
                .frame(width: 130, alignment: .trailing)
            faceplateStar
        }
```

Then add the `faceplateStar` member (place after `qualityText`):

```swift
    private var faceplateStar: some View {
        let saved = NowPlayingFavorite.isSaved(player.current, favorites: app.favorites)
        return Button {
            NowPlayingFavorite.toggle(player.current, favorites: app.favorites)
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(saved ? theme.palette.accent : theme.palette.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(player.current?.showId == nil)
        .help("Save this show to Favorites")
    }
```

(`FaceplateTransport` already has `app`, `theme`, and the `player` accessor.)

- [ ] **Step 4: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual check**

Play a show from a show page. A star appears in the transport (and in The Receiver's faceplate). Tap it → fills; the show appears in Favorites. Confirm the star is **disabled** when nothing is playing and after playing a single-track Search hit (no `showId`).

- [ ] **Step 6: Commit**

```bash
git add AppleNugs/Views/TransportBar.swift AppleNugs/Theme/Transport/FaceplateTransport.swift
git commit -m "Add now-playing save star to transport and faceplate"
```

---

## Task 8: Home favorites strip

**Files:**
- Modify: `AppleNugs/Views/HomeView.swift`

- [ ] **Step 1: Insert the strip and re-index the reveal animation**

In `AppleNugs/Views/HomeView.swift`, the body stack is:

```swift
            VStack(alignment: .leading, spacing: 30) {
                greeting.reveal(appeared, 0)
                if player.current != nil { resumeCard.reveal(appeared, 1) }
                entryRow.reveal(appeared, 2)
                if !sample.isEmpty { crate.reveal(appeared, 3) }
            }
```

Insert the favorites strip after the resume card and bump the later indices:

```swift
            VStack(alignment: .leading, spacing: 30) {
                greeting.reveal(appeared, 0)
                if player.current != nil { resumeCard.reveal(appeared, 1) }
                if !app.favorites.isEmpty { favoritesStrip.reveal(appeared, 2) }
                entryRow.reveal(appeared, 3)
                if !sample.isEmpty { crate.reveal(appeared, 4) }
            }
```

- [ ] **Step 2: Add the favoritesStrip view**

Add this computed property to `HomeView` (e.g. right after the `crate` property). It shows up to 8 followed-artist chips and up to 6 recent saved shows, with a "See all" that selects the Favorites destination:

```swift
    private var favoritesStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(theme.caps.contains(.condensedHeaders) ? "FAVORITES" : "Favorites")
                    .font(theme.type.section(15))
                    .tracking(theme.caps.contains(.condensedHeaders) ? 1.6 : 0)
                    .foregroundStyle(theme.palette.textPrimary)
                Spacer()
                Button("See all ›") { ui.sidebarSelection = .favorites }
                    .buttonStyle(.plain)
                    .font(theme.type.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            if !app.favorites.artists.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(app.favorites.artists.prefix(8)) { fav in
                        NavigationLink(value: Route.artist(ArtistEntry(id: fav.id, name: fav.name))) {
                            HStack {
                                Text(fav.name)
                                    .font(theme.type.body(13))
                                    .foregroundStyle(theme.palette.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(theme.palette.raised)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !app.favorites.shows.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(app.favorites.shows.prefix(6)) { show in
                            NavigationLink(value: Route.album(id: show.id, title: show.title)) {
                                ShowCard(show: show, width: 132)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
```

(`HomeView` already has `app`, `ui`, `theme`.)

- [ ] **Step 3: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check**

With at least one favorite saved, go to **Home** → a "Favorites · See all ›" section sits below the Continue-listening hero, above the entry tiles, showing artist chips and a row of saved-show cards. "See all ›" jumps to the Favorites view. Remove all favorites → the strip disappears and Home looks as before.

- [ ] **Step 5: Commit**

```bash
git add AppleNugs/Views/HomeView.swift
git commit -m "Add Favorites strip to the Home landing"
```

---

## Task 9: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Clean build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`, zero `error:` and zero `warning: .*Swift` lines.

- [ ] **Step 2: Walk the spec's verification checklist**

Run the app and confirm each:
1. Star an artist and a show from their headers → stars fill; both appear in the Favorites view and the Home strip.
2. Save the playing show from the now-playing star; confirm it's disabled for a single-track Search play and when idle.
3. Right-click an artist row and a search result → add/remove works; menu label flips.
4. Relaunch the app → favorites persist (file at `~/Library/Application Support/AppleNugs/favorites.json`); toggling in one place updates everywhere.
5. Switch through all four themes → Favorites view, strip, and stars adopt each theme; sidebar shows text-only labels.
6. Log out and back in → favorites are still present.

- [ ] **Step 3: Final commit (if any verification tweaks were needed)**

```bash
git add -A
git commit -m "Favorites: verification pass fixes" || echo "nothing to commit"
```

- [ ] **Step 4: Hand back for merge**

Report results and offer to merge `favorites` → `main` (fast-forward) and delete the branch, matching the project's established flow.

---

## Self-review

**Spec coverage:**
- Data model & persistence (`FavoritesStore`, `FavArtist`, `FavShow`) → Task 1. ✓
- `QueueTrack.showId` → Task 2. ✓
- Detail-header stars → Task 5. ✓
- Now-playing star (transport + faceplate) → Task 7. ✓
- Context menus (artist list, show rows, search) → Task 6. ✓
- Favorites view (text-only sidebar, stacked sections, empty state) → Task 4. ✓
- Home strip → Task 8. ✓
- Persist across logout (AppModel does not clear favorites) → Task 1, Step 2 note; verified Task 9. ✓
- Themed across all four themes → token usage throughout; verified Task 9. ✓
- Out-of-scope (tracks, sync, reorder) → not implemented. ✓

**Type consistency:** `FavoritesStore` API (`isArtistFavorited`, `toggleArtist(id:name:)`, `isShowFavorited`, `toggleShow(id:title:artistName:dateText:venue:imageURL:)`, `artists`, `shows`, `isEmpty`) is used identically in Tasks 4–8. `FavShow.imageURL: String?` is produced as `URL?.absoluteString` (album/container) or via `NugsConstants.imageURL(path:)?.absoluteString` (now-playing) and consumed as `URL(string:)` in `ShowCard`. `Route.artist`/`Route.album` and `ArtistEntry(id:name:)` match existing usage.

**Placeholder scan:** No TBD/TODO; every code step shows full code; commands include expected output.

**One known limitation (documented, consistent with spec):** a now-playing show restored from `nowplaying.json` after relaunch has no `showId` (not persisted in v1), so its transport star is disabled until you re-open/replay the show. The header star on the show page always works.
