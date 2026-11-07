import AVFoundation
import CryptoKit
import Foundation

/// Serves a sealed download (`SealedFile`) to AVFoundation as plaintext, one
/// byte range at a time, so the decrypted audio only ever exists in memory —
/// a few chunks at once — and never on disk.
///
/// The asset's URL uses the `yeti-local://` scheme, which AVFoundation can't
/// load itself, so every read is routed here. Content type and length come
/// from the file's authenticated header; byte-range access is supported, so
/// seeking just asks for a different range and costs only the chunks that
/// cover it.
///
/// Threading: AVFoundation calls the delegate on `queue` (serial). The reader
/// and everything mutable here are touched only on that queue, which is what
/// makes the `@unchecked Sendable` sound.
final class SealedAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {

    /// Bytes handed to AVFoundation per `respond(with:)`. Large requests (it
    /// routinely asks for "everything to the end") are served piece by piece,
    /// re-enqueued between pieces so a cancellation can land in between.
    static let pieceSize = 4 * SealedFile.defaultChunkSize

    // Requests are always served IN FULL, never finished early. AVFoundation
    // opens with "everything to the end" and, served eagerly, pulls ~34 MB of
    // a 74 MB FLAC in the first second before cancelling (resident memory
    // ~101 MB vs ~36 MB for a plain file URL, scratch harness, macOS). Capping
    // each request and finishing it early was tried: ALAC was fine, but FLAC
    // then decoded to DIFFERENT PCM and a 3.0s file played to 3.04s — the FLAC
    // parser treats an early finish as real data boundaries. Don't add a cap
    // back without the bit-identical-PCM test in SealedAssetLoaderTests
    // passing for FLAC under it.

    let queue = DispatchQueue(label: "com.timvbs.applenugs.sealed-loader", qos: .userInitiated)
    private let fileURL: URL
    private let keyProvider: @Sendable () throws -> SymmetricKey

    // Queue-confined.
    private var reader: SealedFileReader?

    init(fileURL: URL, keyProvider: @escaping @Sendable () throws -> SymmetricKey) {
        self.fileURL = fileURL
        self.keyProvider = keyProvider
    }

    /// `AVAssetResourceLoadingRequest` isn't Sendable; it only ever crosses
    /// from this queue back onto this queue.
    private struct RequestBox: @unchecked Sendable {
        let request: AVAssetResourceLoadingRequest
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard loadingRequest.request.url?.scheme == SealedFile.urlScheme else { return false }
        serve(RequestBox(request: loadingRequest))
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // Nothing to tear down: `serve` checks `isCancelled` before every piece.
    }

    private func openReader() throws -> SealedFileReader {
        if let reader { return reader }
        let opened = try SealedFileReader(url: fileURL, key: keyProvider())
        reader = opened
        return opened
    }

    /// Answer one loading request: content information, then the requested
    /// bytes one piece at a time. Runs on `queue`.
    private func serve(_ box: RequestBox) {
        let request = box.request
        guard !request.isCancelled, !request.isFinished else { return }
        do {
            let reader = try openReader()
            if let info = request.contentInformationRequest {
                info.contentType = reader.contentType
                info.contentLength = reader.plaintextLength
                info.isByteRangeAccessSupported = true
            }
            guard let data = request.dataRequest else {
                request.finishLoading()
                return
            }
            let span = Self.span(requestedOffset: data.requestedOffset,
                                 requestedLength: data.requestedLength,
                                 toEnd: data.requestsAllDataToEndOfResource,
                                 currentOffset: data.currentOffset,
                                 resourceLength: reader.plaintextLength)
            guard let piece = Self.nextPiece(in: span, pieceSize: Self.pieceSize) else {
                request.finishLoading()
                return
            }
            data.respond(with: try reader.read(offset: piece.lowerBound,
                                               length: Int(piece.upperBound - piece.lowerBound)))
            if piece.upperBound >= span.upperBound {
                request.finishLoading()
            } else {
                queue.async { [self] in serve(box) }
            }
        } catch {
            request.finishLoading(with: error)
        }
    }

    // --- pure range math (unit-tested) ---------------------------------------------

    /// The plaintext bytes still owed for a data request: from where it has
    /// got to (`currentOffset`) up to its requested end, clamped to the
    /// resource.
    static func span(requestedOffset: Int64, requestedLength: Int, toEnd: Bool,
                     currentOffset: Int64, resourceLength: Int64) -> Range<Int64> {
        let end = toEnd ? resourceLength
            : min(resourceLength, requestedOffset + Int64(requestedLength))
        let start = min(max(currentOffset, requestedOffset, 0), end)
        return start ..< max(start, end)
    }

    /// The next piece to send from `span`, nil once nothing is left.
    static func nextPiece(in span: Range<Int64>, pieceSize: Int) -> Range<Int64>? {
        guard !span.isEmpty else { return nil }
        return span.lowerBound ..< min(span.upperBound, span.lowerBound + Int64(pieceSize))
    }
}

/// An asset that keeps its resource loader alive. `AVAssetResourceLoader`
/// holds its delegate weakly, and the player items — current and gapless
/// preload — outlive any local variable, so the asset itself is the owner.
final class SealedURLAsset: AVURLAsset, @unchecked Sendable {
    let loader: SealedAssetLoader

    /// `name` only labels the URL (it shows up in AVFoundation logs); the
    /// loader reads `fileURL`.
    init(fileURL: URL, name: String, keyProvider: @escaping @Sendable () throws -> SymmetricKey) {
        loader = SealedAssetLoader(fileURL: fileURL, keyProvider: keyProvider)
        var components = URLComponents()
        components.scheme = SealedFile.urlScheme
        components.host = "download"
        components.path = "/" + name
        super.init(url: components.url ?? URL(string: "\(SealedFile.urlScheme)://download")!,
                   options: nil)
        resourceLoader.setDelegate(loader, queue: loader.queue)
    }
}
