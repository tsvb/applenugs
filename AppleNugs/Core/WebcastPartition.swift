import Foundation

/// The slice of a webcast the schedule partition needs — protocol'd so the
/// pure logic tests without dragging the catalog models in.
protocol WebcastLike {
    var isLive: Bool { get }
    var eventStart: Date? { get }
}

/// Split a livestream feed (queried from a couple of weeks back) into the
/// two rails the Videos page shows:
/// - `upcoming`: currently live first, then scheduled events soonest-first.
///   Undated items stay here — before the partition existed the whole feed
///   showed under Live & Upcoming, and an item we can't date shouldn't be
///   presented as "recent".
/// - `recent`: already-started, no-longer-live events ("last chance"
///   replays), newest first.
func partitionWebcasts<V: WebcastLike>(_ items: [V], now: Date)
    -> (upcoming: [V], recent: [V]) {
    var upcoming: [V] = []
    var recent: [V] = []
    for item in items {
        if item.isLive || (item.eventStart ?? .distantFuture) >= now {
            upcoming.append(item)
        } else {
            recent.append(item)
        }
    }
    upcoming.sort {
        if $0.isLive != $1.isLive { return $0.isLive }
        return ($0.eventStart ?? .distantFuture) < ($1.eventStart ?? .distantFuture)
    }
    recent.sort {
        ($0.eventStart ?? .distantPast) > ($1.eventStart ?? .distantPast)
    }
    return (upcoming, recent)
}
