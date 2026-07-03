import SwiftUI

#if os(macOS)
import AppKit
/// The native bitmap image type for the current platform. Shared code that
/// carries artwork uses this so only the initializer sites differ per OS.
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension PlatformImage {
    /// A CGImage suitable for one-shot pixel analysis (dominant color).
    /// The macOS branch keeps the TIFF round-trip the original extractor
    /// used, so the bytes fed to the color math are identical to pre-port
    /// builds (a direct cgImage(forProposedRect:) can decode ±1 LSB apart).
    var cgImageForAnalysis: CGImage? {
        #if os(macOS)
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
        #else
        return cgImage
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
