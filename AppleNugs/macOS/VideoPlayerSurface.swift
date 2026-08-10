import AVKit
import SwiftUI

/// Draws a `VideoPlayerService`'s `AVPlayer` using AppKit's `AVPlayerView`,
/// which supplies the native scrubber, volume, AirPlay, and (free)
/// Picture-in-Picture. The audio queue is never drawn here — only video has a
/// surface. The SwiftUI side binds `service.player`; all transport is the
/// service's, surfaced through this view's native controls.
///
/// Full screen is the one control AVKit does *not* give you for free:
/// `showsFullScreenToggleButton` defaults to false, so the button has to be
/// opted into. It matters here because the inline surface lives in the
/// NavigationSplitView detail column, squeezed between the sidebar, the
/// transport bar, and a 340pt inspector. Once on, the same button enters and
/// exits (it flips to a shrink icon), and Esc exits too — so there's no need
/// for app-drawn chrome, which would anyway have to use the unrelated
/// `NSView.enterFullScreenMode` path since AVPlayerView has no programmatic
/// full-screen entry point.
struct VideoPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
