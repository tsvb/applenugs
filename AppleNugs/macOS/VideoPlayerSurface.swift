import AVKit
import SwiftUI

/// Draws a `VideoPlayerService`'s `AVPlayer` using AppKit's `AVPlayerView`,
/// which supplies the native scrubber, volume, fullscreen, AirPlay, and (free)
/// Picture-in-Picture. The audio queue is never drawn here — only video has a
/// surface. The SwiftUI side binds `service.player`; all transport is the
/// service's, surfaced through this view's native controls.
struct VideoPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
