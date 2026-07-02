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
    var cgImageForAnalysis: CGImage? {
        #if os(macOS)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
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
