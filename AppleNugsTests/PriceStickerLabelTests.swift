import XCTest

final class PriceStickerLabelTests: XCTestCase {

    // MARK: - pick unknown: lossless is the honest default

    func testUnknownPickSaysLosslessWithNoSpecLine() throws {
        let label = try XCTUnwrap(PriceStickerLabel(pickKnown: false, isLossless: false,
                                                    bitDepth: nil, sampleRate: nil))
        XCTAssertEqual(label.title, "Lossless")
        XCTAssertNil(label.spec)
        XCTAssertEqual(label.accessibilityLabel, "Lossless")
    }

    /// While the pick is unknown any depth/rate can only be left over from the
    /// previous track, and `isLossless` means nothing yet — neither may hide the
    /// sticker or print a spec line.
    func testUnknownPickIgnoresLosslessFlagAndSpecs() throws {
        for isLossless in [false, true] {
            let label = try XCTUnwrap(PriceStickerLabel(pickKnown: false, isLossless: isLossless,
                                                        bitDepth: 24, sampleRate: 96_000))
            XCTAssertEqual(label.title, "Lossless")
            XCTAssertNil(label.spec)
            XCTAssertEqual(label.accessibilityLabel, "Lossless")
        }
    }

    // MARK: - pick known, lossless

    func testKnownLosslessWithSpecsPrintsDepthOverRate() throws {
        let label = try XCTUnwrap(PriceStickerLabel(pickKnown: true, isLossless: true,
                                                    bitDepth: 24, sampleRate: 96_000))
        XCTAssertEqual(label.title, "Lossless")
        XCTAssertEqual(label.spec, "24/96")
        XCTAssertEqual(label.accessibilityLabel, "Lossless, 24-bit 96 kilohertz")
    }

    func testFortyFourPointOnePrintsFortyFourButSpeaksTheTrueRate() throws {
        let label = try XCTUnwrap(PriceStickerLabel(pickKnown: true, isLossless: true,
                                                    bitDepth: 16, sampleRate: 44_100))
        XCTAssertEqual(label.spec, "16/44")
        XCTAssertEqual(label.accessibilityLabel, "Lossless, 16-bit 44.1 kilohertz")
    }

    func testOtherRatesPrintWholeKilohertz() {
        let cases: [(Double, String)] = [
            (48_000, "16/48"), (88_200, "16/88"), (176_400, "16/176"),
            (192_000, "16/192"), (47_999.99, "16/48"),
        ]
        for (hz, expected) in cases {
            XCTAssertEqual(PriceStickerLabel(pickKnown: true, isLossless: true,
                                             bitDepth: 16, sampleRate: hz)?.spec,
                           expected, "\(hz) Hz")
        }
    }

    func testKnownLosslessWithoutBothSpecsHasNoSpecLine() {
        let partials: [(Int?, Double?)] = [
            (nil, nil), (24, nil), (nil, 96_000),
            (0, 96_000), (-1, 96_000), (24, 0), (24, -44_100), (24, .nan), (24, .infinity),
        ]
        for (depth, rate) in partials {
            let label = PriceStickerLabel(pickKnown: true, isLossless: true,
                                          bitDepth: depth, sampleRate: rate)
            let context = "depth=\(String(describing: depth)) rate=\(String(describing: rate))"
            XCTAssertNotNil(label, context)
            XCTAssertEqual(label?.title, "Lossless", context)
            XCTAssertNil(label?.spec, context)
            XCTAssertEqual(label?.accessibilityLabel, "Lossless", context)
        }
    }

    // MARK: - pick known, not lossless: hidden

    func testKnownNonLosslessIsHidden() {
        XCTAssertNil(PriceStickerLabel(pickKnown: true, isLossless: false,
                                       bitDepth: nil, sampleRate: nil))
        XCTAssertNil(PriceStickerLabel(pickKnown: true, isLossless: false,
                                       bitDepth: 16, sampleRate: 44_100))
    }

    /// The real formats, end to end through `AudioFormat.isLossless`.
    func testEveryAudioFormatMapsThroughIsLossless() {
        let formats: [AudioFormat] = [.unknown, .alac16, .flac16, .mqa24, .s360ra, .aac150, .hls]
        for format in formats {
            let label = PriceStickerLabel(pickKnown: true, isLossless: format.isLossless,
                                          bitDepth: format.impliedBitDepth, sampleRate: 44_100)
            XCTAssertEqual(label != nil, format.isLossless, "\(format)")
        }
    }
}
