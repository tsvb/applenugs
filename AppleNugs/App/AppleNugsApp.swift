import SwiftUI

@main
struct AppleNugsApp: App {
    @State private var app = AppModel()
    @State private var ui = UIState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(ui)
                .frame(minWidth: 960, minHeight: 560)
        }
        .defaultSize(width: 1220, height: 760)
        .commands {
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
