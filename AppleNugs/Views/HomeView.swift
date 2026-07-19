import SwiftUI

/// The landing surface. A calm, editorial counterpoint to the dense catalog:
/// a time-aware greeting, favorites, and a taste of the crate to invite
/// digging.
///
/// It also carries a glowing "continue listening" hero (see `resumeCard`),
/// shared across platforms. macOS additionally shows two entry tiles —
/// desktop-only by design, see `entryRow`.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(\.theme) private var theme
    #if os(macOS)
    /// Only the resume hero reads the art color. Left unguarded, this would
    /// re-render Home on every track change on iPhone, where the hero no
    /// longer exists.
    @Environment(\.artColor) private var artColor
    #endif

    @State private var sample: [ArtistEntry] = []
    @State private var artistCount = 0
    @State private var appeared = false
    @State private var sampleError: String?
    /// Starts true: the fetch is already coming, and a one-frame "nothing in
    /// the crate" is a worse lie than a spinner nobody sees.
    @State private var loadingSample = true

    private var player: PlayerService { app.player }

    /// The resume hero's art tint. macOS uses the per-track art color for its
    /// glow; iOS uses the theme accent so Home never re-renders on track change
    /// (the reason `artColor` is read only on macOS — see the `#if os(macOS)`
    /// property near the top of the struct).
    #if os(macOS)
    private var resumeTint: Color? { artColor }
    #else
    private var resumeTint: Color? { nil }
    #endif

    /// The rest of the app pads to 16–20; 36 is a wide-window luxury.
    #if os(iOS)
    private var horizontalPadding: CGFloat { 20 }
    #else
    private var horizontalPadding: CGFloat { 36 }
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                greeting.reveal(appeared, 0)
                if player.current != nil { resumeCard.reveal(appeared, 1) }
                if !app.favorites.isEmpty { favoritesStrip.reveal(appeared, 2) }
                #if os(macOS)
                entryRow.reveal(appeared, 3)
                #endif
                crate.reveal(appeared, 4)
            }
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

    // --- greeting -----------------------------------------------------------

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPLENUGS")
                .font(theme.type.numeric(11))
                .tracking(3)
                .foregroundStyle(theme.palette.accent)
            Text(greetingText)
                .font(theme.type.hero(42))
                .foregroundStyle(theme.palette.textPrimary)
            Text("Pick up where you left off — or dig through the crate.")
                .font(theme.type.title(16))
                .foregroundStyle(theme.palette.textSecondary)
        }
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default:      return "Late set."
        }
    }

    // --- continue listening (the hero) --------------------------------------

    private var resumeArtSize: CGFloat { 96 }
    private var resumeTitleSize: CGFloat { 24 }
    private var resumeGlyphSize: CGFloat { 48 }

    @ViewBuilder
    private var resumeCard: some View {
        if let track = player.current {
            Button {
                player.togglePlayPause()
            } label: {
                HStack(spacing: 18) {
                    ArtChip(image: player.nowPlayingImage,
                            fallbackText: track.artist ?? track.title ?? "?",
                            size: resumeArtSize)
                        .shadow(color: (resumeTint ?? theme.palette.accent).opacity(0.45), radius: 22, y: 6)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("CONTINUE LISTENING")
                            .font(theme.type.numeric(10))
                            .tracking(1.8)
                            .foregroundStyle(theme.palette.textSecondary)
                        Text(track.title ?? "Unknown track")
                            .font(theme.type.hero(resumeTitleSize))
                            .foregroundStyle(theme.palette.textPrimary)
                            .lineLimit(1)
                        Text(NowPlayingMeta.line(track))
                            .font(theme.type.title(14))
                            .foregroundStyle(theme.palette.textSecondary)
                            .lineLimit(1)
                        ResumeProgressRule(tint: resumeTint).padding(.top, 6)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: resumeGlyphSize))
                        .foregroundStyle(theme.effectiveAccent(art: resumeTint))
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.palette.raised)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.clear)
                                .artWash(theme.washStyle, color: resumeTint)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(theme.palette.hairline, lineWidth: 1)
                        }
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// A leaf view: the 4Hz currentTime dependency registers here, not on
    /// the whole editorial landing page.
    private struct ResumeProgressRule: View {
        let tint: Color?
        @Environment(AppModel.self) private var app
        @Environment(\.theme) private var theme

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.palette.hairline)
                    Capsule().fill(theme.effectiveAccent(art: tint))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)
            .frame(maxWidth: 320, alignment: .leading)
        }

        private var fraction: CGFloat {
            let player = app.player
            guard player.duration > 0 else { return 0 }
            return min(max(CGFloat(player.currentTime / player.duration), 0), 1)
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

    /// On iPhone this is the only section that always renders — no resume hero,
    /// no entry tiles, and favorites may well be empty. So it has to account for
    /// itself when it's loading, empty, or offline, or a new user's Home is a
    /// greeting alone on a blank screen, promising a crate that never arrives.
    private var crate: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(theme.caps.contains(.condensedHeaders) ? "FROM THE CRATE" : "From the crate")
                .font(theme.type.section(15))
                .tracking(theme.caps.contains(.condensedHeaders) ? 1.6 : 0)
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

    private var crateGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)],
            alignment: .leading, spacing: 12
        ) {
            ForEach(sample) { artist in
                NavigationLink(value: Route.artist(artist)) {
                    HStack(spacing: 11) {
                        MonogramTile(text: artist.name, size: 36)
                        Text(artist.name)
                            .font(theme.type.body(14))
                            .foregroundStyle(theme.palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(8)
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

    // --- favorites strip ----------------------------------------------------

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
