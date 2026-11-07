#if DEBUG
import Foundation

// The DEBUG Network Probe's pure half: what it asks, in what order, how a
// response is summarized, and the plain-text report. Phase B of the compliance
// spec (docs/superpowers/specs/2026-11-06-yeti-compliance-design.md) — Tim runs
// it with his real session and decides the honest identity from the results.
//
// Pure Foundation, compiled into AppleNugsTests. The networking lives in the
// DEBUG extension at the bottom of NugsClient.swift; the sequencing (one
// request at a time, a second apart) in NetworkProbeView.swift.

/// Which user agent a step sends.
enum ProbeUA: String, Sendable, Hashable {
    /// Today's: the official Android app's.
    case spoofed
    /// `Yeti/<version> (unofficial; …)`.
    case honest

    var label: String {
        switch self {
        case .spoofed: return "Android UA"
        case .honest: return "Yeti UA"
        }
    }
}

enum ProbeGroup: String, Sendable, CaseIterable {
    case api, resolve, cdn

    var title: String {
        switch self {
        case .api: return "API identity"
        case .resolve: return "Resolve (UA × tier)"
        case .cdn: return "CDN (UA × Referer)"
        }
    }
}

/// One request the probe makes.
enum ProbeStep: Sendable, Hashable {
    /// GET subscriptions.nugs.net/api/v1/me/subscriptions — an authenticated
    /// JSON call the app makes at every login.
    case api(ProbeUA)
    /// GET streamapi.nugs.net/api.aspx?method=catalog.container for the current
    /// track's show — the busy browse host, same request as `album(id:)`.
    case catalog(ProbeUA)
    /// GET streamapi.nugs.net/bigriver/subPlayer.aspx for one platformID.
    case resolve(ProbeUA, platformId: Int)
    /// Ranged GET (bytes 0–1023, cancelled once headers arrive) of a stream
    /// URL a resolve returned.
    case cdn(ProbeUA, referer: Bool)

    var group: ProbeGroup {
        switch self {
        case .api, .catalog: return .api
        case .resolve: return .resolve
        case .cdn: return .cdn
        }
    }

    var ua: ProbeUA {
        switch self {
        case .api(let ua), .catalog(let ua), .resolve(let ua, _), .cdn(let ua, _): return ua
        }
    }

    var label: String {
        switch self {
        case .api(let ua): return "Subscriptions · \(ua.label)"
        case .catalog(let ua): return "Catalog show · \(ua.label)"
        case .resolve(let ua, let tier): return "\(ua.label) · tier \(tier)"
        case .cdn(let ua, let referer):
            return "\(ua.label) · \(referer ? "with Referer" : "no Referer")"
        }
    }

    /// The identity this step sends: today's for the control steps, the
    /// honest one otherwise — except the CDN Referer, which is the step's
    /// own variable, set independently of the UA.
    func identity(honest: NugsIdentity) -> NugsIdentity {
        var identity = ua == .honest ? honest : .current
        if case .cdn(_, let referer) = self {
            identity.refererCDN = referer ? NugsConstants.playerReferer : nil
        }
        return identity
    }
}

/// What the probe asks, in order. The control (today's identity) goes first
/// in every group, so a session problem shows up before the honest variant is
/// blamed for it.
enum ProbePlan {
    static let apiSteps: [ProbeStep] = [
        .api(.spoofed), .api(.honest), .catalog(.spoofed), .catalog(.honest),
    ]

    static func resolveSteps(platforms: [Int] = NugsConstants.probePlatforms) -> [ProbeStep] {
        [ProbeUA.spoofed, .honest].flatMap { ua in
            platforms.map { ProbeStep.resolve(ua, platformId: $0) }
        }
    }

    static let cdnSteps: [ProbeStep] = [
        .cdn(.spoofed, referer: true),   // exactly today's playback request
        .cdn(.spoofed, referer: false),
        .cdn(.honest, referer: true),
        .cdn(.honest, referer: false),
    ]

    /// Every step, CDN included (the CDN group runs only if a resolve returned
    /// a URL — see `cdnTarget`).
    static func allSteps(platforms: [Int] = NugsConstants.probePlatforms) -> [ProbeStep] {
        apiSteps + resolveSteps(platforms: platforms) + cdnSteps
    }

