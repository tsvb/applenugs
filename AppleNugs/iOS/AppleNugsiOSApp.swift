import AVFAudio
import SwiftUI

@main
struct AppleNugsiOSApp: App {
    @State private var app = AppModel()
    @State private var ui = UIState()
    @State private var themes = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
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
