import XCTest

final class SignalReadoutTests: XCTestCase {

    private let allFormats: [AudioFormat] =
        [.unknown, .alac16, .flac16, .mqa24, .s360ra, .aac150, .hls]

    // MARK: - the invariant this type exists for

    /// The regression test for the reported bug: the inspector's Signal section
    /// used to drop from six rows to two while a track loaded, jumping the whole
    /// Up Next list below it. No combination of missing inputs may remove a row
    /// or reorder one.
    func testRowShapeIsConstantAcrossEveryCombinationOfMissingInputs() {
        let expected: [SignalReadout.Kind] = [.format, .source, .sampleRate, .bitDepth, .channels]

        let formats: [AudioFormat?] = [nil, .alac16, .aac150]
        let platforms: [Int?] = [nil, 0, 7]
        let rates: [Double?] = [nil, 0, -1, .nan, .infinity, 44_100]
        let depths: [Int?] = [nil, 0, -1, 16]
        let channelCounts: [Int?] = [nil, 0, -1, 1, 2, 6]

        for format in formats {
            for platformId in platforms {
                for rate in rates {
                    for depth in depths {
                        for channels in channelCounts {
                            let rows = SignalReadout.rows(format: format, platformId: platformId,
                                                          sampleRate: rate, bitDepth: depth,
                                                          channels: channels)
                            let context = "format=\(String(describing: format)) "
                                + "platform=\(String(describing: platformId)) "
                                + "rate=\(String(describing: rate)) "
                                + "depth=\(String(describing: depth)) "
                                + "channels=\(String(describing: channels))"
                            XCTAssertEqual(rows.count, SignalReadout.rowCount, context)
                            XCTAssertEqual(rows.map(\.kind), expected, context)
                            XCTAssertFalse(rows.contains { $0.label.isEmpty }, context)
                            XCTAssertFalse(rows.contains { $0.value.isEmpty }, context)
                        }
                    }
                }
            }
        }
    }

    /// Nothing known at all — the exact state the panel is in for the few
    /// hundred milliseconds after a track is clicked, and the state a
    /// launch-restored queue sits in indefinitely until first play.
    func testEverythingUnknownStillYieldsAFullRowSet() {
        let rows = SignalReadout.rows(format: nil, platformId: nil, sampleRate: nil,
                                      bitDepth: nil, channels: nil)
        XCTAssertEqual(rows.count, SignalReadout.rowCount)
        XCTAssertTrue(rows.allSatisfy(\.isUnknown))
        XCTAssertTrue(rows.allSatisfy { $0.value == SignalReadout.unknown })
    }

    // MARK: - format

    func testFormatUsesTheQualityLabelAndFallsBackToThePlaceholder() {
        for format in allFormats {
            let row = self.row(.format, format: format)
            XCTAssertEqual(row.value, format.qualityLabel, format.rawValue)
            XCTAssertFalse(row.isUnknown, format.rawValue)
        }
        XCTAssertEqual(row(.format, format: nil).value, SignalReadout.unknown)
    }

    // MARK: - source / platform tier

    /// The label must not flip under the user while a track loads. It cannot:
    /// the unknown case only ever occurs on the network path (the downloaded
    /// branch resolves its pick synchronously), and that path always resolves to
    /// a tier — so the unknown state and the resolved state share a label and
    /// only the value changes.
    func testSourceRowKeepsThePlatformTierLabelWhileUnknown() {
        let unknown = row(.source, platformId: nil)
        XCTAssertEqual(unknown.label, "Platform tier")
        XCTAssertEqual(unknown.value, SignalReadout.unknown)

        let resolved = row(.source, platformId: 7)
        XCTAssertEqual(resolved.label, "Platform tier")
        XCTAssertEqual(resolved.value, "7")
        XCTAssertFalse(resolved.isUnknown)
    }

    /// platformId 0 is the local-file sentinel, not a tier.
    func testSourceRowNamesADownloadedFile() {
        let local = row(.source, platformId: 0)
        XCTAssertEqual(local.label, "Source")
        XCTAssertEqual(local.value, "Downloaded file")
        XCTAssertFalse(local.isUnknown)
    }

