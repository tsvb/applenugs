import XCTest

final class CatalogArtistAvatarsTests: XCTestCase {

    private func parse(_ items: String) -> [String: URL] {
        let data = #"{"offset":0,"limit":9,"total":2,"items":["#.appending(items).appending("]}").data(using: .utf8)!
        return Catalog.artistAvatars(from: JSON.parse(data))
    }

    /// The real v1 shape (trimmed): id → the avatar's redirecting URL.
    func testMapsIdToAvatarURL() {
        let avatars = parse(#"""
        {"id":"1205","name":"Goose","abbreviation":"goo",
         "avatarImage":{"id":null,"url":"https://catalog.nugs.net/api/v1/artists/1205/images/avatar/8a5a8811"},
         "coverImage":{"id":null,"url":"https://catalog.nugs.net/api/v1/artists/1205/images/cover/a54e"}},
        {"id":"101","name":"Lotus",
         "avatarImage":{"id":null,"url":"https://catalog.nugs.net/api/v1/artists/101/images/avatar/0e8a"}}
        """#)
        XCTAssertEqual(avatars.count, 2)
        XCTAssertEqual(avatars["1205"]?.absoluteString,
                       "https://catalog.nugs.net/api/v1/artists/1205/images/avatar/8a5a8811")
        XCTAssertEqual(avatars["101"]?.lastPathComponent, "0e8a")
    }

    /// The avatar, never the wide cover image.
    func testIgnoresCoverImage() {
        let avatars = parse(#"""
        {"id":"7","name":"Cover Only","coverImage":{"url":"https://x/cover.jpg"}}
        """#)
        XCTAssertTrue(avatars.isEmpty)
    }

    /// Missing ids, missing or empty urls and non-http urls fall back to the
    /// monogram (no entry) instead of a broken image.
    func testSkipsUnusableEntries() {
        let avatars = parse(#"""
        {"name":"No Id","avatarImage":{"url":"https://x/a.jpg"}},
        {"id":"2","name":"Null Url","avatarImage":{"id":null,"url":null}},
        {"id":"3","name":"Empty Url","avatarImage":{"url":""}},
        {"id":"4","name":"Relative","avatarImage":{"url":"/images/a.jpg"}},
        {"id":"5","name":"Good","avatarImage":{"url":"https://x/5.jpg"}}
        """#)
        XCTAssertEqual(Array(avatars.keys), ["5"])
    }

    func testEmptyOrMalformedResponse() {
        XCTAssertTrue(Catalog.artistAvatars(from: JSON.parse(Data("{}".utf8))).isEmpty)
        XCTAssertTrue(Catalog.artistAvatars(from: JSON.parse(Data("not json".utf8))).isEmpty)
    }
}
