import Foundation

/// The transfer layer: a background URLSession that survives app suspension,
/// carrying the same CDN headers playback uses. One instance per app; tasks
/// carry their trackId in `taskDescription` and are tracked in an explicit
/// map (a `getAllTasks` snapshot races against tasks created after it).
/// Delegate callbacks arrive on the main queue and hop into MainActor state
/// with `assumeIsolated` — the same observer pattern PlayerService uses.
@MainActor
final class DownloadManager: NSObject {

    /// (trackId, fractionCompleted)
    typealias ProgressHandler = @MainActor @Sendable (String, Double) -> Void
    /// (trackId, parked file in the inbox, or error)
    typealias CompletionHandler = @MainActor @Sendable (String, Result<URL, Error>) -> Void

    // Set exactly once in init (the session needs self as its delegate, so
    // it can't be a `let`); never mutated after — safe across the delegate's
    // Sendable requirement.
    private nonisolated(unsafe) var session: URLSession!
    private let onProgress: ProgressHandler
    private let onComplete: CompletionHandler

    /// Live tasks by trackId — the source of truth for supersede/cancel.
    private var activeTasks: [String: URLSessionDownloadTask] = [:]

    /// Where finished temp files are parked until the store files them away:
    /// `didFinishDownloadingTo`'s location dies with the callback, so the
    /// manager immediately moves each finished file here under its trackId.
    private let inboxDir: URL

    init(identifier: String = "com.timvbs.applenugs.downloads",
         onProgress: @escaping ProgressHandler,
         onComplete: @escaping CompletionHandler) {
        self.onProgress = onProgress
        self.onComplete = onComplete

        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleNugs/DownloadInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Anything parked here belongs to a completion that never routed
        // (previous run died mid-handoff) — full-size audio files, purge.
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .forEach { try? FileManager.default.removeItem(at: $0) }
        inboxDir = dir

        super.init()

        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = false
        // Off until the app implements handleEventsForBackgroundURLSession —
        // being relaunched for events nobody handles helps no one. In-flight
        // state doesn't survive relaunch either (see sweep below), so
        // transfers from a dead run are cancelled, not resumed.
        config.sessionSendsLaunchEvents = false
        // Delegate on the main queue so MainActor.assumeIsolated is sound.
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        // Tasks resurrected from a previous run have no in-memory owner —
        // cancel them so they stop burning bandwidth; their shows honestly
        // read as not-downloaded and re-download with one tap.
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }

    /// Queue a transfer for one track, superseding any live task for it.
    func fetch(trackId: String, from url: URL) {
        activeTasks[trackId]?.cancel()
        var request = URLRequest(url: url)
        request.setValue(NugsConstants.playerReferer, forHTTPHeaderField: "Referer")
        request.setValue(NugsConstants.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        task.taskDescription = trackId
        activeTasks[trackId] = task
        task.resume()
    }

    /// Cancel live transfers for the given tracks (show delete / show fail).
    /// Cancellation completions are swallowed by the `.cancelled` check.
    func cancel(trackIds: some Sequence<String>) {
        for trackId in trackIds {
            activeTasks[trackId]?.cancel()
            activeTasks[trackId] = nil
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
            // Ignore ghosts (superseded tasks still draining callbacks).
            guard activeTasks[trackId] === downloadTask else { return }
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
                guard activeTasks[trackId] === downloadTask else { return }
                activeTasks[trackId] = nil
                onComplete(trackId, .failure(URLError(.badServerResponse)))
            }
            return
        }
        // `location` is only valid inside this callback — move it now, even
        // for ghost tasks (the file must not linger in the system temp dir);
        // ghost parks are deleted right below.
        let parked = inboxDir.appendingPathComponent(trackId)
        try? FileManager.default.removeItem(at: parked)
        do {
            try FileManager.default.moveItem(at: location, to: parked)
            MainActor.assumeIsolated {
                guard activeTasks[trackId] === downloadTask else {
                    try? FileManager.default.removeItem(at: parked)
                    return
                }
                activeTasks[trackId] = nil
                onComplete(trackId, .success(parked))
            }
        } catch {
            MainActor.assumeIsolated {
                guard activeTasks[trackId] === downloadTask else { return }
                activeTasks[trackId] = nil
                onComplete(trackId, .failure(error))
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        // Success already flowed through didFinishDownloadingTo; only errors
        // (including cancellations) arrive here with a non-nil error.
        guard let error, let trackId = task.taskDescription else { return }
        if (error as? URLError)?.code == .cancelled { return }
        MainActor.assumeIsolated {
            guard activeTasks[trackId] === task else { return }
            activeTasks[trackId] = nil
            onComplete(trackId, .failure(error))
        }
    }
}
