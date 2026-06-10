import AppKit

/// Window-level key handling, ported from audio-interop.js: space toggles
/// play/pause, n/p skip, "/" focuses search, Esc blurs a focused input.
/// Keys pass through untouched while a text input has focus, so typing in
/// the search box never triggers transport actions.
@MainActor
enum KeyboardShortcuts {
    private static var monitor: Any?

    static func install(app: AppModel, ui: UIState) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, app: app, ui: ui)
        }
    }

    private static func handle(_ event: NSEvent, app: AppModel, ui: UIState) -> NSEvent? {
        let escape: UInt16 = 53

        // A focused field's editor is an NSTextView — let keys do their
        // normal thing there, except Esc which blurs (matches the web port).
        if NSApp.keyWindow?.firstResponder is NSTextView {
            if event.keyCode == escape {
                NSApp.keyWindow?.makeFirstResponder(nil)
                return nil
            }
            return event
        }

        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return event
        }

        switch event.charactersIgnoringModifiers {
        case " ":
            app.player.togglePlayPause()
            return nil
        case "n":
            app.player.next()
            return nil
        case "p":
            app.player.previous()
            return nil
        case "/":
            ui.requestSearchFocus()
            return nil
        default:
            return event
        }
    }
}
