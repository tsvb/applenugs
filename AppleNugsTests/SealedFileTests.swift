import CryptoKit
import XCTest

final class SealedFileTests: XCTestCase {

    private var dir: URL!
    private let key = SymmetricKey(size: .bits256)
    private let chunk = SealedFile.defaultChunkSize

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SealedFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // --- helpers -------------------------------------------------------------------

    /// Deterministic, non-repeating bytes, so a misplaced chunk can't
    /// accidentally compare equal.
    private func plaintext(_ count: Int, seed: UInt64 = 0x9E3779B97F4A7C15) -> Data {
        var state = seed
        var out = Data(count: count)
        for i in 0..<count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            out[i] = UInt8(truncatingIfNeeded: state >> 33)
        }
        return out
    }

    private func sealed(_ data: Data, contentType: String = "org.xiph.flac",
                        file: String = "sealed.yeti") throws -> URL {
        let source = dir.appendingPathComponent("plain-\(UUID().uuidString)")
        try data.write(to: source)
        let dest = dir.appendingPathComponent(file)
        try SealedFile.seal(contentsOf: source, to: dest, key: key, contentType: contentType)
        return dest
    }

    // --- round trips -----------------------------------------------------------------

    func testRoundTripsAcrossChunkBoundarySizes() throws {
        for size in [0, 1, chunk - 1, chunk, chunk + 1, 1_000_003] {
            let plain = plaintext(size, seed: UInt64(size) + 1)
            let url = try sealed(plain, file: "rt-\(size).yeti")
            let reader = try SealedFileReader(url: url, key: key)
            XCTAssertEqual(reader.plaintextLength, Int64(size), "size \(size)")
            XCTAssertEqual(reader.contentType, "org.xiph.flac")
            XCTAssertEqual(try reader.read(offset: 0, length: size), plain, "size \(size)")

            // Exact on-disk size: header + plaintext + one tag per chunk.
            let onDisk = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
            XCTAssertEqual(Int64(onDisk ?? -1), reader.layout.sealedFileLength, "size \(size)")
        }
    }

    func testCiphertextDoesNotContainThePlaintext() throws {
        let plain = Data(repeating: 0x41, count: 3 * chunk)
        let url = try sealed(plain)
        let disk = try Data(contentsOf: url)
        XCTAssertNil(disk.range(of: Data(repeating: 0x41, count: 64)))
        XCTAssertEqual(disk.prefix(4), Data("YETI".utf8))
    }

    func testRandomRangesEqualThePlaintextSlice() throws {
        let size = 1_000_003
        let plain = plaintext(size)
        let reader = try SealedFileReader(url: try sealed(plain), key: key)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let offset = Int.random(in: 0..<size, using: &rng)
            let length = Int.random(in: 0...min(size - offset, 3 * chunk), using: &rng)
            XCTAssertEqual(try reader.read(offset: Int64(offset), length: length),
                           plain.subdata(in: offset ..< offset + length),
                           "offset \(offset) length \(length)")
        }
        // Edges: last byte, a range straddling one boundary, the whole tail.
        XCTAssertEqual(try reader.read(offset: Int64(size - 1), length: 1), plain.suffix(1))
        XCTAssertEqual(try reader.read(offset: Int64(chunk - 2), length: 4),
                       plain.subdata(in: chunk - 2 ..< chunk + 2))
        XCTAssertEqual(try reader.read(offset: Int64(size - chunk - 5), length: chunk + 5),
                       plain.suffix(chunk + 5))
    }

    func testReadPastTheEndThrows() throws {
        let reader = try SealedFileReader(url: try sealed(plaintext(100)), key: key)
        XCTAssertThrowsError(try reader.read(offset: 90, length: 11))
        XCTAssertThrowsError(try reader.read(offset: -1, length: 1))
        XCTAssertEqual(try reader.read(offset: 100, length: 0), Data())
    }

    // --- tamper resistance --------------------------------------------------------------

    func testTamperedCiphertextByteFailsAuthentication() throws {
        let url = try sealed(plaintext(3 * chunk))
        var disk = try Data(contentsOf: url)
        let reader0 = try SealedFileReader(url: url, key: key)
        let target = Int(reader0.layout.sealedOffset(ofChunk: 1)) + 100
        disk[target] ^= 0x01
        try disk.write(to: url)

        let reader = try SealedFileReader(url: url, key: key)
        XCTAssertNoThrow(try reader.read(offset: 0, length: 10))   // chunk 0 untouched
        XCTAssertThrowsError(try reader.read(offset: Int64(chunk), length: 10)) {
            XCTAssertEqual($0 as? SealedFile.Failure, .authenticationFailed)
        }
    }

    func testTamperedHeaderFailsAuthentication() throws {
        let url = try sealed(plaintext(chunk + 10), contentType: "org.xiph.flac")
        var disk = try Data(contentsOf: url)
        // Flip one letter of the content type ("org.xiph.flac" → "org.xiph.flad").
        let header = try SealedFile.Header.decode(disk)
        disk[header.encodedLength - 1] ^= 0x07
        try disk.write(to: url)
        let reader = try SealedFileReader(url: url, key: key)
        XCTAssertThrowsError(try reader.read(offset: 0, length: 1)) {
            XCTAssertEqual($0 as? SealedFile.Failure, .authenticationFailed)
        }
    }

    func testSwappedChunksFailAuthentication() throws {
        let url = try sealed(plaintext(3 * chunk))
        let layout = try SealedFileReader(url: url, key: key).layout
        var disk = try Data(contentsOf: url)
        let a = Int(layout.sealedOffset(ofChunk: 0))
        let b = Int(layout.sealedOffset(ofChunk: 1))
        let length = layout.sealedLength(ofChunk: 0)
        let chunkA = disk.subdata(in: a ..< a + length)
        let chunkB = disk.subdata(in: b ..< b + length)
        disk.replaceSubrange(a ..< a + length, with: chunkB)
        disk.replaceSubrange(b ..< b + length, with: chunkA)
        try disk.write(to: url)

        let reader = try SealedFileReader(url: url, key: key)
        XCTAssertThrowsError(try reader.read(offset: 0, length: 1))
        XCTAssertThrowsError(try reader.read(offset: Int64(chunk), length: 1))
        XCTAssertNoThrow(try reader.read(offset: Int64(2 * chunk), length: 1))
    }

    func testChunkFromAnotherFileFailsAuthentication() throws {
        // Same key, same position — only the per-file nonce prefix and header differ.
        let one = try sealed(plaintext(2 * chunk, seed: 1), file: "one.yeti")
        let two = try sealed(plaintext(2 * chunk, seed: 2), file: "two.yeti")
        let layout = try SealedFileReader(url: one, key: key).layout
        var diskOne = try Data(contentsOf: one)
        let diskTwo = try Data(contentsOf: two)
        let a = Int(layout.sealedOffset(ofChunk: 1))
        let length = layout.sealedLength(ofChunk: 1)
        diskOne.replaceSubrange(a ..< a + length, with: diskTwo.subdata(in: a ..< a + length))
        try diskOne.write(to: one)
        XCTAssertThrowsError(try SealedFileReader(url: one, key: key).read(offset: Int64(chunk), length: 1))
    }

    func testWrongKeyFails() throws {
        let url = try sealed(plaintext(1000))
        let reader = try SealedFileReader(url: url, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try reader.read(offset: 0, length: 1)) {
            XCTAssertEqual($0 as? SealedFile.Failure, .authenticationFailed)
        }
    }

    func testTruncatedFileIsRejectedOnOpen() throws {
        let url = try sealed(plaintext(2 * chunk))
        let disk = try Data(contentsOf: url)
        try disk.dropLast(1).write(to: url)
        XCTAssertThrowsError(try SealedFileReader(url: url, key: key)) {
            XCTAssertEqual($0 as? SealedFile.Failure, .truncated)
        }
    }

    func testPlaintextFileIsNotASealedFile() throws {
        let url = dir.appendingPathComponent("raw.flac")
        try Data("fLaC".utf8 + plaintext(500)).write(to: url)
        XCTAssertThrowsError(try SealedFileReader(url: url, key: key)) {
            XCTAssertEqual($0 as? SealedFile.Failure, .badMagic)
        }
    }

    func testEachSealUsesAFreshNoncePrefix() throws {
        let plain = plaintext(100)
        let one = try SealedFileReader(url: try sealed(plain, file: "a.yeti"), key: key)
        let two = try SealedFileReader(url: try sealed(plain, file: "b.yeti"), key: key)
        XCTAssertNotEqual(one.header.noncePrefix, two.header.noncePrefix)
        XCTAssertEqual(one.header.noncePrefix.count, 8)
    }

    // --- header + layout math ----------------------------------------------------------

    func testHeaderRoundTrips() throws {
        let header = SealedFile.Header(chunkSize: 65536, plaintextLength: 123_456_789_012,
                                       noncePrefix: Data([1, 2, 3, 4, 5, 6, 7, 8]),
                                       contentType: "com.apple.m4a-audio")
        let encoded = header.encoded()
        XCTAssertEqual(encoded.count, header.encodedLength)
        XCTAssertEqual(try SealedFile.Header.decode(encoded + Data([0xFF, 0xEE])), header)
        XCTAssertThrowsError(try SealedFile.Header.decode(encoded.dropLast()))

        // An absurd length is a corrupt header, not an arithmetic trap.
        var huge = header
        huge.plaintextLength = Int64.max
        XCTAssertThrowsError(try SealedFile.Header.decode(huge.encoded())) {
            XCTAssertEqual($0 as? SealedFile.Failure, .malformedHeader)
        }
    }

    func testLayoutMapsRangesToCoveringChunks() throws {
        let layout = SealedLayout(headerLength: 40, chunkSize: 100, plaintextLength: 350)
        XCTAssertEqual(layout.chunkCount, 4)
        XCTAssertEqual(layout.plaintextLength(ofChunk: 3), 50)
        XCTAssertEqual(layout.sealedOffset(ofChunk: 0), 40)
        XCTAssertEqual(layout.sealedOffset(ofChunk: 2), 40 + 2 * 116)
        XCTAssertEqual(layout.sealedLength(ofChunk: 3), 66)
        XCTAssertEqual(layout.sealedFileLength, 40 + 350 + 4 * 16)

        XCTAssertEqual(try layout.chunks(coveringOffset: 0, length: 1), 0...0)
        XCTAssertEqual(try layout.chunks(coveringOffset: 99, length: 2), 0...1)
        XCTAssertEqual(try layout.chunks(coveringOffset: 100, length: 100), 1...1)
        XCTAssertEqual(try layout.chunks(coveringOffset: 150, length: 200), 1...3)
        XCTAssertNil(try layout.chunks(coveringOffset: 350, length: 0))
        XCTAssertThrowsError(try layout.chunks(coveringOffset: 300, length: 51))

        let empty = SealedLayout(headerLength: 40, chunkSize: 100, plaintextLength: 0)
        XCTAssertEqual(empty.chunkCount, 0)
        XCTAssertEqual(empty.sealedFileLength, 40)
    }

    func testContentTypeForExtensions() {
        XCTAssertEqual(SealedFile.contentType(forExtension: "flac"), "org.xiph.flac")
        XCTAssertEqual(SealedFile.contentType(forExtension: "M4A"), "com.apple.m4a-audio")
        XCTAssertEqual(SealedFile.contentType(forExtension: "bin"), "public.audio")
    }
}