    /// The URL the CDN checks fetch: the one production would play — the best
    /// `preferenceRank` among the control resolves (lowest tier on a tie) —
    /// else the best an honest resolve returned. Nil skips the CDN group.
    static func cdnTarget(from results: [ProbeResult]) -> ProbeResult? {
        let withURL = results.filter { result in
            guard case .resolve = result.step else { return false }
            return result.streamURL?.isEmpty == false
        }
        func best(_ rs: [ProbeResult]) -> ProbeResult? {
            rs.min { a, b in
                let ra = a.format?.preferenceRank ?? Int.max
                let rb = b.format?.preferenceRank ?? Int.max
                if ra != rb { return ra < rb }
                return a.platformId < b.platformId
            }
        }
        return best(withURL.filter { $0.step.ua == .spoofed }) ?? best(withURL)
    }
}

/// One step's outcome.
struct ProbeResult: Sendable, Equatable {
    var step: ProbeStep
    var ok: Bool
    /// Nil when no HTTP response arrived (transport error, timeout).
    var status: Int?
    /// One line for the screen: format and bitrate, or what went wrong.
    var summary: String
    /// Extra lines for the copied report only (response keys, body snippet).
    var detail: [String] = []
    /// A resolve's stream link. Used to pick the CDN target; NEVER printed —
    /// it is a signed, per-session URL.
    var streamURL: String? = nil
    var format: AudioFormat? = nil

    var platformId: Int {
        if case .resolve(_, let tier) = step { return tier }
        return 0
    }

    var mark: String { ok ? "✓" : "✗" }
    var statusText: String { status.map(String.init) ?? "—" }
}

/// Turning responses into result rows.
enum ProbeParse {
    /// Keys whose names suggest they describe the stream's format.
    private static let formatHints = ["format", "codec", "bitrate", "kbps", "quality",
                                      "samplerate", "bitdepth", "container"]

    /// Scalar top-level fields that look like format/codec/bitrate
    /// descriptors, as "key=value", sorted by key.
    static func reportedFields(_ json: JSON) -> [String] {
        guard let dict = json.raw as? [String: Any] else { return [] }
        return dict.keys.sorted().compactMap { key in
            let lower = key.lowercased()
            guard formatHints.contains(where: { lower.contains($0) }),
                  let value = JSON(dict[key]).string
            else { return nil }
            return "\(key)=\(value)"
        }
    }

    /// Top-level key names (never values — they include signed URLs).
    static func responseKeys(_ json: JSON) -> [String] {
        ((json.raw as? [String: Any])?.keys).map { $0.sorted() } ?? []
    }

