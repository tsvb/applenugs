import Foundation

/// The inspector's "Signal" rows, as pure data.
///
/// This exists so the section can hold a CONSTANT shape while a track loads.
/// `PlayerService.startCurrent()` nils `nowPick` and `specs` and zeroes
/// `bufferedAhead` on every track change; the pick comes back once the stream
/// resolves and the specs only once AVFoundation has read the asset's format
/// descriptions. Previously each of those was a separate `if let` in the view,
/// so the section collapsed from six rows to two — and the whole queue below it
/// jumped — on every click in the Up Next list.
///
/// The invariant this type enforces, and that `SignalReadoutTests` pins: for
/// ANY combination of nil / present / zero inputs, `rows(...)` returns the same
/// `rowCount` rows in the same `Kind` order. Unknown values degrade to
/// `unknown`; a row never disappears. Height then falls out of the row count
/// and the theme's own fonts, so it is automatically right in all five themes
/// and under iOS Dynamic Type — no reserved heights, no magic numbers.
///
/// Deliberately Foundation-only (no SwiftUI, no AVFoundation) and taking loose
/// primitives rather than `PlayerService.AudioSpecs`, so it compiles straight
/// into the host-free `AppleNugsTests` target.
enum SignalReadout {

    /// The one placeholder for every unknown scalar. Matches the em-dash the
    /// rest of the app already uses for "no value yet" (FaceplateTransport,
    /// ClickWheelScreen, TouchFaceplate, CrateItem); `--:--` stays reserved for
    /// clocks.
    static let unknown = "—"

    /// Row identity. The `ForEach` keys on this rather than on the label,
    /// because the second row's LABEL legitimately changes ("Platform tier" for
    /// a stream, "Source" for a downloaded file) — keying on the label would
    /// make that swap a remove-and-insert instead of a value update.
    enum Kind: Hashable {
        case format, source, sampleRate, bitDepth, channels
    }

    struct Row: Identifiable, Equatable {
        let kind: Kind
        let label: String
        let value: String

        var id: Kind { kind }

        /// Drives the dimmed treatment in the view. Dimming must be a
        /// foreground-color change ONLY — any font or weight change would move
        /// the row height and reintroduce the very bug this type prevents.
        var isUnknown: Bool { value == SignalReadout.unknown }
    }

    /// Rows always returned by `rows(...)`. `Buffered` is not included: it is
    /// rendered by a separate leaf view so the ~4Hz `bufferedAhead` dependency
    /// stays off the panel body.
    static let rowCount = 5

    static func rows(format: AudioFormat?,
                     platformId: Int?,
                     sampleRate: Double?,
                     bitDepth: Int?,
                     channels: Int?) -> [Row] {
        [
            Row(kind: .format, label: "Format",
                value: format?.qualityLabel ?? unknown),
            sourceRow(platformId: platformId),
            Row(kind: .sampleRate, label: "Sample rate",
                value: sampleRateValue(sampleRate)),
            Row(kind: .bitDepth, label: "Bit depth",
                value: bitDepthValue(bitDepth)),
            Row(kind: .channels, label: "Channels",
                value: channelsValue(channels)),
        ]
    }

    // MARK: - fields

    /// `platformId` 0 is the local-file sentinel, not a tier.
    ///
    /// The unknown case takes the "Platform tier" label rather than inventing a
    /// third one, and that is safe rather than a guess: `startCurrent()` only
    /// leaves the pick nil on the NETWORK path — the downloaded-file branch
    /// calls `loadCurrentPick()` synchronously, so a local track never has an
    /// observable unknown window. So the unknown state always resolves to a
    /// tier, and only the value changes ("—" → "7"). The label never flips
    /// under the user.
    private static func sourceRow(platformId: Int?) -> Row {
        guard let platformId else {
            return Row(kind: .source, label: "Platform tier", value: unknown)
        }
        return platformId > 0
            ? Row(kind: .source, label: "Platform tier", value: String(platformId))
            : Row(kind: .source, label: "Source", value: "Downloaded file")
    }

    private static func sampleRateValue(_ hz: Double?) -> String {
        guard let hz, hz > 0, hz.isFinite else { return unknown }
        return String(format: "%.1f kHz", hz / 1000)
    }

    /// `nil` and `<= 0` collapse to the same placeholder on purpose. A depth of
    /// 0 is what a decoder reports for a compressed stream, and
    /// `AudioFormat.impliedBitDepth` is legitimately nil forever for AAC / HLS /
    /// 360RA — so "not known yet" and "not applicable" share one token. A
    /// separate "n/a" would itself flip to a different string the moment specs
    /// landed, which is the flicker this whole type exists to remove; the Format
    /// row directly above already names the codec.
    private static func bitDepthValue(_ bits: Int?) -> String {
        guard let bits, bits > 0 else { return unknown }
        return "\(bits)-bit"
    }

    private static func channelsValue(_ channels: Int?) -> String {
        guard let channels, channels > 0 else { return unknown }
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        default: return String(channels)
        }
    }

    // MARK: - buffered (rendered by a leaf view, hence separate)

    static let bufferedLabel = "Buffered"

    /// Zero is not only "not measured yet" — `PlayerService.tick()` computes the
    /// loaded range CONTAINING the playhead, so it also reads 0 at the end of a
    /// track and whenever the playhead sits outside every loaded range. Hence a
    /// neutral placeholder rather than "0 s ahead".
    static func buffered(secondsAhead: Double) -> String {
        guard secondsAhead > 0, secondsAhead.isFinite else { return unknown }
        return String(format: "%.0f s ahead", secondsAhead)
    }
}
