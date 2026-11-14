import AppKit

/// Playback ▸ Clear Queue's confirmation, asked with AppKit straight from the
/// menu command.
///
/// A `Commands` builder has no view to present a SwiftUI dialog from, and
/// routing it through one window's root broke whenever that window wasn't the
/// one in front: with only the Now Playing window open nothing appeared (and
/// the dialog popped up unprompted once the main window came back), a
/// minimized or backgrounded main window took the sheet out of sight, two main
/// windows each presented one, and a window already showing a sheet collided
/// with it. So: a sheet on the key window when it can take one, otherwise an
/// app-modal alert. Same words as the in-window dialog (`ClearQueueCopy`).
@MainActor
enum ClearQueueAlert {
    /// One question at a time: a second Clear Queue while the first alert is
    /// up would otherwise stack a second alert behind it.
    private static var isPresenting = false

    static func present(onConfirm: @escaping @MainActor () -> Void) {
        guard !isPresenting else { return }
        isPresenting = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ClearQueueCopy.title
        alert.informativeText = ClearQueueCopy.message
        alert.addButton(withTitle: ClearQueueCopy.confirm).hasDestructiveAction = true
        // A second button titled "Cancel" gets Escape from AppKit.
        alert.addButton(withTitle: ClearQueueCopy.cancel)

        if let window = sheetHost() {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated {
                    finish(response, onConfirm: onConfirm)
                }
            }
        } else {
            finish(alert.runModal(), onConfirm: onConfirm)
        }
    }

    private static func finish(_ response: NSApplication.ModalResponse,
                               onConfirm: @MainActor () -> Void) {
        isPresenting = false
        if response == .alertFirstButtonReturn { onConfirm() }
    }

    /// The window to attach the sheet to: the key window (else the main one)
    /// if it's an ordinary on-screen window with no sheet of its own. A panel
    /// (About, Sparkle), a sheet, or a window already showing one gets an
    /// app-modal alert instead.
    private static func sheetHost() -> NSWindow? {
        let candidates = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
        return candidates.first { window in
            window.canBecomeMain
                && !window.isSheet
                && window.attachedSheet == nil
                && window.isVisible
                && !window.isMiniaturized
        }
    }
}