    /// The row's identity is its `Kind`, not its label — otherwise the
    /// "Platform tier" ↔ "Source" swap would read as a remove-and-insert to
    /// SwiftUI rather than a value change.
    func testSourceRowIdentitySurvivesTheLabelSwap() {
        XCTAssertEqual(row(.source, platformId: nil).id, row(.source, platformId: 0).id)
    }

    // MARK: - sample rate

    func testSampleRateFormatting() {
        XCTAssertEqual(row(.sampleRate, sampleRate: 44_100).value, "44.1 kHz")
        XCTAssertEqual(row(.sampleRate, sampleRate: 96_000).value, "96.0 kHz")
    }

    func testSampleRatePlaceholders() {
        for bad: Double? in [nil, 0, -1, .nan, .infinity] {
            XCTAssertEqual(row(.sampleRate, sampleRate: bad).value, SignalReadout.unknown,
                           String(describing: bad))
        }
    }

    // MARK: - bit depth

    func testBitDepthFormatting() {
        XCTAssertEqual(row(.bitDepth, bitDepth: 16).value, "16-bit")
        XCTAssertEqual(row(.bitDepth, bitDepth: 24).value, "24-bit")
    }

    /// A decoder reports 0 bits per channel for a compressed stream. That must
    /// never render as "0-bit" — see `AudioFormatTests.testImpliedBitDepthIsNil…`,
    /// which pins the same rule one layer down.
    func testBitDepthPlaceholders() {
        for bad: Int? in [nil, 0, -1] {
            XCTAssertEqual(row(.bitDepth, bitDepth: bad).value, SignalReadout.unknown,
                           String(describing: bad))
        }
    }

    // MARK: - channels

    func testChannelNaming() {
        XCTAssertEqual(row(.channels, channels: 1).value, "Mono")
        XCTAssertEqual(row(.channels, channels: 2).value, "Stereo")
        XCTAssertEqual(row(.channels, channels: 6).value, "6")
    }

    func testChannelPlaceholders() {
        for bad: Int? in [nil, 0, -1] {
            XCTAssertEqual(row(.channels, channels: bad).value, SignalReadout.unknown,
                           String(describing: bad))
        }
    }

    // MARK: - buffered

    func testBufferedFormatting() {
        XCTAssertEqual(SignalReadout.buffered(secondsAhead: 12.4), "12 s ahead")
        XCTAssertEqual(SignalReadout.buffered(secondsAhead: 1248), "1248 s ahead")
    }

    /// Zero is not only "not measured yet": `tick()` computes the loaded range
    /// containing the playhead, so it also reads 0 at the end of a track. A
    /// neutral placeholder is correct for both.
    func testBufferedPlaceholders() {
        XCTAssertEqual(SignalReadout.buffered(secondsAhead: 0), SignalReadout.unknown)
        XCTAssertEqual(SignalReadout.buffered(secondsAhead: -1), SignalReadout.unknown)
        XCTAssertEqual(SignalReadout.buffered(secondsAhead: .nan), SignalReadout.unknown)
        XCTAssertEqual(SignalReadout.buffered(secondsAhead: .infinity), SignalReadout.unknown)
    }

    // MARK: - helper

    private func row(_ kind: SignalReadout.Kind,
                     format: AudioFormat? = .alac16,
                     platformId: Int? = 7,
                     sampleRate: Double? = 44_100,
                     bitDepth: Int? = 16,
                     channels: Int? = 2) -> SignalReadout.Row {
        let rows = SignalReadout.rows(format: format, platformId: platformId,
                                      sampleRate: sampleRate, bitDepth: bitDepth,
                                      channels: channels)
        guard let match = rows.first(where: { $0.kind == kind }) else {
            XCTFail("no \(kind) row")
            return SignalReadout.Row(kind: kind, label: "", value: "")
        }
        return match
    }
}
