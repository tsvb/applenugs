import Darwin
import XCTest

final class MemoryFootprintTests: XCTestCase {

    func testFormatUsesBinaryUnitsWithADotDecimal() {
        XCTAssertEqual(MemoryFootprint.format(bytes: 0), "0.0 MB")
        XCTAssertEqual(MemoryFootprint.format(bytes: 1_048_576), "1.0 MB")
        XCTAssertEqual(MemoryFootprint.format(bytes: 19_293_798), "18.4 MB")
        // At 100 MB and up a decimal is noise.
        XCTAssertEqual(MemoryFootprint.format(bytes: 140_509_184), "134 MB")
        XCTAssertEqual(MemoryFootprint.format(bytes: 1_342_177_280), "1.25 GB")
    }

    func testSampleReadsThisProcess() throws {
        let sample = try XCTUnwrap(MemoryFootprint.sample())
        XCTAssertGreaterThan(sample.current, 0)
        XCTAssertGreaterThanOrEqual(sample.peak, sample.current)
    }

    /// The point of using the kernel's ledger peak instead of a sampler: it
    /// keeps the high-water mark after the memory is gone.
    func testPeakSurvivesTheMemoryBeingReleased() throws {
        let size = 64 << 20
        let before = try XCTUnwrap(MemoryFootprint.sample())
        let region = try XCTUnwrap(mmap(nil, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0))
        XCTAssertNotEqual(region, MAP_FAILED)
        memset(region, 1, size)
        let holding = try XCTUnwrap(MemoryFootprint.sample())
        munmap(region, size)
        let after = try XCTUnwrap(MemoryFootprint.sample())
        XCTAssertGreaterThan(holding.current, before.current + UInt64(size) / 2)
        XCTAssertLessThan(after.current, holding.current - UInt64(size) / 2)
        XCTAssertGreaterThanOrEqual(after.peak, holding.current)
    }
}
