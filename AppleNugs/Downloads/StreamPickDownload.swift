import Foundation

// Pure downloadability rules for resolved stream picks. HLS playlists are
// streams, not files — only direct-file picks can be saved for offline.

extension StreamPick {
    /// True when the pick is a direct file the CDN will serve as bytes.
    /// The URL check backstops a mislabeled format.
    var isDownloadable: Bool {
        format != .hls && !url.lowercased().contains(".m3u8")
    }

    /// The on-disk extension for a downloaded pick. Format knowledge first
    /// (the container is implied by the tier), URL path extension as the
    /// fallback, "bin" when nothing usable exists.
    var downloadFileExtension: String {
        switch format {
        case .flac16, .mqa24: return "flac"
        case .alac16, .aac150: return "m4a"
        case .s360ra, .hls, .unknown:
            let ext = (URL(string: url)?.pathExtension ?? "")
            return ext.isEmpty ? "bin" : ext.lowercased()
        }
    }
}

/// The pick a download should fetch: best preference rank among the
/// downloadable ones, nil when the track is stream-only (HLS).
func bestDownloadablePick(_ picks: [StreamPick]) -> StreamPick? {
    picks.filter(\.isDownloadable).min { $0.format.preferenceRank < $1.format.preferenceRank }
}
