import AVFAudio
import SwiftUI

@main
struct AppleNugsiOSApp: App {
    @State private var app = AppModel()
    @State private var ui: UIState
    @State private var themes = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase
    // Portrait-locked app, rotatable fullscreen video (see OrientationGate).
    @UIApplicationDelegateAdaptor(OrientationGate.self) private var orientationGate

    init() {
        // Launch-arg tab/theme selection for layout screenshots under -UITEST
        // (simctl cannot tap; XCUITest on iOS is future work).
        let ui = UIState()
        #if DEBUG
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-UITestTab"),
           ProcessInfo.processInfo.arguments.indices.contains(i + 1) {
            switch ProcessInfo.processInfo.arguments[i + 1] {
            case "artists": ui.sidebarSelection = .artists
            case "search": ui.sidebarSelection = .search
            case "favorites": ui.sidebarSelection = .favorites
            case "videos": ui.sidebarSelection = .videos
            default: break
            }
        }
        let themes = ThemeManager()
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-UITestTheme"),
           ProcessInfo.processInfo.arguments.indices.contains(i + 1),
           let id = ThemeID(rawValue: ProcessInfo.processInfo.arguments[i + 1]) {
            themes.selected = id
        }
        _themes = State(initialValue: themes)
        #endif
        _ui = State(initialValue: ui)
        // Same CDN-artwork cache sizing as the Mac entry point: AsyncImage
        // loads through URLSession.shared → URLCache.shared, which defaults
        // to a tiny in-memory cache.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)

        // .playback: audible with the silent switch on and eligible for
        // background audio (with UIBackgroundModes=audio). Activation happens
        // when playback starts, not at launch.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environment(app)
                .environment(ui)
                .environment(themes)
                .environment(\.theme, themes.theme)
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS has no reliable willTerminate; persist on every backgrounding.
            if phase == .background { app.player.persistNow() }
        }
    }
}
