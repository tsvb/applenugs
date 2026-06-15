import SwiftUI

/// The landing surface. A calm, editorial counterpoint to the dense catalog:
/// a time-aware greeting, a glowing "continue listening" hero, a couple of
/// restrained entry points, and a small taste of the crate to invite digging.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(\.theme) private var theme
    @Environment(\.artColor) private var artColor

    @State private var sample: [ArtistEntry] = []
    @State private var artistCount = 0
    @State private var appeared = false
    #if DEBUG
    @State private var showVideoTest = false
    #endif

    private var player: PlayerService { app.player }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                greeting.reveal(appeared, 0)
                if player.current != nil { resumeCard.reveal(appeared, 1) }
                if !app.favorites.isEmpty { favoritesStrip.reveal(appeared, 2) }
                entryRow.reveal(appeared, 3)
                if !sample.isEmpty { crate.reveal(appeared, 4) }
            }
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 40)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.palette.base)
        .navigationTitle("Home")
        .task { await loadSample() }
        .onAppear { appeared = true }
        #if DEBUG
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Play test video", systemImage: "play.rectangle") {
                    showVideoTest = true
                    Task { await app.video.play(Self.debugVideo) }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Debug: Open Probe Video", systemImage: "rectangle.stack.badge.play") {
                    ui.open(.video(id: "44463", title: "Probe Video"))
                }
                .help("Phase 3 debug: navigate to VideoDetailView via Route.video")
            }
        }
        .sheet(isPresented: $showVideoTest, onDismiss: { app.video.stop() }) {
            videoTestSheet
        }
        #endif
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

    @ViewBuilder
    private var resumeCard: some View {
        if let track = player.current {
            Button {
                player.togglePlayPause()
            } label: {
                HStack(spacing: 18) {
                    ArtChip(image: player.nowPlayingImage,
                            fallbackText: track.artist ?? track.title ?? "?",
                            size: 96)
                        .shadow(color: (artColor ?? theme.palette.accent).opacity(0.45), radius: 22, y: 6)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("CONTINUE LISTENING")
                            .font(theme.type.numeric(10))
                            .tracking(1.8)
                            .foregroundStyle(theme.palette.textSecondary)
                        Text(track.title ?? "Unknown track")
                            .font(theme.type.hero(24))
                            .foregroundStyle(theme.palette.textPrimary)
                            .lineLimit(1)
                        Text(NowPlayingMeta.line(track))
                            .font(theme.type.title(14))
                            .foregroundStyle(theme.palette.textSecondary)
                            .lineLimit(1)
                        progressRule.padding(.top, 6)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(theme.effectiveAccent(art: artColor))
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.palette.raised)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.clear)
                                .artWash(theme.washStyle, color: artColor)
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

    private var progressRule: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.palette.hairline)
                Capsule().fill(theme.effectiveAccent(art: artColor))
                    .frame(width: geo.size.width * resumeProgress)
            }
        }
        .frame(height: 3)
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var resumeProgress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return min(max(CGFloat(player.currentTime / player.duration), 0), 1)
    }

    // --- entry points -------------------------------------------------------

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

    // --- from the crate -----------------------------------------------------

    private var crate: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(theme.caps.contains(.condensedHeaders) ? "FROM THE CRATE" : "From the crate")
                .font(theme.type.section(15))
                .tracking(theme.caps.contains(.condensedHeaders) ? 1.6 : 0)
                .foregroundStyle(theme.palette.textPrimary)

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
        guard let all = try? await app.artists() else { return }
        artistCount = all.count
        sample = Array(all.shuffled().prefix(9))
    }

    #if DEBUG
    /// TEMPORARY Phase-2 verification harness. Removed in Phase 4 once VideosView
    /// can open VideoDetailView. Uses the Phase-0 probe's known video container.
    private static let debugVideo = VideoDetail(
        id: "44463",
        videoSku: 916156,
        isLive: false,
        title: "Test Video",
        artistName: "Phase 0 Probe",
        venue: nil,
        dateText: nil,
        description: nil,
        imagePath: nil,
        chapters: [],
        liveEvent: nil)

    private var videoTestSheet: some View {
        VStack(spacing: 0) {
            if let error = app.video.loadError {
                Text(error)
                    .font(theme.type.body(14))
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(40)
            } else {
                VideoPlayerSurface(player: app.video.player)
                    .frame(minWidth: 640, minHeight: 360)
            }
            HStack {
                Text("Audio resumes on close if it was playing.")
                    .font(theme.type.body(11))
                    .foregroundStyle(theme.palette.textSecondary)
                Spacer()
                Button("Close") { showVideoTest = false }
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(theme.palette.base)
    }
    #endif
}

// MARK: - Entry tile

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
