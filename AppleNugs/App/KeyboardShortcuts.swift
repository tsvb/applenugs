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

        // Arrow-key seek (bare = ±10s, Shift = ±30s). cmd-ctrl-arrows already
        // own whole-track prev/next and are excluded by the guard above.
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123:  // left arrow
            app.player.seek(by: shift ? -30 : -10)
            return nil
        case 124:  // right arrow
            app.player.seek(by: shift ? 30 : 10)
            return nil
        default:
            break
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
        case "0":
            app.player.seek(to: 0)
            return nil
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            if let n = event.charactersIgnoringModifiers.flatMap(Int.init), app.player.duration > 0 {
                app.player.seek(to: app.player.duration * Double(n) / 10)
            }
            return nil
        default:
            return event
        }
    }
}
