import SwiftUI

/// The one question every clear-queue path asks (Tim's ruling P2): the
/// now-playing ⋯ menu, the dashboard's "Clear", and Playback ▸ Clear Queue on
/// the Mac. The words live here so the SwiftUI dialog below and the Mac menu's
/// AppKit alert (`ClearQueueAlert`) can't drift apart. The message says what
/// `PlayerService.clear()` does: it stops playback and empties the queue.
enum ClearQueueCopy {
    static let title = "Clear the queue?"
    static let message = "Playback stops and the whole queue empties."
    static let confirm = "Clear Queue"
    static let cancel = "Cancel"
}

extension View {
    /// The in-window form of the question, for surfaces that own a view to
    /// present from (the dashboard and the now-playing ⋯ menu).
    func clearQueueConfirmation(isPresented: Binding<Bool>,
                                onConfirm: @escaping () -> Void) -> some View {
        confirmationDialog(ClearQueueCopy.title, isPresented: isPresented,
                           titleVisibility: .visible) {
            Button(ClearQueueCopy.confirm, role: .destructive, action: onConfirm)
            Button(ClearQueueCopy.cancel, role: .cancel) {}
        } message: {
            Text(ClearQueueCopy.message)
        }
    }
}
