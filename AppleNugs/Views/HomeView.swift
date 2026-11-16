import SwiftUI

/// The landing surface. A calm, editorial counterpoint to the dense catalog:
/// a time-aware greeting, favorites, and a taste of the crate to invite
/// digging.
///
/// Both platforms carry a "continue listening" hero while a track is loaded:
/// on iPhone the blister pack (Tim's ruling 1), on the Mac the flat card-stock
/// `YetiResumeCard` (ruling 4); both live in `HomeResumeHero.swift`. The Mac
/// also gets two entry tiles (`entryRow`), desktop-only by design.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(\.theme) private var theme

    @State private var sample: [ArtistEntry] = []
    @State private var artistCount = 0
    @State private var appeared = false
    @State private var sampleError: String?
    /// The crate artists' photos, by artist id. Empty until the lookup lands
    /// (and for good if it fails) — tiles show the monogram meanwhile.
    @State private var avatars: [String: URL] = [:]
    /// Starts true: the fetch is already coming, and a one-frame "nothing in
    /// the crate" is a worse lie than a spinner nobody sees.
    @State private var loadingSample = true

    private var player: PlayerService { app.player }

    /// Whether a hero renders at all. This body reads `current` and nothing
    /// else of the player; the hero host reads the rest.
    private var showsHero: Bool { player.current != nil }

    /// The rest of the app pads to 16–20; 36 is a wide-window luxury.
    #if os(iOS)
    private var horizontalPadding: CGFloat { 20 }
    #else
    private var horizontalPadding: CGFloat { 36 }
    #endif

    /// Home's measured content width (inside the padding, under the 880 cap).
    /// 0 until the first measurement lands, which `HomeColumns` answers with
    /// one column. iOS reads it; the Mac never splits.
    @State private var contentWidth: CGFloat = 0

    private var columns: HomeColumns {
        #if os(iOS)
        HomeColumns.columns(width: contentWidth, hasHero: showsHero)
        #else
        .single
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                greeting.reveal(appeared, 0)
                switch columns {
                case .single:
                    if showsHero { YetiHeroHost().reveal(appeared, 1) }
                    sections
                case .split(let leading):
                    // The wide canvas (the Duo's inner display): the hero keeps
                    // its designed upright pack in a leading column instead of
                    // stretching into a long card, and the rest sits beside it.
                    HStack(alignment: .top, spacing: HomeColumns.gutter) {
                        YetiHeroHost()
                            .frame(width: leading)
                            .reveal(appeared, 1)
                        VStack(alignment: .leading, spacing: 30) { sections }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            // Fill the proposal rather than hug the content, so the reading
            // below is the width Home has — not the widest section's.
            .frame(maxWidth: .infinity, alignment: .leading)
            // Never animate the switch: the first frame is unmeasured (one
            // column), and the reveal animation would otherwise morph it into
            // the split on the Duo.
            .animation(nil, value: columns)
            #if os(iOS)
            // Measured inside the padding and the cap, so this is the width
            // the columns actually share. Both arrangements fill it, so the
            // reading never depends on which one is showing. iOS only: the Mac
            // never splits, and a window resize shouldn't re-run Home's body.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            #endif
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 34)
            .padding(.bottom, 40)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.base)
        .navigationTitle("Home")
        .compactNavigationTitle()
        .task { await loadSample() }
        .onAppear { appeared = true }
    }

    /// Everything after the hero, in order — one column's tail, or the whole
    /// trailing column of a split.
    @ViewBuilder private var sections: some View {
        if !app.favorites.isEmpty { favoritesStrip.reveal(appeared, 2) }
        #if os(macOS)
        entryRow.reveal(appeared, 3)
        #endif
        if app.listening.hasAnyPlay {
            ListeningLedger().reveal(appeared, 4)
        }
        crate.reveal(appeared, 5)
    }

    // --- greeting -----------------------------------------------------------

    /// No eyebrow: the greeting stands alone.
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greetingText)
                .font(theme.type.hero(greetingSize))
                .foregroundStyle(theme.palette.textPrimary)
            Text(theme.copy.homeLede)
                .font(theme.type.body(16))
                .foregroundStyle(theme.palette.textSecondary)
        }
    }

    /// 42 on the Mac; the iPhone sets the greeting at the large-title size
    /// (`.large-title { font-size: 34px }`) to leave the hero room above the
    /// fold.
    private var greetingSize: CGFloat {
        #if os(iOS)
        34
        #else
        42
        #endif
    }

    /// Said plainly — "Good evening", no period — but "Late set." is a
    /// sentence, and keeps its stop.
    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Late set."
        }
    }

    // --- entry points -------------------------------------------------------

    // macOS only: on iPhone these two tiles re-open Artists and Search, which
    // the tab bar already puts one tap away.
    #if os(macOS)
    private var entryRow: some View {
        HStack(spacing: 14) {
            EntryTile(icon: "music.mic",
                      title: "Artists",
                      subtitle: artistCount > 0 ? "\(artistCount) in the catalog" : "Browse the catalog") {
                ui.sidebarSelection = .artists
            }
            EntryTile(icon: "magnifyingglass",
                      title: "Search",
                      subtitle: "Shows, songs, venues") {
                ui.requestSearchFocus()
            }
        }
    }
    #endif

    // --- from the crate -----------------------------------------------------

    /// On iPhone this is the only section that always renders — no entry
    /// tiles, the hero only while a track is loaded, and favorites may well be
    /// empty. So it has to account for
    /// itself when it's loading, empty, or offline, or a new user's Home is a
    /// greeting alone on a blank screen, promising a crate that never arrives.
    private var crate: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("From the crate")
                .font(theme.type.section(sectionSize))
                .foregroundStyle(theme.palette.textPrimary)

            if !sample.isEmpty {
                crateGrid
            } else if loadingSample {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 6)
            } else {
                crateNotice
            }
        }
    }

    @ViewBuilder
    private var crateNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sampleError {
                Text("Couldn't reach the catalog. \(sampleError)")
                    .font(theme.type.body(14))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await loadSample() } }
                    .buttonStyle(.bordered)
                    .tint(theme.palette.accent)
            } else {
                Text("The catalog came back empty.")
                    .font(theme.type.body(14))
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// The crate's grid. The Mac keeps the design sheet's `.crategrid`: rows of
    /// a small monogram and the name, three across a ~800pt Home. iOS gets
    /// compact TILES instead — monogram above, name below — because rows sized
    /// for the Mac ran the full width of a phone (one ~350pt bar per artist)
    /// and of the Duo's right column, mostly bare. Tiles put three across a
    /// portrait phone and five across the flat Duo's column.
    private var crateGrid: some View {
        LazyVGrid(columns: [GridItem(crateColumn, spacing: crateSpacing)],
                  alignment: .leading, spacing: crateSpacing) {
            ForEach(sample) { artist in
                NavigationLink(value: Route.artist(artist)) {
                    crateCell(artist)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.palette.raised)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    #if os(iOS)
    private var crateColumn: GridItem.Size { .adaptive(minimum: 92, maximum: 132) }
    private var crateSpacing: CGFloat { 10 }

    /// The artist's photo in a circle (Apple Music's shape for an artist, so it
    /// reads apart from the square show covers in Favorites above), the name
    /// centered below.
    ///
    /// Names are never cut off for ~98% of the catalog: up to three lines,
    /// shrinking to 85% before truncating (median name 14 characters, 1 in 10
    /// past 27, the longest 62). Two lines are always reserved, and the tile
    /// stretches to its row, so a row of short and long names lines up.
    private func crateCell(_ artist: ArtistEntry) -> some View {
        VStack(spacing: 8) {
            ArtistPortrait(url: avatars[artist.id], name: artist.name)
            ZStack(alignment: .top) {
                // Holds two lines' height at the current Dynamic Type size.
                Text(" ").lineLimit(2, reservesSpace: true).hidden()
                Text(artist.name)
                    .foregroundStyle(theme.palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            .font(theme.type.body(13))
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    #else
    private var crateColumn: GridItem.Size { .adaptive(minimum: 200, maximum: 280) }
    private var crateSpacing: CGFloat { 12 }

    private func crateCell(_ artist: ArtistEntry) -> some View {
        HStack(spacing: 11) {
            MonogramTile(text: artist.name, size: 36)
            Text(artist.name)
                .font(theme.type.body(14))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(8)
    }
    #endif

    /// Section headers: `.sec h3`'s heavy 22.
    private var sectionSize: CGFloat { 22 }

    // --- favorites strip ----------------------------------------------------

    private var favoritesStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Favorites")
                    .font(theme.type.section(sectionSize))
                    .foregroundStyle(theme.palette.textPrimary)
                Spacer()
                Button("See all") { ui.sidebarSelection = .favorites }
                    .buttonStyle(.plain)
                    .font(theme.type.body(14))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            if !app.favorites.artists.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(app.favorites.artists.prefix(8)) { fav in
                        NavigationLink(value: Route.artist(ArtistEntry(id: fav.id, name: fav.name))) {
                            HStack {
                                Text(fav.name)
                                    .font(theme.type.body(13.5).weight(.bold))
                                    .foregroundStyle(theme.palette.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(theme.palette.raised)
                                    // `.chips span`: shelf with a frost keyline.
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(theme.palette.hairline, lineWidth: 1)
                                    }
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

    private func loadSample() async {
        guard sample.isEmpty else { return }
        loadingSample = true
        defer { loadingSample = false }
        do {
            let all = try await app.artists()
            artistCount = all.count
            sample = Array(all.shuffled().prefix(9))
            sampleError = nil
        } catch {
            sampleError = error.localizedDescription
        }
        #if os(iOS)
        // Photos are a nicety on top of a crate that already works: a failure
        // leaves the monograms, and reports nothing.
        if !sample.isEmpty {
            avatars = (try? await app.artistAvatars(ids: sample.map(\.id))) ?? [:]
        }
        #endif
    }
}

// MARK: - Yeti hero host

/// Reads the player for the Home hero and hands the hero plain values, so
/// `isPlaying`, the cover, the pick and the specs subscribe this small view —
/// not the greeting, favorites strip, ledger and crate around it. (Playback
/// time is read one level further down still, in `ResumeProgressRule`.)
private struct YetiHeroHost: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openNowPlaying) private var openNowPlaying

    var body: some View {
        let player = app.player
        if let track = player.current {
            #if os(iOS)
            YetiHomeHero(track: track,
                         image: player.nowPlayingImage,
                         isPlaying: player.isPlaying,
                         isBuffering: player.isBuffering,
                         price: PriceStickerLabel(player: player),
                         onToggle: { player.togglePlayPause() },
                         onOpen: { openNowPlaying?() })
            #else
            YetiResumeCard(track: track,
                           image: player.nowPlayingImage,
                           isPlaying: player.isPlaying,
                           isBuffering: player.isBuffering,
                           onToggle: { player.togglePlayPause() })
            #endif
        }
    }
}

// MARK: - Entry tile

#if os(macOS)
private struct EntryTile: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.palette.accent)
                Spacer(minLength: 14)
                Text(title)
                    .font(theme.type.title(19))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(subtitle)
                    .font(theme.type.body(12))
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.palette.raised)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(hovering ? theme.palette.accent.opacity(0.6) : theme.palette.hairline,
                                          lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .offset(y: hovering ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
    }
}
#endif

// MARK: - Staggered reveal

private struct Reveal: ViewModifier {
    let appeared: Bool
    let index: Int
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.07), value: appeared)
    }
}

private extension View {
    func reveal(_ appeared: Bool, _ index: Int) -> some View {
        modifier(Reveal(appeared: appeared, index: index))
    }
}

#if os(iOS)
// MARK: - Artist portrait

/// An artist's photo clipped to a circle, filling the width it's given. The
/// monogram stands in while the photo loads, when there is none, and when it
/// fails — so a crate with no network still reads as artists, not holes.
private struct ArtistPortrait: View {
    @Environment(\.theme) private var theme

    let url: URL?
    let name: String

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            monogram(side)
                        }
                    }
                } else {
                    monogram(side)
                }
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(theme.palette.hairline, lineWidth: 1) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func monogram(_ side: CGFloat) -> some View {
        MonogramTile(text: name, size: side)
    }
}
#endif

