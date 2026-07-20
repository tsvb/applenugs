import SwiftUI
import AVKit

/// System output routing (AirPlay, headphones, HomePod). The view manages its
/// own popover; we only theme its tint.
struct RoutePicker: UIViewRepresentable {
    let tint: Color

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(tint)
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(tint)
    }
}
