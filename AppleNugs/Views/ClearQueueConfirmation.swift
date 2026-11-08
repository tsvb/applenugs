import SwiftUI

/// The one question every clear-queue path asks (Tim's ruling P2): the
/// now-playing ⋯ menu, the dashboard's "Clear", and Playback ▸ Clear Queue on
/// the Mac. One modifier so the three can't drift apart. The message says what
/// `PlayerService.clear()` does: it stops playback and empties the queue.
extension View {
    func clearQueueConfirmation(isPresented: Binding<Bool>,
                                onConfirm: @escaping () -> Void) -> some View {
        confirmationDialog("Clear the queue?", isPresented: isPresented,
                           titleVisibility: .visible) {
            Button("Clear Queue", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Playback stops and the whole queue empties.")
        }
    }
}
