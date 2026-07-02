import AVKit
import SwiftUI

/// iOS counterpart of the Mac AVPlayerView wrapper: native transport,
/// fullscreen, AirPlay, and PiP via AVPlayerViewController. Same call
/// signature as the macOS VideoPlayerSurface so VideoDetailView stays shared.
struct VideoPlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        // Concert videos keep playing in PiP when the user swipes home,
        // matching how the audio side keeps playing in the background.
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
