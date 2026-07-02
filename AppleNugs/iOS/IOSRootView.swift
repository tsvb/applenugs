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
    // Starts presented under -UITestShowNowPlaying so layout screenshots can
    // reach the full-screen player without a tap (simctl cannot tap).
    @State private var nowPlayingPresented =
        ProcessInfo.processInfo.arguments.contains("-UITestShowNowPlaying")

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
        // One tab per Mac sidebar section. All tabs share the single
        // UIState.navPath (only the visible tab's stack is live, and UIState
        // resets the path whenever the section changes, so a background
        // tab can never hold stale path entries).
        return TabView(selection: $ui.sidebarSelection) {
            tab(.home, "Home", systemImage: "house") { HomeView() }
            tab(.artists, "Artists", systemImage: "music.mic") { ArtistListView() }
            tab(.search, "Search", systemImage: "magnifyingglass") { SearchView() }
            tab(.favorites, "Library", systemImage: "star") { LibraryView() }
            tab(.videos, "Videos", systemImage: "play.rectangle") { VideosView() }
        }
        .overlay(alignment: .bottom) { toastOverlay }
        .fullScreenCover(isPresented: $nowPlayingPresented) {
            NowPlayingScreen()
        }
    }

    /// One tab: its own NavigationStack over the shared navPath, the shared
    /// Route destinations (so in-content pushes via UIState.open(_:) work
    /// exactly as in the Mac shell's detail column), and the account menu.
    private func tab<Content: View>(
        _ item: UIState.SidebarItem, _ title: String, systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        @Bindable var ui = ui
        return NavigationStack(path: $ui.navPath) {
            content()
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
                    ToolbarItem(placement: .topBarTrailing) { accountMenu }
                }
                // Inset per tab (not on the TabView) so the bar docks above
                // the tab bar instead of covering it.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if app.player.current != nil {
                        VStack(spacing: 0) {
                            Divider()
                            TransportBar()
                        }
                        // Buttons inside the bar win over this container tap.
                        .contentShape(Rectangle())
                        .onTapGesture { nowPlayingPresented = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens full-screen now playing")
                    }
                }
        }
        .tabItem { Label(title, systemImage: systemImage) }
        .tag(UIState.SidebarItem?.some(item))
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
