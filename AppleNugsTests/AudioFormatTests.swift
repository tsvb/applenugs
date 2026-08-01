import XCTest

final class AudioFormatTests: XCTestCase {

    func testLosslessFormatsAreLossless() {
        XCTAssertTrue(AudioFormat.flac16.isLossless)
        XCTAssertTrue(AudioFormat.alac16.isLossless)
        XCTAssertTrue(AudioFormat.mqa24.isLossless)
    }

    func testLossyAndUnknownFormatsAreNotLossless() {
        XCTAssertFalse(AudioFormat.aac150.isLossless)
        XCTAssertFalse(AudioFormat.hls.isLossless)
        XCTAssertFalse(AudioFormat.s360ra.isLossless)
        XCTAssertFalse(AudioFormat.unknown.isLossless)
    }

    /// `unknown` is the fallback `identify(_:)` returns for an unrecognised URL.
    /// Claiming lossless there would light the badge for a stream we cannot
    /// vouch for, so the pessimistic answer is the correct one.
    func testUnknownIsPessimistic() {
        XCTAssertFalse(AudioFormat.identify("https://example.com/no/idea").isLossless)
    }

    /// A tripwire, not a redundant assertion.
    ///
    /// `isLossless` and `impliedBitDepth != nil` happen to select the same three
    /// cases today, which is why `isLossless` was tempting to write as a delegate
    /// to the latter. It deliberately isn't: one asks "is this compressed without
    /// loss", the other "does the tier tell us a bit depth", and those are
    /// independent facts that could diverge (a lossless format whose depth varies
    /// would be lossless with no implied depth).
    ///
    /// If this test fails, the two have diverged. That may be entirely correct —
    /// update the expectation deliberately rather than "fixing" either property
    /// to match the other.
    func testLosslessCurrentlyCoincidesWithImpliedBitDepth() {
        let formats: [AudioFormat] = [.unknown, .alac16, .flac16, .mqa24, .s360ra, .aac150, .hls]
        for format in formats {
            XCTAssertEqual(format.isLossless, format.impliedBitDepth != nil,
                           "\(format.rawValue): isLossless and impliedBitDepth disagree")
        }
    }
}
