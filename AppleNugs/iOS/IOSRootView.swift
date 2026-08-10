import SwiftUI
import UIKit

/// The iPhone shell: a tab per Mac sidebar section, each with its own
/// NavigationStack over the shared UIState routing, and the now-playing pill
/// hosted in the TabView's bottom accessory.
///
/// The pill lives in the accessory rather than in a per-tab `safeAreaInset`
/// because the accessory belongs to the TabView: it rides above pushed detail
/// screens for free. The old inset decorated each stack's *root* view, so the
/// bar vanished the moment anything was pushed.
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
    /// Offline library sheet reachable from the connection-failed screen.
    @State private var offlineShown = false
    /// The pill's expanded panel. Owned here, not by the pill — see the sheet.
    @State private var panelShown = false

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
        // Deep links (applenugs://show/…). Parse here; AppModel acts now if the
        // session is up, or stashes for the drain below. Drop the now-playing
        // cover on receipt — the router pushes the linked show onto the shared
        // stack, and a video's playback only starts once VideoDetailView is on
        // screen, so behind an opaque cover it would play blind. None of the
        // Mac's NSApp plumbing: iOS foregrounds us on open, and there is one scene.
        .onOpenURL { url in
            guard let link = DeepLink.parse(url) else { return }
            nowPlayingPresented = false
            app.receiveDeepLink(link, ui: ui)
        }
        // Replay a link that arrived before login/bootstrap finished — which is
        // every cold-launch link, since bootstrap awaits the session before
        // flipping isLoggedIn. The iOS analog of RootView's drain: same
        // serialized channel, nil'd first so a duplicate fire can't double-open.
        .task(id: app.isLoggedIn) {
            if app.isLoggedIn, let link = app.pendingDeepLink {
                app.pendingDeepLink = nil
                nowPlayingPresented = false
                app.handleDeepLink(link, ui: ui)
            }
        }
    }

    private func connectionFailedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't reach nugs.net", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { Task { await app.retryBootstrap() } }
                .buttonStyle(.borderedProminent)
            // The whole point of downloads is being reachable right here.
            if !app.downloads.manifest.shows.isEmpty {
                Button("Listen Offline") { offlineShown = true }
            }
            Button("Sign Out") { app.logout() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $offlineShown) {
            NavigationStack {
                DownloadsView()
                    .navigationTitle("Downloads")
                    .compactNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { offlineShown = false }
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if app.player.current != nil {
                            // Sheets cannot host a tab accessory, so this is the
                            // one legitimate place the pill is mounted by hand.
                            // `tabViewBottomAccessoryPlacement` is nil here and
                            // PillLayout treats nil as .expanded. There is no
                            // full-screen player or panel to open from a
                            // connection-failed sheet, so both are no-ops/nil.
                            NowPlayingPill(onTap: { }, onExpand: nil)
                                .frame(height: 48)
                                .background(.thinMaterial, in: Capsule())
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
            }
            .presentationBackground(theme.palette.base)
        }
    }

    private var mainLayout: some View {
        @Bindable var ui = ui
        // One tab per Mac sidebar section. All tabs share the single
        // UIState.navPath (only the visible tab's stack is live, and UIState
        // resets the path whenever the section changes, so a background
        // tab can never hold stale path entries).
        return TabView(selection: $ui.sidebarSelection) {
            Tab("Home", systemImage: "house",
                value: UIState.SidebarItem?.some(.home)) {
                tabStack { HomeView() }
            }
            Tab("Artists", systemImage: "music.mic",
                value: UIState.SidebarItem?.some(.artists)) {
                tabStack { ArtistListView() }
            }
            Tab("Search", systemImage: "magnifyingglass",
                value: UIState.SidebarItem?.some(.search)) {
                tabStack { SearchView() }
            }
            Tab("Library", systemImage: "star",
                value: UIState.SidebarItem?.some(.favorites)) {
                tabStack { LibraryView() }
            }
            Tab("Videos", systemImage: "play.rectangle",
                value: UIState.SidebarItem?.some(.videos)) {
                tabStack { VideosView() }
            }
        }
        // The accessory belongs to the TabView, so it rides above every screen
        // — including pushed detail views — instead of decorating each stack's
        // root the way the old safeAreaInset did.
        .modifier(NowPlayingAccessory(
            app: app,
            onTap: { nowPlayingPresented = true },
            onExpand: { panelShown = true }))
        .fullScreenCover(isPresented: $nowPlayingPresented) {
            NowPlayingScreen()
        }
        // Presented here rather than from inside the pill: a sheet attached
        // within `tabViewBottomAccessory` runs its content's body but never
        // appears, because the accessory is a system-hosted container rather
        // than a normal presentation context.
        .sheet(isPresented: $panelShown) {
            ExpandedPlayerPanel()
                .presentationDetents([.height(250)])
                .presentationCornerRadius(26)
                .presentationBackground(.thinMaterial)
                .presentationDragIndicator(.visible)
        }
        .background(KeyCommandsHost(app: app, ui: ui))
        // A text field in the tab you just left keeps first responder across a
        // tab switch (switching tabs doesn't end its editing), which would
        // swallow the hardware-keyboard shortcuts — keys keep flowing into the
        // hidden field. Resign it on leave so KeyCommandsHost reclaims focus.
        // Skip when arriving at Search: the "/" shortcut switches here and then
        // focuses the field, and resigning would fight that.
        .onChange(of: ui.sidebarSelection) { _, newValue in
            if newValue != .search {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    /// One tab's stack: its own NavigationStack over the shared navPath, the
    /// shared Route destinations (so in-content pushes via UIState.open(_:)
    /// work exactly as in the Mac shell's detail column), and the account menu.
    @ViewBuilder
    private func tabStack<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        @Bindable var ui = ui
        // The toast overlay is attached to the NavigationStack itself, not
        // to `content()` (the stack's root view): the root is covered the
        // moment a destination is pushed, and its overlay along with it, so
        // a toast fired from a pushed screen — AlbumDetailView's "Playing
        // next" / "Added to queue" — would silently vanish. One level out,
        // the overlay stays visible across every push in this stack.
        NavigationStack(path: $ui.navPath) {
            content()
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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { accountMenu }
                }
        }
        .overlay(alignment: .bottom) { toastOverlay }
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
                // This overlay is attached to the NavigationStack itself, one
                // level above `content()` (see `tabStack` above) — but the
                // NavigationStack is still a Tab's content, and it's *being*
                // a Tab's content that gets the accessory pill and the tab
                // bar excluded from the safe area, not specifically being
                // `content()`. So the exclusion still applies here, and a
                // plain 8pt still clears the pill by construction at any
                // chrome height. Confirmed live at the stack root (a deep
                // link's failure toast, screenshot in the branch's
                // final-review report); a pushed destination sits under the
                // same overlay by construction, so the same safe area and
                // padding apply there too, but that specific case wasn't
                // exercised with a live tap (see the report for why).
                .padding(.bottom, 8)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}

/// Hosts `NowPlayingPill` in the `TabView`'s bottom accessory.
///
/// `tabViewBottomAccessory(isEnabled:content:)` is the overload that hides the
/// accessory entirely when nothing is playing; it is iOS 26.1+, which is why
/// the deployment target is 26.1 rather than 26.0. The content-only overload
/// (26.0) has no way to reclaim the slot, so an idle player would leave a 48pt
/// gap above the tab bar.
private struct NowPlayingAccessory: ViewModifier {
    let app: AppModel
    let onTap: () -> Void
    let onExpand: () -> Void

    func body(content: Content) -> some View {
        content
            .tabViewBottomAccessory(isEnabled: app.player.current != nil) {
                NowPlayingPill(onTap: onTap, onExpand: onExpand)
            }
            .tabBarMinimizeBehavior(.onScrollDown)
    }
}
