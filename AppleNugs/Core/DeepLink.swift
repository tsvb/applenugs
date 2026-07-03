import Foundation

/// A parsed `applenugs://` deep link. Pure value type — no I/O — so it unit-tests
/// cleanly. Contract lives in goose-almanac `docs/integrations/applenugs-deeplink.md`:
///   applenugs://show/<date>?artist=Goose[&venue=][&song=&set=&pos=][&media=audio|video]
struct DeepLink: Equatable {
    enum Media: String { case audio, video }

    var date: String          // "yyyy-MM-dd" — the join key
    var artist: String        // e.g. "Goose"
    var venue: String?        // tie-break for two-show days
    var song: String?         // track title to start at (track-level link)
    var setNumber: String?    // elgoose setNumber ("1","2","e"…) — tie-break only
    var position: Int?        // elgoose position — tie-break only
    var media: Media

    /// Parse `applenugs://show/<date>?artist=…&venue=…&song=…&set=…&pos=…&media=…`.
    /// Returns nil for anything that isn't a well-formed `show` link.
    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "applenugs",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host == "show"
        else { return nil }

        // host is "show"; the date is the first path segment (path == "/<date>").
        guard let date = comps.path.split(separator: "/").first.map(String.init),
              !date.isEmpty
        else { return nil }

        // URLComponents percent-decodes queryItems for us. (The Almanac emits %20,
        // never +, precisely because URLComponents does NOT turn + into a space.)
        // uniquingKeysWith avoids a trap-on-duplicate-key crash from malformed links.
        let items = Dictionary(
            (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first })

        guard let artist = items["artist"], !artist.isEmpty else { return nil }

        func nonEmpty(_ key: String) -> String? {
            items[key].flatMap { $0.isEmpty ? nil : $0 }
        }

        return DeepLink(
            date: DeepLinkMatch.normalizedISODate(date),   // pad so "2024-4-20" matches catalog dateText
            artist: artist,
            venue: nonEmpty("venue"),
            song: nonEmpty("song"),
            setNumber: nonEmpty("set"),
            position: items["pos"].flatMap { Int($0) },
            media: items["media"].flatMap(Media.init(rawValue:)) ?? .audio)
    }
}

/// Pure, app-type-free fuzzy matching for the deep-link router. Kept separate
/// from `DeepLinkRouter` (which needs AppModel/Catalog) so this logic compiles
/// into the host-free logic-test bundle and unit-tests cleanly.
enum DeepLinkMatch {

    /// Lowercased, diacritic-folded, punctuation-stripped, whitespace-trimmed.
    /// Makes title/venue comparison robust across elgoose vs nugs spellings.
    static func normalize(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Bidirectional normalized containment. A venue hint like "Salt Shed" should
    /// match "The Salt Shed, Chicago" and vice-versa. nil left side never matches.
    static func venueMatches(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na.contains(nb) || nb.contains(na)
    }

    /// Title match within ONE show's track list — a small candidate set, so
    /// normalized matching is safe. Titles are in performance order, so the
    /// returned index lines up with the playback queue. elgoose set/pos are
    /// tie-breakers only; titles win. Precedence (most→least confident):
    ///   1. exact normalized equality
    ///   2. a title that CONTAINS the song (e.g. "Hot Tea" → "Hot Tea Reprise")
    ///   3. the song CONTAINS a title (segue link "Madhuvan > Hot Tea" → track
    ///      "Madhuvan"): pick the LONGEST contained title — the most specific —
    ///      rather than the first, so an incidental earlier short track doesn't win.
    static func bestTrackIndex(matching song: String, inTitles titles: [String]) -> Int? {
        let target = normalize(song)
        guard !target.isEmpty else { return nil }
        let norm = titles.map(normalize)
        if let i = norm.firstIndex(of: target) { return i }
        if let i = norm.firstIndex(where: { !$0.isEmpty && $0.contains(target) }) { return i }
        return norm.enumerated()
            .filter { $0.element.count >= 4 && target.contains($0.element) }
            .max(by: { $0.element.count < $1.element.count })?
            .offset
    }

    /// Zero-pad a `yyyy-M-d` date to `yyyy-MM-dd` so a non-padded but otherwise
    /// valid inbound date still matches the catalog's always-padded dateText.
    /// Returns the input unchanged if it isn't three numeric components.
    static func normalizedISODate(_ s: String) -> String {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return s }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
