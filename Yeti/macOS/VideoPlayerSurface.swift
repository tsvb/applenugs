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
/// transport bar, and a 340pt inspector.
///
/// That button is the *only* way in or out: AVPlayerView exposes no method to
/// enter or exit full screen and no property reporting whether it is — just the
/// four `AVPlayerViewDelegate` notifications. Hence no app-drawn chrome (it
/// would need the unrelated `NSView.enterFullScreenMode` path, a second
/// full-screen mechanism AVKit's own state knows nothing about), and hence the
/// delegate below rather than a direct query.
struct VideoPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    @Environment(AppModel.self) private var app

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        context.coordinator.video = app.video
        view.player = player
        view.delegate = context.coordinator
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.video = app.video
        if nsView.player !== player {
            nsView.player = player
        }
    }

    /// Reports AVKit's full-screen transitions to the service, which defers the
    /// end-of-playback arbiter hand-back while full screen — otherwise a video
    /// that finishes there resumes the audio queue behind a window the viewer
    /// can't see past. iOS needs no equivalent: `AVPlayerViewController` leaves
    /// full screen on its own via `exitsFullScreenWhenPlaybackEnds`.
    ///
    /// @preconcurrency: the delegate protocol predates actor annotations; AVKit
    /// delivers these callbacks on the main thread, and the runtime check
    /// enforces it. Mirrors the iOS surface's coordinator.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewDelegate {
        weak var video: VideoPlayerService?

        func playerViewDidEnterFullScreen(_ playerView: AVPlayerView) {
            video?.setFullScreen(true)
        }

        func playerViewDidExitFullScreen(_ playerView: AVPlayerView) {
            video?.setFullScreen(false)
        }
    }
}
