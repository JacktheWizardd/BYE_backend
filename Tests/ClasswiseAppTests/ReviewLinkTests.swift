import XCTest
import ClasswiseCore
@testable import Classwise

final class ReviewLinkTests: XCTestCase {
    func testBuildsPrefilledReviewURL() throws {
        let url = ReviewLink.url(professor: "Jane Doe", course: try Course("math 5a"), site: "https://example.dev")
        XCTAssertEqual(url?.absoluteString, "https://example.dev/reviews/?professor=Jane%20Doe&course=MATH%205A")
        let padded = ReviewLink.url(professor: "Jane Doe", course: try Course("MATH 005A"), site: "https://example.dev/")
        XCTAssertEqual(padded?.absoluteString, "https://example.dev/reviews/?professor=Jane%20Doe&course=MATH%20005A")
    }

    func testEncodesReservedCharacters() throws {
        let url = try XCTUnwrap(ReviewLink.url(professor: "Núñez, A&B = C+D #1", course: try Course("ETH 014"), site: "https://example.dev"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first { $0.name == "professor" }?.value, "Núñez, A&B = C+D #1")
        XCTAssertEqual(items?.first { $0.name == "course" }?.value, "ETH 014")
        XCTAssertTrue(url.absoluteString.contains("C%2BD"))
        XCTAssertFalse(url.absoluteString.contains("#"))
    }

    func testBlankNameHasNoLink() throws {
        XCTAssertNil(ReviewLink.url(professor: "  ", course: try Course("ETH 014"), site: "https://example.dev"))
    }

    func testSiteFallsBackWhenKeyIsMissing() {
        XCTAssertEqual(ReviewLink.site(info: nil), ReviewLink.defaultSite)
        XCTAssertEqual(ReviewLink.site(info: ["BYEWebsiteURL": " "]), ReviewLink.defaultSite)
        XCTAssertEqual(ReviewLink.site(info: ["BYEWebsiteURL": "https://example.dev"]), "https://example.dev")
    }
}
