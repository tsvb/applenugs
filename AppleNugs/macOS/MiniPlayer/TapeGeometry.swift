import Foundation

/// Geometry for Tape Room's cassette reels.
///
/// Foundation-only on purpose: this file is compiled directly into the
/// host-free `AppleNugsTests` bundle (see `project.yml`), which admits no
/// SwiftUI. Callers convert to `CGFloat` at the use site.
enum TapeGeometry {

    /// Radius of a tape pack holding `fraction` (0...1) of the reel's tape.
    ///
    /// Tape winds in a flat spiral, so the pack's *area* — not its radius — is
    /// proportional to the length of tape on the reel. The radius therefore
    /// goes as the square root, which is why a real reel visibly slows its
    /// growth as it fills. A linear interpolation looks wrong in motion.
    static func packRadius(fraction: Double, hub: Double, full: Double) -> Double {
        let f = clampUnit(fraction)
        return (hub * hub + (full * full - hub * hub) * f).squareRoot()
    }

    /// Playback position as a 0...1 fraction. Zero unless both inputs are
    /// finite and the duration is positive — `duration` is 0 before a track
    /// loads and can be NaN for a stream that never reports one.
    static func progress(currentTime: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return 0 }
        return clampUnit(currentTime / duration)
    }

    private static func clampUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
