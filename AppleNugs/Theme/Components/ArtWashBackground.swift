import SwiftUI

/// The album-art color wash behind a region. The look varies by theme:
/// a leading gradient (Soundboard), a faint full wash (Shoebox), or a soft
/// bloom (The Receiver). Animates as the color changes between tracks.
struct ArtWashBackground: View {
    let style: WashStyle
    let color: Color

    var body: some View {
        Group {
            switch style {
            case .none:
                Color.clear
            case .linear:
                LinearGradient(
                    colors: [color.opacity(0.45), .clear],
                    startPoint: .leading, endPoint: .trailing)
            case .warmLow:
                color.opacity(0.10)
            case .bloom18:
                RadialGradient(
                    colors: [color.opacity(0.18), .clear],
                    center: .center, startRadius: 0, endRadius: 180)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.4), value: color)
    }
}
