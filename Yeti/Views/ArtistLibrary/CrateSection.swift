import Foundation

/// Anything the crate list can section and filter. Kept minimal so the pure
/// grouping logic compiles into the host-free logic-test bundle without
/// dragging in Route / NugsConstants / SwiftUI.
protocol CrateSectionable {
    var date: Date? { get }
    /// Lowercased, diacritic-folded haystack. Built once, at construction.
    var searchText: String { get }
}

/// Pure grouping + filtering for the artist crate. No I/O, no view types.
enum CrateSection {

    /// The calendar every date in the catalog lives in. `Catalog.parseDate`
    /// reads performance dates with a UTC formatter, so a show on the 1st is an
    /// instant at 00:00 UTC. Bucketing or formatting it in the user's local zone
    /// slides it into the previous month — and, on New Year's Day, the previous
    /// year, which is what the old year-grouping quietly did with
    /// `Calendar.current`.
    static let catalogCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Lowercased, diacritic-folded, trimmed. Punctuation is deliberately kept:
    /// a date query like "06/28/26" has to survive normalization.
    static func normalized(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The haystack for one row. The nugs `venue` string already embeds city and
    /// state ("The Salt Shed, Chicago, IL"), so one field answers three queries.
    /// Both slashed date forms are folded in so "06/28/26" and "6/28/2026" match
    /// alongside the ISO "2026-06-28" the row actually displays.
    static func searchText(title: String, venue: String?, artistName: String,
                           dateText: String?, date: Date?) -> String {
        var parts = [title, venue ?? "", artistName, dateText ?? ""]
        if let date {
            parts.append(shortSlash.string(from: date))
            parts.append(longSlash.string(from: date))
        }
        return normalized(parts.joined(separator: " "))
    }

    /// First instant of the item's month — the section's identity.
    static func monthStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    /// Filter, then bucket by month: newest month first, newest item first
    /// within a month, undated items in a trailing `nil` section.
    static func sections<T: CrateSectionable>(
        _ items: [T], filter: String, calendar: Calendar
    ) -> [(month: Date?, items: [T])] {
        let needle = normalized(filter)
        let kept = needle.isEmpty ? items : items.filter { $0.searchText.contains(needle) }

        let grouped = Dictionary(grouping: kept) { item -> Date? in
            item.date.map { monthStart($0, calendar: calendar) }
        }

        return grouped
            .map { (month: $0.key,
                    items: $0.value.sorted {
                        ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
                    }) }
            .sorted { lhs, rhs in
                switch (lhs.month, rhs.month) {
                case let (l?, r?): return l > r
                case (nil, _):     return false   // undated sorts last
                case (_, nil):     return true
                }
            }
    }

    /// "June 2026", or "Unknown date" for the trailing undated section.
    ///
    /// Takes the same `calendar` that bucketed the section. A month start is an
    /// instant, so formatting it in a different time zone than it was computed
    /// in slides it across the boundary — June 1 00:00 UTC prints as "May 2026"
    /// anywhere west of Greenwich.
    static func monthTitle(_ month: Date?, calendar: Calendar, locale: Locale) -> String {
        guard let month else { return "Unknown date" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: month)
    }

    // Fixed-locale formatters: these feed the search haystack, not the UI, so
    // they must not shift with the user's locale.
    private static let shortSlash: DateFormatter = slash("MM/dd/yy")
    private static let longSlash: DateFormatter = slash("M/d/yyyy")

    private static func slash(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = catalogCalendar
        f.timeZone = catalogCalendar.timeZone   // UTC, matching Catalog.parseDate
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
