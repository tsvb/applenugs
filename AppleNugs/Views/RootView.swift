import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(UIState.self) private var ui

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
            }
        }
        .task { await app.bootstrap() }
        .onAppear { KeyboardShortcuts.install(app: app, ui: ui) }
    }

    private var mainLayout: some View {
        @Bindable var ui = ui
        return VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $ui.sidebarSelection) {
                    Label("Artists", systemImage: "music.mic")
                        .tag(UIState.SidebarItem.artists)
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(UIState.SidebarItem.search)
                }
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
                            }
                        }
                }
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

            Divider()
            TransportBar()
        }
        .overlay(alignment: .bottom) { toastOverlay }
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch ui.sidebarSelection {
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
