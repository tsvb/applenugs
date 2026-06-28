import SwiftUI
import Sparkle

@main
struct AppleNugsApp: App {
    @State private var app = AppModel()
    @State private var ui = UIState()
    @State private var themes = ThemeManager()

    private let updaterController: SPUStandardUpdaterController
    @StateObject private var updaterModel: UpdaterViewModel

    init() {
        // Size the shared HTTP cache so the nugs CDN's cover art and video
        // posters are reused across scroll and navigation instead of re-fetched
        // — AsyncImage loads through URLSession.shared → URLCache.shared, which
        // defaults to a tiny in-memory cache.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)

        // Start Sparkle at launch. With SUEnableAutomaticChecks unset, the
        // first check prompts the user to enable automatic update checks.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController = controller
        _updaterModel = StateObject(wrappedValue: UpdaterViewModel(updater: controller.updater))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(ui)
                .environment(themes)
                .environment(\.theme, themes.theme)
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1220, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
                .disabled(!updaterModel.canCheckForUpdates)
            }
            CommandGroup(after: .toolbar) {
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
                Divider()
            }
            CommandMenu("Playback") {
                Button(app.player.isPlaying ? "Pause" : "Play") {
                    app.player.togglePlayPause()
                }
                .disabled(app.player.current == nil)

                Button("Next Track") { app.player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                    .disabled(!app.player.hasNext)

                Button("Previous Track") { app.player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                    .disabled(!app.player.hasPrevious)

                Divider()

                Button("Clear Queue") { app.player.clear() }
                    .disabled(app.player.queue.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button("Search") { ui.requestSearchFocus() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button(ui.inspectorOpen ? "Hide Dashboard" : "Show Dashboard") {
                    ui.inspectorOpen.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}
