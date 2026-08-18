import Foundation

/// The "artist · show" now-playing subtitle, broken into linkable segments.
///
/// Sixteen surfaces render this line — four transport signatures, four Mac
/// miniplayers, three full-screen players, the iOS pill and panel, the
/// inspector, and the Home hero — and eight of them build it by joining the two
/// fields into one flat string. Making the artist and the show individually
/// clickable therefore has to happen BELOW the string, not by splitting the
/// views: several of those surfaces are dimensionally tight (the cassette's
/// 25:16 ratio, the pill's text budget, the faceplate's fixed-width ticker), and
/// an HStack of buttons would not truncate the way one Text does.
///
/// So this type answers "what are the runs, and which of them point somewhere",
/// and `NowPlayingMetaText` renders them as one `Text(AttributedString)` with a
/// `.link` on the pointed-at runs. Same glyphs, same metrics, same truncation.
///
/// Deliberately Foundation-only, and taking loose fields rather than a
/// `QueueTrack` (which lives in `PlayerService.swift` and drags in AVFoundation),
/// so it compiles straight into the host-free `AppleNugsTests` target.
enum NowPlayingMetaLine {

    /// Where a segment points. Carries everything the destination needs: the
    /// show has a real container id in hand, while the artist has only a name
    /// and must be resolved against the catalog at tap time.
    enum Target: Hashable {
        case artist(name: String)
        case show(id: String, title: String)
    }

    enum Field { case artist, show }

    /// Some signatures render the line in tracked small caps.
    enum Casing { case asIs, upper }

    enum Mode {
        /// "artist · show" — the usual line.
        case joined
        /// One field only, show preferred. `ExpandedPlayerPanel` renders
        /// `show ?? artist` in a single Text and must keep doing so.
        case firstAvailable
    }

    struct Segment: Equatable {
        let text: String
        /// `nil` for the separator, and for a field that has nothing to point
        /// at — an unresolvable-by-construction show (no container id), or an
        /// empty name.
        let target: Target?
    }

    static let separator = " · "

    /// Builds the runs.
    ///
    /// Two deliberate improvements over the flat `[artist, show].compactMap`
    /// join this replaces: fields are trimmed (catalog names occasionally carry
    /// leading whitespace — see `ArtistListView`, which trims for the same
    /// reason), and a field that is present but EMPTY is dropped rather than
    /// contributing a dangling " · ". Both are invisible on well-formed data.
    static func segments(artist: String?,
                         show: String?,
                         showId: String?,
                         fields: [Field] = [.artist, .show],
                         mode: Mode = .joined,
                         casing: Casing = .asIs) -> [Segment] {
        let artistText = fields.contains(.artist) ? clean(artist) : nil
        let showText = fields.contains(.show) ? clean(show) : nil
        let container = clean(showId)

        let artistSegment = artistText.map {
            Segment(text: cased($0, casing), target: .artist(name: $0))
        }
        let showSegment = showText.map { title in
            // Linkable only when we hold a real container id. Nothing to resolve
            // a show title against, so an unlinked show run is the honest
            // rendering — this is the single-track Search play, and any queue
            // restored from a nowplaying.json written before showId existed.
            Segment(text: cased(title, casing),
                    target: container.map { .show(id: $0, title: title) })
        }

        switch mode {
        case .firstAvailable:
            return [showSegment ?? artistSegment].compactMap { $0 }
        case .joined:
            switch (artistSegment, showSegment) {
            case let (.some(a), .some(s)):
                return [a, Segment(text: separator, target: nil), s]
            case let (.some(a), .none):
                return [a]
            case let (.none, .some(s)):
                return [s]
            case (.none, .none):
                return []
            }
        }
    }

    /// The flat string, for callers that only want text (and for the
    /// `NowPlayingMeta.line` compatibility shim).
    static func text(artist: String?, show: String?, showId: String? = nil,
                     fields: [Field] = [.artist, .show],
                     mode: Mode = .joined,
                     casing: Casing = .asIs) -> String {
        segments(artist: artist, show: show, showId: showId,
                 fields: fields, mode: mode, casing: casing)
            .map(\.text).joined()
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return nil
        }
        return t
    }

    /// Applied to each segment's text separately, never to an already-joined
    /// string, so run boundaries stay exact.
    private static func cased(_ s: String, _ casing: Casing) -> String {
        casing == .upper ? s.uppercased() : s
    }
}

// MARK: - URL vocabulary

/// A tap on a link run arrives as a URL through `OpenURLAction`, so a target has
/// to survive a round trip through one.
extension NowPlayingMetaLine.Target {

    /// Deliberately NOT `applenugs://`. That scheme is registered in both
    /// Info.plists and is the public deep-link contract; routing internal taps
    /// through it would invite LaunchServices and any future `onOpenURL`
    /// handler into a purely in-process hop. Unregistered means the worst case
    /// if an interceptor is ever missing is a silent no-op, not a relaunch.
    static let scheme = "x-applenugs-meta"

    private static let artistHost = "artist"
    private static let showHost = "show"

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .artist(let name):
            c.host = Self.artistHost
            // A query item, never a path segment: real catalog names include
            // "Umphrey's McGee" and "Béla Fleck", and URLComponents handles the
            // percent-encoding for us.
            c.queryItems = [URLQueryItem(name: "name", value: name)]
        case .show(let id, let title):
            c.host = Self.showHost
            c.queryItems = [URLQueryItem(name: "id", value: id),
                            URLQueryItem(name: "title", value: title)]
        }
        // Non-optional by construction: the scheme and host are literals and
        // URLComponents escapes the values.
        return c.url ?? URL(string: "\(Self.scheme)://\(Self.artistHost)")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let items = c.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        switch c.host {
        case Self.artistHost:
            guard let name = value("name") else { return nil }
            self = .artist(name: name)
        case Self.showHost:
            guard let id = value("id") else { return nil }
            self = .show(id: id, title: value("title") ?? "")
        default:
            return nil
        }
    }
}
