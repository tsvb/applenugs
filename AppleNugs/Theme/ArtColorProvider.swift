import AppKit
import CoreImage
import Observation
import SwiftUI

/// Extracts a clamped, legible accent color from the now-playing cover art for
/// the themes that want it (Soundboard, The Receiver). Runs off the main actor,
/// caches per artwork path, and is never invoked for static-accent themes.
@MainActor
@Observable
final class ArtColorProvider {
    private(set) var color: Color?

    private var cache: [String: Color] = [:]
    private var task: Task<Void, Never>?

    nonisolated static let fallback = Color(hex: 0xE0902E)

    /// Resolve the color for the current art. `enabled` is the active theme's
    /// `consumesArtColor`, so static themes pay nothing.
    func update(image: NSImage?, key: String?, enabled: Bool) {
        task?.cancel()
        guard enabled else {
            set(nil)
            return
        }
        guard let key, let image else {
            set(Self.fallback)
            return
        }
        if let cached = cache[key] {
            set(cached)
            return
        }
        task = Task.detached(priority: .utility) {
            let resolved = ArtColorProvider.dominantColor(of: image) ?? Self.fallback
            await MainActor.run { [weak self] in
                self?.cache[key] = resolved
                self?.set(resolved)
            }
        }
    }

    private func set(_ newColor: Color?) {
        withAnimation(.easeInOut(duration: 0.4)) { color = newColor }
    }

    // --- extraction (nonisolated; runs on a background task) ----------------

    nonisolated private static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    nonisolated private static func dominantColor(of image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return nil }

        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ]), let output = filter.outputImage else { return nil }

        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output, toBitmap: &px, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)

        let raw = NSColor(
            srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
            blue: CGFloat(px[2]) / 255, alpha: 1)
        guard let dev = raw.usingColorSpace(.deviceRGB) else { return nil }

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        dev.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Clamp so a muddy or dark cover still yields a legible, lively tint.
        let clampedS = max(s, 0.5)
        let clampedB = min(max(b, 0.5), 0.66)
        return Color(hue: Double(h), saturation: Double(clampedS), brightness: Double(clampedB))
    }
}
