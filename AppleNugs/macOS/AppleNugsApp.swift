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

    private let updaterController: SPUStandardUpdaterController?
    @StateObject private var updaterModel: UpdaterViewModel

    init() {
        // Size the shared HTTP cache so the nugs CDN's cover art and video
        // posters are reused across scroll and navigation instead of re-fetched
        // — AsyncImage loads through URLSession.shared → URLCache.shared, which
        // defaults to a tiny in-memory cache.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)

        // Skip Sparkle entirely under UI tests. Even SPUStandardUpdaterController
        // creation (with startingUpdater: false) may touch the Keychain or spawn
        // XPC helpers that contend with window-server activation and prevent the
        // app window from appearing when launched without a user gesture.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            updaterController = nil
            _updaterModel = StateObject(wrappedValue: UpdaterViewModel(updater: nil))
            return
        }
        #endif
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
                // Window minimum width is managed by WindowMinSizeUpdater in
                // RootView — it sets NSWindow.minSize directly so it correctly
                // accounts for the inspector column (250pt) when it is open.
                .frame(minHeight: 600)
                #if DEBUG
                .modifier(UITestWindowSize())
                #endif
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController?.checkForUpdates(nil)
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

#if DEBUG
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
private struct UITestWindowSize: ViewModifier {
    func body(content: Content) -> some View {
        content.background(UITestWindowMinimizer())
    }
}

/// Reaches the hosting `NSWindow` and shrinks it so AppKit clamps it to the
/// enforced minimum (set by `WindowMinSizeUpdater` in RootView). Only active
/// when `-UITestShrinkWindow` is passed; inert in all other launches.
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
/// Handles the lifecycle gap that SwiftUI's App protocol can't cover for
/// UI tests: XCUITest launches the app without a user gesture so it starts
/// in a background/inactive state. SwiftUI's WindowGroup skips window
/// creation until the app becomes the active application. We hook every
/// relevant lifecycle event to coax activation and window-creation out of
/// both the app itself and SwiftUI's internal scene machinery.
private class UITestAppDelegate: NSObject, NSApplicationDelegate {

    /// Very early — before SwiftUI even sets up its scene infrastructure.
    /// Requesting activation here gives the system the maximum lead time to
    /// grant it before SwiftUI makes its window-creation decision.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST") else { return }
        NSApp.unhide(nil)
        NSApp.activate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST") else { return }
        NSApp.unhide(nil)
        NSApp.activate()
    }

    /// Fires when the app actually becomes active — either because our
    /// activate() above was granted, or because the test's app.activate()
    /// triggered it. Order any already-created windows to front.
    func applicationWillBecomeActive(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST") else { return }
        NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST") else { return }
        // If SwiftUI hasn't created a window yet, simulate a dock-click reopen.
        // NSApp.delegate is SwiftUI's internal scene delegate; calling
        // applicationShouldHandleReopen on it triggers its window-creation path
        // (the same path that fires when the user clicks the dock icon).
        if !NSApp.windows.contains(where: { $0.isVisible }) {
            _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
        }
        NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }

    /// Called by SwiftUI's delegate in response to the reopen event above (or
    /// to any dock-icon click). Returning true when there are no visible windows
    /// tells SwiftUI to create a new window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST") else { return false }
        return !hasVisibleWindows
    }
}
#endif
