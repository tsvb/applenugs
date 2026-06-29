import SwiftUI
import Sparkle

@main
struct AppleNugsApp: App {
    @State private var app = AppModel()
    @State private var ui = UIState()
    @State private var themes = ThemeManager()
    #if DEBUG
    @NSApplicationDelegateAdaptor(UITestAppDelegate.self) private var uiTestDelegate
    #endif

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
        // Skip it under UI tests: Sparkle's installer/downloader XPC services
        // spawn per launch and, across the many rapid launches a test run does,
        // contend with window-server activation (the flaky "window never appeared").
        let startUpdater = !ProcessInfo.processInfo.arguments.contains("-UITEST")
        let controller = SPUStandardUpdaterController(
            startingUpdater: startUpdater, updaterDelegate: nil, userDriverDelegate: nil)
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
                // No hardcoded width floor. Each visible column declares its own
                // minimum (sidebar 150 + detail 480 + inspector 250, in RootView),
                // and .windowResizability(.contentMinSize) below sums the
                // currently-visible columns + dividers into the enforced window
                // minimum. That floor is content-derived and adapts automatically
                // when the Dashboard inspector toggles — so the window can never
                // be narrower than its columns need, and the sidebar can never
                // overflow/clip past the left edge. (A hardcoded constant here was
                // the bug: it undershot the real 3-column width, so at the floor
                // the content overflowed and clipped the sidebar.)
                .frame(minHeight: 600)
                .modifier(UITestWindowSize())
        }
        .defaultSize(width: 1320, height: 820)
        .windowResizability(.contentMinSize)
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

/// In UI tests only, park the window at its ENFORCED minimum size so layout
/// regressions are tested at the real window-minimum layer — the layer where the
/// sidebar-clip bug actually lives. Launched with `-UITestShrinkWindow`, it asks
/// the window for an absurdly small frame; AppKit clamps that UP to the window's
/// content-derived minimum (from `.windowResizability(.contentMinSize)`), leaving
/// the window exactly at its minimum width.
///
/// This deliberately replaces the old `-UITestWindowWidth` forced-`.frame(width:)`
/// approach, which HID this bug: a fixed content frame squeezes the columns to
/// fit, whereas a real window at its minimum lets the content keep its intrinsic
/// size and overflow — which is precisely the failure being guarded against.
///
/// A strict no-op in normal/release runs: compiled out of release, and inert
/// unless `-UITestShrinkWindow` is present.
private struct UITestWindowSize: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        content.background(UITestWindowMinimizer())
        #else
        content
        #endif
    }
}

#if DEBUG
/// Reaches the hosting `NSWindow` and shrinks it so AppKit clamps it to the
/// enforced (content-derived) minimum. Only active when `-UITestShrinkWindow`
/// is passed; inert in all other launches.
private struct UITestWindowMinimizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-UITestShrinkWindow") else { return probe }
        // Defer until the window exists and initial layout (hence the
        // content-derived minimum) is established, then request a tiny frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak probe] in
            guard let window = probe?.window else { return }
            var frame = window.frame
            frame.size.width = 200          // clamped up to the enforced minimum
            window.setFrame(frame, display: true)
        }
        return probe
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

#if DEBUG
/// Handles the one lifecycle gap that SwiftUI's App protocol can't cover for
/// UI tests: on macOS Tahoe, apps launched without a user gesture (as XCUITest
/// does) start in a "hidden" state. SwiftUI's WindowGroup skips window creation
/// for hidden apps. `NSApp.unhide` restores normal foreground state so the
/// window is created and XCTest can query it.
private class UITestAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST") else { return }
        DispatchQueue.main.async {
            NSApp.unhide(nil)
        }
    }
}
#endif
