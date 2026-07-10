import SwiftUI

/// The transport's tactile vocabulary. Three feelings, used everywhere, so a
/// tap means the same thing whichever surface it lands on — the docked bar,
/// the full-screen player, the faceplate, the Click Wheel.
extension SensoryFeedback {
    /// Play/pause: the one press that commits to something.
    static let transportToggle = SensoryFeedback.impact(weight: .medium, intensity: 0.9)

    /// Skip, seek, wheel ticks: a step along the queue, not a decision.
    static let transportStep = SensoryFeedback.selection

    /// A machined button bottoming out under the finger.
    static let machinedPress = SensoryFeedback.impact(weight: .heavy, intensity: 0.8)
}

/// A `Button` that answers the press with a haptic.
///
/// `.sensoryFeedback` needs a trigger value that changes across the press, so
/// the counter has to live in a view that outlives the tap — which is why this
/// is a wrapper and not a modifier you hang on an existing `Button`.
///
/// Everything you'd apply to a `Button` still works from the outside:
/// `.buttonStyle` and `.disabled` reach the inner button through the
/// environment, and a disabled button never runs its action, so it never
/// bumps the counter and never fires.
///
/// A no-op on Macs without a haptic trackpad, and it honors the system
/// Haptics setting on both platforms.
struct HapticButton<Label: View>: View {
    private let feedback: SensoryFeedback
    private let action: () -> Void
    private let label: () -> Label

    @State private var presses = 0

    init(_ feedback: SensoryFeedback,
         action: @escaping () -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.feedback = feedback
        self.action = action
        self.label = label
    }

    var body: some View {
        Button {
            presses &+= 1
            action()
        } label: {
            label()
        }
        .sensoryFeedback(feedback, trigger: presses)
    }
}
