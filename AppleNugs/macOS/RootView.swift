import SwiftUI

struct RootView: View {
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
        .onAppear { KeyboardShortcuts.install(app: app, ui: ui) }
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
        // NavigationSplitView is the top-level content (not nested in a VStack)
        // so its toolbar is hosted at the window level: trailing items anchor to
        // the window's right edge and don't fold into the ⋯ overflow when the
        // sidebar slides in and narrows the detail column. The transport bar is
        // pinned with safeAreaInset — the idiomatic persistent bottom bar.
        return NavigationSplitView {
            List(selection: $ui.sidebarSelection) {
                Text("Home")
                    .tag(UIState.SidebarItem.home)
                    .accessibilityIdentifier("sidebar.item.home")
                Text("Artists")
                    .tag(UIState.SidebarItem.artists)
                    .accessibilityIdentifier("sidebar.item.artists")
                Text("Videos")
                    .tag(UIState.SidebarItem.videos)
                    .accessibilityIdentifier("sidebar.item.videos")
                Text("Favorites")
                    .tag(UIState.SidebarItem.favorites)
                    .accessibilityIdentifier("sidebar.item.favorites")
                Text("Downloads")
                    .tag(UIState.SidebarItem.downloads)
                    .accessibilityIdentifier("sidebar.item.downloads")
                Text("Search")
                    .tag(UIState.SidebarItem.search)
                    .accessibilityIdentifier("sidebar.item.search")
            }
            .accessibilityIdentifier("sidebar.list")
            .scrollContentBackground(.hidden)
            .background(theme.palette.base)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 240)
        } detail: {
            NavigationStack(path: $ui.navPath) {
                detailRoot
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .artist(let artist):
                            ArtistDetailView(artist: artist)
                        case .album(let id, let title):
                            AlbumDetailView(albumId: id, titleHint: title)
                        case .video(let id, let title):
                            VideoDetailView(videoId: id, titleHint: title)
                        case .webcast(let ctx):
                            VideoDetailView(videoId: ctx.id, titleHint: ctx.title, webcast: ctx)
                        }
                    }
            }
            // The detail column must declare an honest minimum so it participates
            // in the window's enforced minimum: the window floor is the SUM of the
            // visible columns' minimums, so a detail reporting ~0 would let the
            // window squeeze the detail and overflow/clip the sidebar. 480 is the
            // narrowest width the editorial detail content stays usable at.
            .frame(minWidth: 480, idealWidth: 760, maxWidth: .infinity)
        }
        .inspector(isPresented: $ui.inspectorOpen) {
            DashboardPanel()
                .inspectorColumnWidth(min: 250, ideal: 300, max: 380)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ui.inspectorOpen.toggle()
                } label: {
                    Label("Dashboard", systemImage: "sidebar.right")
                }
                .help("Toggle the dashboard panel (⌥⌘I)")
            }
            ToolbarItem(placement: .primaryAction) {
                accountMenu
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                TransportBar()
            }
        }
        .overlay(alignment: .bottom) { toastOverlay }
        // WindowMinSizeUpdater keeps NSWindow.minSize in sync with the visible
        // columns. .windowResizability(.contentMinSize) alone does not include
        // the inspector's 250pt minimum, so the window could be dragged narrower
        // than sidebar+detail+inspector, clipping the sidebar off the left edge.
        .background(WindowMinSizeUpdater(inspectorOpen: ui.inspectorOpen))
        // Replay a deep link that arrived before login/bootstrap finished. This
        // layout only exists once `.loggedIn`, so the task fires exactly when the
        // app is ready. Goes through the serialized channel so it can't interleave
        // with a link that arrives at almost the same moment.
        .task(id: app.isLoggedIn) {
            if app.isLoggedIn, let link = app.pendingDeepLink {
                app.pendingDeepLink = nil
                app.handleDeepLink(link, ui: ui)
            }
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch ui.sidebarSelection {
        case .home:
            HomeView()
        case .videos:
            VideosView()
        case .favorites:
            FavoritesView()
        case .downloads:
            DownloadsView()
        case .search:
            SearchView()
        default:
            ArtistListView()
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

// MARK: - Window minimum size

/// Keeps `NSWindow.minSize` in sync with the visible columns so the user
/// cannot drag the window narrower than its content requires — the real fix
/// for the sidebar-clip bug.
///
/// `.windowResizability(.contentMinSize)` alone does not include the
/// Dashboard inspector's 250pt minimum in its calculation, so the window
/// could be dragged to a width where the inspector pushes the detail column
/// (and ultimately the sidebar) off the left edge. This struct reaches into
/// AppKit directly and updates `minSize` whenever the inspector toggles.
private struct WindowMinSizeUpdater: NSViewRepresentable {
    var inspectorOpen: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        // sidebar min (150) + detail min (480) + inspector min (250 when open)
        // + 1pt per visible column divider
        let width: CGFloat = 150 + 480 + (inspectorOpen ? 250 + 1 : 0) + 1
        window.minSize = CGSize(width: width, height: 600)
    }
}
