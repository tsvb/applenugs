import XCTest

final class CatalogArtistPagingTests: XCTestCase {

    private func next(_ offset: Int, _ received: Int, total: Int?, page: Int) -> Int? {
        Catalog.nextArtistPageOffset(after: offset, received: received, total: total, pageIndex: page)
    }

    /// The real catalog: 718 artists → offsets 0, 100, …, 700, then stop.
    func testWalksTheRealCatalogInEightPages() {
        var offsets: [Int] = []
        var offset: Int? = 0
        var page = 0
        while let current = offset {
            offsets.append(current)
            let received = min(Catalog.artistPageSize, 718 - current)
            offset = next(current, received, total: 718, page: page)
            page += 1
        }
        XCTAssertEqual(offsets, [0, 100, 200, 300, 400, 500, 600, 700])
    }

    /// A short page is the last one, whatever `total` says.
    func testShortPageStops() {
        XCTAssertNil(next(700, 18, total: 9999, page: 7))
        XCTAssertNil(next(0, 0, total: nil, page: 0))
    }

    /// Reaching `total` stops even on a full page.
    func testTotalReachedStops() {
        XCTAssertNil(next(100, 100, total: 200, page: 1))
        XCTAssertEqual(next(100, 100, total: 201, page: 1), 200)
    }

    /// No `total` in the response: keep going while pages are full.
    func testMissingTotalFollowsFullPages() {
        XCTAssertEqual(next(0, 100, total: nil, page: 0), 100)
    }

    /// A misreported total can't loop forever: the page cap ends the walk.
    func testPageCapEndsTheWalk() {
        XCTAssertEqual(next(1800, 100, total: 100_000, page: Catalog.maxArtistPages - 2), 1900)
        XCTAssertNil(next(1900, 100, total: 100_000, page: Catalog.maxArtistPages - 1))
    }
}
