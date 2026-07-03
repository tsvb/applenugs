import AVKit
import SwiftUI

/// iOS counterpart of the Mac AVPlayerView wrapper: native transport,
/// fullscreen, AirPlay, and PiP via AVPlayerViewController. Same call
/// signature as the macOS VideoPlayerSurface so VideoDetailView stays shared.
///
/// Orientation contract (the YouTube pattern): the app itself is locked to
/// portrait (see OrientationGate); entering video fullscreen opens the gate
/// so the presentation can rotate to landscape, and exiting closes it and
/// snaps the interface back to portrait. The delegate also keeps playback
/// running across the exit transition — AVKit pauses it by default.
struct VideoPlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.delegate = context.coordinator
        vc.allowsPictureInPicturePlayback = true
        // Concert videos keep playing in PiP when the user swipes home,
        // matching how the audio side keeps playing in the background.
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        // A finished video shouldn't strand the user in a black fullscreen.
        vc.exitsFullScreenWhenPlaybackEnds = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }

    // @preconcurrency: the delegate protocol predates actor annotations;
    // AVKit delivers these callbacks on the main thread, and the runtime
    // check enforces it.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator
            coordinator: any UIViewControllerTransitionCoordinator
        ) {
            OrientationGate.videoFullscreen = true
            playerViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator
            coordinator: any UIViewControllerTransitionCoordinator
        ) {
            OrientationGate.videoFullscreen = false
            // AVKit pauses on exit-fullscreen by default; if the video was
            // playing, keep it playing inline after the transition settles.
            let player = playerViewController.player
            let wasPlaying = (player?.rate ?? 0) > 0
            coordinator.animate(alongsideTransition: nil) { _ in
                MainActor.assumeIsolated {
                    if wasPlaying { player?.play() }
                    // Snap the interface back to the app's portrait world.
                    let scene = playerViewController.view.window?.windowScene
                        ?? UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }.first
                    scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                    playerViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }
}

/// App-level orientation policy: the browse/player UI is portrait-only on
/// iPhone (it was never designed for landscape), while fullscreen video may
/// rotate. UIKit consults this on every orientation decision.
final class OrientationGate: NSObject, UIApplicationDelegate {
    @MainActor static var videoFullscreen = false

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        OrientationGate.videoFullscreen ? .allButUpsideDown : .portrait
    }
}