    /// A body excerpt for a failed response, on one line.
    static func snippet(_ data: Data, limit: Int = 120) -> String {
        let text = String(decoding: data.prefix(limit * 4), as: UTF8.self)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    static func resolve(step: ProbeStep, status: Int, body: Data) -> ProbeResult {
        let json = JSON.parse(body)
        let keys = responseKeys(json)
        var detail = keys.isEmpty ? [] : ["keys: " + keys.joined(separator: ", ")]
        guard (200..<300).contains(status) else {
            let body = snippet(body)
            if !body.isEmpty { detail.append("body: " + body) }
            return ProbeResult(step: step, ok: false, status: status,
                               summary: "HTTP \(status)", detail: detail)
        }
        guard let link = json.str("streamLink", "StreamLink"), !link.isEmpty else {
            return ProbeResult(step: step, ok: false, status: status,
                               summary: "No stream link", detail: detail)
        }
        let format = AudioFormat.identify(link)
        let fields = reportedFields(json)
        var summary = format.qualityLabel
        if !fields.isEmpty { summary += " · " + fields.joined(separator: " · ") }
        return ProbeResult(step: step, ok: true, status: status, summary: summary,
                           detail: detail, streamURL: link, format: format)
    }

    static func api(step: ProbeStep, status: Int, body: Data) -> ProbeResult {
        let ok = (200..<300).contains(status)
        var detail: [String] = []
        if !ok {
            let body = snippet(body)
            if !body.isEmpty { detail.append("body: " + body) }
        }
        return ProbeResult(step: step, ok: ok, status: status,
                           summary: ok ? "Accepted" : "HTTP \(status)", detail: detail)
    }

    /// "audio/flac · 1,024 B of 38.2 MB". 200 (Range ignored) and 206 both
    /// mean the CDN served the file.
    static func cdn(step: ProbeStep, status: Int, contentType: String?,
                    contentLength: String?, contentRange: String?) -> ProbeResult {
        let ok = status == 200 || status == 206
        var parts: [String] = []
        if let contentType, !contentType.isEmpty { parts.append(contentType) }
        let total = contentRange.flatMap(totalBytes(fromContentRange:))
        let length = contentLength.flatMap { Int64($0) }
        switch (length, total) {
        case let (length?, total?): parts.append("\(length) B of \(megabytes(total))")
        case let (length?, nil): parts.append("\(length) B")
        case let (nil, total?): parts.append("of \(megabytes(total))")
        case (nil, nil): break
        }
        if status == 200 { parts.append("Range ignored") }
        let summary = ok
            ? (parts.isEmpty ? "Served" : parts.joined(separator: " · "))
            : "HTTP \(status)" + (parts.isEmpty ? "" : " · " + parts.joined(separator: " · "))
        return ProbeResult(step: step, ok: ok, status: status, summary: summary)
    }

    /// A `catalog.container` response passes when it is 2xx AND parses into a
    /// show with tracks through the production parser (`Catalog.album`).
    static func catalog(step: ProbeStep, status: Int, body: Data,
                        showId: String, trackId: String) -> ProbeResult {
        guard (200..<300).contains(status) else {
            let body = snippet(body)
            return ProbeResult(step: step, ok: false, status: status, summary: "HTTP \(status)",
                               detail: body.isEmpty ? [] : ["body: " + body])
        }
        let json = JSON.parse(body)
        let album = Catalog.album(from: json, id: showId)
        guard !album.tracks.isEmpty else {
            let keys = responseKeys(json.unwrapped)
            return ProbeResult(step: step, ok: false, status: status, summary: "Show didn't parse",
                               detail: keys.isEmpty ? [] : ["keys: " + keys.joined(separator: ", ")])
        }
        let listed = album.tracks.contains { $0.id == trackId }
        let count = album.tracks.count
        return ProbeResult(
            step: step, ok: true, status: status,
            summary: "Show parsed · \(count) track\(count == 1 ? "" : "s")"
                + (listed ? " · current track listed" : " · current track not listed"))
    }

    static func failure(step: ProbeStep, error: String) -> ProbeResult {
        ProbeResult(step: step, ok: false, status: nil, summary: error)
    }

    /// `bytes 0-1023/40000000` → 40000000. `*` (unknown total) → nil.
    static func totalBytes(fromContentRange header: String) -> Int64? {
        guard let slash = header.lastIndex(of: "/") else { return nil }
        return Int64(header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }

    static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }
}

/// The plain-text report "Copy results" puts on the pasteboard.
enum ProbeReport {
    struct Header: Sendable, Equatable {
        var date: Date
        var appVersion: String
        var platform: String
        var trackTitle: String
        var trackArtist: String
        var trackId: String
        var showId: String?
        var honest: NugsIdentity
    }

    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// One row: mark, status right-aligned in 3, label padded to 30, summary.
    static func line(_ r: ProbeResult) -> String {
        let status = String(repeating: " ", count: max(0, 3 - r.statusText.count)) + r.statusText
        let label = r.step.label.padding(toLength: max(30, r.step.label.count),
                                         withPad: " ", startingAt: 0)
        return "\(r.mark) \(status)  \(label)  \(r.summary)"
    }

    static func text(header h: Header, results: [ProbeResult], cdnTarget: ProbeResult?,
                     note: String? = nil) -> String {
        var out: [String] = []
        out.append("Yeti network probe — \(timestamp(h.date))")
        out.append("App: Yeti \(h.appVersion) · \(h.platform)")
        out.append("Track: \(h.trackTitle) — \(h.trackArtist) (trackID \(h.trackId), show \(h.showId ?? "none"))")
        out.append("Yeti UA: \(h.honest.userAgentAPI)")
        out.append("Android UA (API, CDN): \(NugsIdentity.current.userAgentAPI)")
        out.append("Android UA (resolve): \(NugsIdentity.current.userAgentLegacy)")
        out.append("Referer (CDN): \(NugsIdentity.current.refererCDN ?? "none")")
        if let note { out.append("Note: \(note)") }
        for group in ProbeGroup.allCases {
            out.append("")
            out.append("[\(group.title)]")
            if group == .cdn {
                if let t = cdnTarget, let format = t.format {
                    out.append("  target: \(format.qualityLabel) from \(t.step.label)")
                } else {
                    out.append("  skipped — no resolve returned a stream URL")
                }
            }
            for r in results where r.step.group == group {
                out.append(line(r))
                out.append(contentsOf: r.detail.map { "      " + $0 })
            }
        }
        return out.joined(separator: "\n") + "\n"
    }
}
#endif
