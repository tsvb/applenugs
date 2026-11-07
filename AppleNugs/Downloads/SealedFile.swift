import CryptoKit
import Foundation

// The at-rest format for downloaded audio (`<uuid>.yeti`). Pure Foundation +
// CryptoKit, so it is compiled straight into the host-free test bundle.
//
// Layout (all integers big-endian):
//
//   header   "YETI" | version u8 | chunkSize u32 | plaintextLength u64
//            | noncePrefix 8 bytes | contentTypeLength u16 | contentType UTF-8
//   chunk i  ciphertext (chunkSize bytes; the last chunk may be shorter) | tag 16
//
// Every chunk is sealed with AES-GCM under the per-install key. The 12-byte
// nonce is the file's random 8-byte prefix followed by the chunk index, and
// the authenticated data is the whole header followed by the chunk index — so
// a chunk can't be moved to another position, spliced in from another file, or
// paired with an edited header, and the authenticated plaintext length makes
// truncation fail too. Chunk i always starts at
// `headerLength + i * (chunkSize + 16)`, which is what makes a byte range map
// to its covering chunks with plain arithmetic (`SealedLayout`).

enum SealedFile {
    /// The custom URL scheme playback uses for a downloaded track. Lives here
    /// (not with the AVFoundation loader) so pure code can recognize a local
    /// pick without importing AVFoundation.
    static let urlScheme = "yeti-local"
    static let fileExtension = "yeti"

    static let magic = Data("YETI".utf8)
    static let version: UInt8 = 1
    static let defaultChunkSize = 64 * 1024
    static let tagSize = 16
    static let noncePrefixSize = 8

