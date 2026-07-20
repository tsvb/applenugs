import SwiftUI
import UIKit

/// Hardware-keyboard shortcuts for iPad — the iOS counterpart to
/// `macOS/KeyboardShortcuts`. A first-responder `UIViewController` (placed in the
/// window via `KeyCommandsHost`) declares `UIKeyCommand`s and dispatches to the
/// shared player/UI. Transport keys register only while a track is loaded, so
/// `Space`/arrows keep their default behavior when nothing plays; a focused text
/// field takes first responder while editing, so typing is never hijacked, and
/// the host reclaims first responder once editing ends.
struct KeyCommandsHost: UIViewControllerRepresentable {
    let app: AppModel
    let ui: UIState

    func makeUIViewController(context: Context) -> KeyCommandsController {
        let vc = KeyCommandsController()
        vc.onSearch    = { [ui] in ui.requestSearchFocus() }
        vc.onPlayPause = { [app] in app.player.togglePlayPause() }
        vc.onNext      = { [app] in app.player.next() }
        vc.onPrevious  = { [app] in app.player.previous() }
        vc.onSeekBy    = { [app] delta in app.player.seek(by: delta) }
        vc.onRestart   = { [app] in app.player.seek(to: 0) }
        vc.onDecile    = { [app] n in
            if app.player.duration > 0 {
                app.player.seek(to: app.player.duration * Double(n) / 10)
            }
        }
        return vc
    }

    func updateUIViewController(_ vc: KeyCommandsController, context: Context) {
        // Re-query trigger only — never re-grabs first responder here (that would
        // steal focus from an actively-editing text field on the 4Hz playback tick).
        vc.hasCurrent = app.player.current != nil
    }
}

final class KeyCommandsController: UIViewController {
    var onSearch:    () -> Void = {}
    var onPlayPause: () -> Void = {}
    var onNext:      () -> Void = {}
    var onPrevious:  () -> Void = {}
    var onSeekBy:    (Double) -> Void = { _ in }
    var onRestart:   () -> Void = {}
    var onDecile:    (Int) -> Void = { _ in }

    /// Whether a track is loaded — transport keys register only then.
    var hasCurrent = false

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        // Reclaim key focus after a text field (Search / filters / login) ends
        // editing — otherwise shortcuts stay dead once a field has stolen it.
        for name in [UITextField.textDidEndEditingNotification,
                     UITextView.textDidEndEditingNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(reclaimFocus), name: name, object: nil)
        }
    }

    @objc private func reclaimFocus() {
        // Async so we don't race the field's own resignFirstResponder.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isFirstResponder else { return }
            self.becomeFirstResponder()
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        var cmds = [command("/", #selector(doSearch))]   // always available
        guard hasCurrent else { return cmds }            // transport only when playing
        cmds += [
            command(" ", #selector(doPlayPause)),
            command(UIKeyCommand.inputLeftArrow,  #selector(doSeekBack)),
            command(UIKeyCommand.inputRightArrow, #selector(doSeekForward)),
            command(UIKeyCommand.inputLeftArrow,  #selector(doSeekBackFar),    modifiers: .shift),
            command(UIKeyCommand.inputRightArrow, #selector(doSeekForwardFar), modifiers: .shift),
            command("n", #selector(doNext)),
            command("p", #selector(doPrevious)),
            command("0", #selector(doRestart)),
        ]
        for n in 1...9 { cmds.append(command("\(n)", #selector(doDecile(_:)))) }
        return cmds
    }

    private func command(_ input: String, _ action: Selector,
                         modifiers: UIKeyModifierFlags = []) -> UIKeyCommand {
        let c = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
        c.wantsPriorityOverSystemBehavior = true
        return c
    }

    @objc private func doSearch()         { onSearch() }
    @objc private func doPlayPause()      { onPlayPause() }
    @objc private func doNext()           { onNext() }
    @objc private func doPrevious()       { onPrevious() }
    @objc private func doSeekBack()       { onSeekBy(-10) }
    @objc private func doSeekForward()    { onSeekBy(10) }
    @objc private func doSeekBackFar()    { onSeekBy(-30) }
    @objc private func doSeekForwardFar() { onSeekBy(30) }
    @objc private func doRestart()        { onRestart() }
    @objc private func doDecile(_ sender: UIKeyCommand) {
        if let s = sender.input, let n = Int(s) { onDecile(n) }
    }
}
