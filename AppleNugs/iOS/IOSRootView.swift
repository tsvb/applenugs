import SwiftUI

/// Phase A shell: one NavigationStack over the shared section views, driven by
/// the same UIState routing the Mac shell uses, with the shared TransportBar
/// pinned via safeAreaInset. Phase B replaces `mainLayout` with the real tab
/// shell; the session switch and theming here are permanent.
struct IOSRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui
    @Environment(ThemeManager.self) private var themes
    @Environment(\.theme) private var theme

    @State private var artProvider = ArtColorProvider()

    /// The accent the chrome should use right now: the live art color when the
    /// active theme is art-driven, else nil (so static themes are untouched).
    private var activeArtColor: Color? {
        theme.consumesArtColor ? artProvider.color : nil
    }

    /// Refires the extractor when the track changes, when its art finishes
    /// loading, or when the theme's appetite for art changes.
    private var artTaskID: String {
        let track = app.player.current?.id.uuidString ?? "none"
        return "\(track)|\(app.player.nowPlayingImage != nil)|\(theme.consumesArtColor)"
    }

    var body: some View {
        Group {
            switch app.sessionState {
            case .unknown:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loggedOut:
                LoginView()
            case .loggedIn:
                mainLayout
            case .connectionFailed(let message):
                connectionFailedView(message)
            }
        }
        .themed(theme, art: activeArtColor)
        .environment(\.artColor, activeArtColor)
        .task(id: artTaskID) {
            artProvider.update(
                image: app.player.nowPlayingImage,
                key: app.player.current?.artworkPath,
                enabled: theme.consumesArtColor)
        }
        .task { await app.bootstrap() }
    }

    private func connectionFailedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't reach nugs.net", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { Task { await app.retryBootstrap() } }
                .buttonStyle(.borderedProminent)
            Button("Sign Out") { app.logout() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainLayout: some View {
        @Bindable var ui = ui
        // The stack binds to the same navPath the shared views append Routes
        // to (UIState.open(_:)), so in-content pushes navigate here exactly
        // as they do in the Mac shell's detail column.
        return NavigationStack(path: $ui.navPath) {
            sectionRoot
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .artist(let artist):
                        ArtistDetailView(artist: artist)
                    case .album(let id, let title):
                        AlbumDetailView(albumId: id, titleHint: title)
                    case .video(let id, let title):
                        VideoDetailView(videoId: id, titleHint: title)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { sectionMenu }
                    ToolbarItem(placement: .topBarTrailing) { accountMenu }
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                TransportBar()
            }
        }
        .overlay(alignment: .bottom) { toastOverlay }
    }

    @ViewBuilder
    private var sectionRoot: some View {
        switch ui.sidebarSelection {
        case .home:
            HomeView()
        case .videos:
            VideosView()
        case .favorites:
            FavoritesView()
        case .search:
            SearchView()
        default:
            ArtistListView()
        }
    }

    /// Crude stand-in for the Mac sidebar until Phase B's tab bar: a menu
    /// that swaps the visible section (UIState resets navPath on change).
    private var sectionMenu: some View {
        @Bindable var ui = ui
        return Menu {
            Picker("Section", selection: $ui.sidebarSelection) {
                Text("Home").tag(UIState.SidebarItem?.some(.home))
                Text("Artists").tag(UIState.SidebarItem?.some(.artists))
                Text("Videos").tag(UIState.SidebarItem?.some(.videos))
                Text("Favorites").tag(UIState.SidebarItem?.some(.favorites))
                Text("Search").tag(UIState.SidebarItem?.some(.search))
            }
        } label: {
            Label("Browse", systemImage: "line.3.horizontal")
        }
    }

    private var accountMenu: some View {
        Menu {
            if case .loggedIn(let plan) = app.sessionState, let plan {
                Text(plan)
            }
            Picker("Theme", selection: Binding(
                get: { themes.selected },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.35)) { themes.selected = newValue }
                }
            )) {
                ForEach(ThemeID.allCases) { id in
                    Text(id.displayName).tag(id)
                }
            }
            .pickerStyle(.menu)
            Divider()
            Button("Log Out") { app.logout() }
        } label: {
            Label("Account", systemImage: "person.circle")
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = ui.toast {
            Text(toast)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 78)  // float above the transport bar
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}