    enum Failure: Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt8)
        case malformedHeader
        /// The file is shorter than its header says it should be.
        case truncated
        /// A chunk failed to authenticate: tampered bytes, chunks out of
        /// order, or the wrong key. Deliberately indistinguishable.
        case authenticationFailed
        /// The source changed size while it was being sealed.
        case sourceChanged
        case rangeOutOfBounds
    }

    struct Header: Equatable, Sendable {
        var chunkSize: Int
        var plaintextLength: Int64
        var noncePrefix: Data
        var contentType: String

        /// Byte count of the encoded header, i.e. where chunk 0 starts.
        var encodedLength: Int { Self.fixedLength + Data(contentType.utf8).count }

        static let fixedLength = 4 + 1 + 4 + 8 + 8 + 2

        func encoded() -> Data {
            var data = SealedFile.magic
            data.append(SealedFile.version)
            data.appendBigEndian(UInt32(chunkSize))
            data.appendBigEndian(UInt64(plaintextLength))
            data.append(noncePrefix)
            let type = Data(contentType.utf8)
            data.appendBigEndian(UInt16(type.count))
            data.append(type)
            return data
        }

        /// Parse the header from the start of `data`. `data` may hold more
        /// than the header (or less, which throws).
        static func decode(_ data: Data) throws -> Header {
            let bytes = [UInt8](data.prefix(fixedLength))
            guard bytes.count >= 5 else { throw Failure.truncated }
            guard Data(bytes[0..<4]) == SealedFile.magic else { throw Failure.badMagic }
            guard bytes[4] == SealedFile.version else { throw Failure.unsupportedVersion(bytes[4]) }
            guard bytes.count == fixedLength else { throw Failure.truncated }
            let chunkSize = Int(bytes.bigEndianInteger(at: 5, as: UInt32.self))
            let length = bytes.bigEndianInteger(at: 9, as: UInt64.self)
            let prefix = Data(bytes[17..<25])
            let typeLength = Int(bytes.bigEndianInteger(at: 25, as: UInt16.self))
            // Bounds keep the layout arithmetic far from overflow, so a
            // corrupted header throws instead of trapping.
            guard chunkSize > 0, chunkSize <= 16 * 1024 * 1024, length <= 1 << 48 else {
                throw Failure.malformedHeader
            }
            let all = [UInt8](data.prefix(fixedLength + typeLength))
            guard all.count == fixedLength + typeLength else { throw Failure.truncated }
            guard let type = String(bytes: all[fixedLength...], encoding: .utf8) else {
                throw Failure.malformedHeader
            }
            return Header(chunkSize: chunkSize, plaintextLength: Int64(length),
                          noncePrefix: prefix, contentType: type)
        }
    }

    // --- content types ---------------------------------------------------------

    /// The UTI AVFoundation needs for a downloaded container, from the file
    /// extension the download would have had. Both mappings are verified
    /// against AVFoundation through the resource loader (see
    /// SealedAssetLoaderTests).
    static func contentType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "flac": return "org.xiph.flac"
        case "m4a", "mp4", "alac": return "com.apple.m4a-audio"
        case "mp3": return "public.mp3"
        case "aac": return "public.aac-audio"
        default: return "public.audio"
        }
    }

    // --- crypto primitives -------------------------------------------------------

    static func nonce(prefix: Data, chunk: Int) throws -> AES.GCM.Nonce {
        var bytes = prefix
        bytes.appendBigEndian(UInt32(chunk))
        return try AES.GCM.Nonce(data: bytes)
    }

    static func authenticatedData(header: Data, chunk: Int) -> Data {
        var aad = header
        aad.appendBigEndian(UInt32(chunk))
        return aad
    }

    // --- sealing -------------------------------------------------------------------

    /// Seal `source` into a new file at `destination`, streaming one chunk at
    /// a time (memory stays at about one chunk regardless of file size).
    /// Leaves no partial destination behind on failure. Does not touch
    /// `source`.
    static func seal(contentsOf source: URL, to destination: URL, key: SymmetricKey,
                     contentType: String, chunkSize: Int = defaultChunkSize) throws {
        precondition(chunkSize > 0 && chunkSize <= Int(UInt32.max))
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let length = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        let header = Header(chunkSize: chunkSize, plaintextLength: length,
                            noncePrefix: randomBytes(noncePrefixSize), contentType: contentType)
        let headerBytes = header.encoded()

        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try? FileManager.default.removeItem(at: destination)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            try output.write(contentsOf: headerBytes)

            let layout = SealedLayout(header: header)
            var total: Int64 = 0
            for chunk in 0..<layout.chunkCount {
                try autoreleasepool {
                    let plain = try input.read(upToCount: chunkSize) ?? Data()
                    guard plain.count == layout.plaintextLength(ofChunk: chunk) else {
                        throw Failure.sourceChanged
                    }
                    total += Int64(plain.count)
                    let box = try AES.GCM.seal(
                        plain, using: key,
                        nonce: nonce(prefix: header.noncePrefix, chunk: chunk),
                        authenticating: authenticatedData(header: headerBytes, chunk: chunk))
                    try output.write(contentsOf: box.ciphertext)
                    try output.write(contentsOf: box.tag)
                }
            }
            // A source that grew after we sized it would be silently cut off.
            guard total == length, (try input.read(upToCount: 1) ?? Data()).isEmpty else {
                throw Failure.sourceChanged
            }
            try output.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

/// Pure chunk/range arithmetic for a sealed file — no I/O, no crypto.
struct SealedLayout: Equatable, Sendable {
    let headerLength: Int
    let chunkSize: Int
    let plaintextLength: Int64

    init(headerLength: Int, chunkSize: Int, plaintextLength: Int64) {
        self.headerLength = headerLength
        self.chunkSize = chunkSize
        self.plaintextLength = plaintextLength
    }

    init(header: SealedFile.Header) {
        self.init(headerLength: header.encodedLength, chunkSize: header.chunkSize,
                  plaintextLength: header.plaintextLength)
    }

    var chunkCount: Int {
        Int((plaintextLength + Int64(chunkSize) - 1) / Int64(chunkSize))
    }

    /// The exact on-disk size a well-formed file with this layout has.
    var sealedFileLength: Int64 {
        Int64(headerLength) + plaintextLength + Int64(chunkCount * SealedFile.tagSize)
    }

    func plaintextOffset(ofChunk chunk: Int) -> Int64 {
        Int64(chunk) * Int64(chunkSize)
    }

    func plaintextLength(ofChunk chunk: Int) -> Int {
        Int(min(Int64(chunkSize), plaintextLength - plaintextOffset(ofChunk: chunk)))
    }

    /// Where chunk `chunk`'s ciphertext starts in the file.
    func sealedOffset(ofChunk chunk: Int) -> UInt64 {
        UInt64(headerLength) + UInt64(chunk) * UInt64(chunkSize + SealedFile.tagSize)
    }

    /// Ciphertext + tag byte count of chunk `chunk`.
    func sealedLength(ofChunk chunk: Int) -> Int {
        plaintextLength(ofChunk: chunk) + SealedFile.tagSize
    }

    /// The chunk indices whose plaintext covers `offset ..< offset + length`,
    /// or nil for an empty range. Throws for a range past the end.
    func chunks(coveringOffset offset: Int64, length: Int) throws -> ClosedRange<Int>? {
        guard offset >= 0, length >= 0, offset + Int64(length) <= plaintextLength else {
            throw SealedFile.Failure.rangeOutOfBounds
        }
        guard length > 0 else { return nil }
        let first = Int(offset / Int64(chunkSize))
        let last = Int((offset + Int64(length) - 1) / Int64(chunkSize))
        return first...last
    }
}

/// Random-access decryption of one sealed file. Not thread-safe: confine an
/// instance to one queue (the resource loader's). Keeps the most recently
/// decrypted chunk, because AVFoundation reads small sequential ranges and
/// would otherwise decrypt the same chunk repeatedly.
final class SealedFileReader {
    let header: SealedFile.Header
    let layout: SealedLayout
    private let handle: FileHandle
    private let headerBytes: Data
    private let key: SymmetricKey
    private var cache: (chunk: Int, plaintext: Data)?

    var plaintextLength: Int64 { header.plaintextLength }
    var contentType: String { header.contentType }

    init(url: URL, key: SymmetricKey) throws {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            // The fixed part first; it says how long the content type is.
            var bytes = try handle.read(upToCount: SealedFile.Header.fixedLength) ?? Data()
            if bytes.count == SealedFile.Header.fixedLength {
                let typeLength = Int([UInt8](bytes).bigEndianInteger(at: 25, as: UInt16.self))
                bytes += try handle.read(upToCount: typeLength) ?? Data()
            }
            headerBytes = bytes
            header = try SealedFile.Header.decode(headerBytes)
            layout = SealedLayout(header: header)
            let size = try handle.seekToEnd()
            guard size == UInt64(layout.sealedFileLength) else { throw SealedFile.Failure.truncated }
        } catch {
            try? handle.close()
            throw error
        }
        self.handle = handle
        self.key = key
    }

    deinit {
        try? handle.close()
    }

    /// Decrypt and return plaintext bytes `offset ..< offset + length`,
    /// reading only the chunks that cover the range.
    func read(offset: Int64, length: Int) throws -> Data {
        guard let chunks = try layout.chunks(coveringOffset: offset, length: length) else {
            return Data()
        }
        var out = Data(capacity: length)
        for chunk in chunks {
            let plain = try decryptChunk(chunk)
            let chunkStart = layout.plaintextOffset(ofChunk: chunk)
            let from = Int(max(offset, chunkStart) - chunkStart)
            let to = Int(min(offset + Int64(length), chunkStart + Int64(plain.count)) - chunkStart)
            out.append(plain[plain.startIndex + from ..< plain.startIndex + to])
        }
        return out
    }

    func decryptChunk(_ chunk: Int) throws -> Data {
        if let cache, cache.chunk == chunk { return cache.plaintext }
        try handle.seek(toOffset: layout.sealedOffset(ofChunk: chunk))
        let sealedLength = layout.sealedLength(ofChunk: chunk)
        let sealed = try handle.read(upToCount: sealedLength) ?? Data()
        guard sealed.count == sealedLength else { throw SealedFile.Failure.truncated }
        let split = sealed.startIndex + sealedLength - SealedFile.tagSize
        do {
            let box = try AES.GCM.SealedBox(
                nonce: SealedFile.nonce(prefix: header.noncePrefix, chunk: chunk),
                ciphertext: sealed[sealed.startIndex ..< split],
                tag: sealed[split...])
            let plain = try AES.GCM.open(
                box, using: key,
                authenticating: SealedFile.authenticatedData(header: headerBytes, chunk: chunk))
            cache = (chunk, plain)
            return plain
        } catch {
            throw SealedFile.Failure.authenticationFailed
        }
    }
}

// --- big-endian helpers -----------------------------------------------------------

fileprivate extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}

private extension Array where Element == UInt8 {
    func bigEndianInteger<T: FixedWidthInteger>(at offset: Int, as: T.Type) -> T {
        var value: T = 0
        for i in 0..<MemoryLayout<T>.size {
            value = (value << 8) | T(self[offset + i])
        }
        return value
    }
}
