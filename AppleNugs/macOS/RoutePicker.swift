import SwiftUI
import AVKit

/// System audio-output routing (AirPlay) for the Mac transport bar. The macOS
/// AVRoutePickerView is an NSView that colors its button per-state, rather than
/// via the single `tintColor` the iOS view uses. API-compatible call shape with
/// the iOS `RoutePicker` so both transports read the same at the call site.
struct RoutePicker: NSViewRepresentable {
    let tint: Color

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        apply(tint, to: view)
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        apply(tint, to: view)
    }

    private func apply(_ tint: Color, to view: AVRoutePickerView) {
        let color = NSColor(tint)
        view.setRoutePickerButtonColor(color, for: .normal)
        view.setRoutePickerButtonColor(color, for: .active)
    }
}
