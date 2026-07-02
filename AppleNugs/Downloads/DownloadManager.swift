import Foundation

/// The transfer layer: a background URLSession that survives app suspension,
/// carrying the same CDN headers playback uses. One instance per app; tasks
/// carry their trackId in `taskDescription` so progress and completion can be
/// routed without extra bookkeeping. Delegate callbacks arrive on the main
/// queue and hop into the MainActor store via the closures given at init —
/// the same observer pattern PlayerService uses.
final class DownloadManager: NSObject {

    /// (trackId, fractionCompleted)
    typealias ProgressHandler = @MainActor @Sendable (String, Double) -> Void
    /// (trackId, temp file location moved to a stable spot by the caller-owned
    /// closure, or error)
    typealias CompletionHandler = @MainActor @Sendable (String, Result<URL, Error>) -> Void

    // Set exactly once in init (the session needs self as its delegate, so
    // it can't be a `let`); never mutated after — safe across the delegate's
    // Sendable requirement.
    private nonisolated(unsafe) var session: URLSession!
    private let onProgress: ProgressHandler
    private let onComplete: CompletionHandler

    /// Where finished temp files are parked until the store files them away:
    /// `didFinishDownloadingTo`'s location dies with the callback, so the
    /// manager immediately moves each finished file here under its trackId.
    private let inboxDir: URL

    @MainActor
    init(identifier: String = "com.timvbs.applenugs.downloads",
         onProgress: @escaping ProgressHandler,
         onComplete: @escaping CompletionHandler) {
        self.onProgress = onProgress
        self.onComplete = onComplete

        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleNugs/DownloadInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        inboxDir = dir

        super.init()

        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        // Delegate on the main queue so MainActor.assumeIsolated is sound.
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    /// Queue a transfer for one track. Any live task for the same track is
    /// superseded (cancelled) first.
    func fetch(trackId: String, from url: URL) {
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == trackId {
                task.cancel()
            }
        }
        var request = URLRequest(url: url)
        request.setValue(NugsConstants.playerReferer, forHTTPHeaderField: "Referer")
        request.setValue(NugsConstants.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        task.taskDescription = trackId
        task.resume()
    }

    func cancelAll() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let trackId = downloadTask.taskDescription,
              totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        MainActor.assumeIsolated {
            onProgress(trackId, min(max(fraction, 0), 1))
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let trackId = downloadTask.taskDescription else { return }
        // A non-2xx response (e.g. a CDN 403 HTML page) is not a download.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            MainActor.assumeIsolated {
                onComplete(trackId, .failure(URLError(.badServerResponse)))
            }
            return
        }
        // `location` is only valid inside this callback — move it now.
        let parked = inboxDir.appendingPathComponent(trackId)
        try? FileManager.default.removeItem(at: parked)
        do {
            try FileManager.default.moveItem(at: location, to: parked)
            MainActor.assumeIsolated { onComplete(trackId, .success(parked)) }
        } catch {
            MainActor.assumeIsolated { onComplete(trackId, .failure(error)) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        // Success already flowed through didFinishDownloadingTo; only errors
        // (including cancellations) arrive here with a non-nil error.
        guard let error, let trackId = task.taskDescription else { return }
        if (error as? URLError)?.code == .cancelled { return }
        MainActor.assumeIsolated {
            onComplete(trackId, .failure(error))
        }
    }
}
