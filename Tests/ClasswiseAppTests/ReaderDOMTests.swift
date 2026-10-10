import Foundation
import WebKit
import XCTest
@testable import ClasswiseCore

/// Runs the production reader against real WebKit DOM/entity parsing, rather than a document stub.
final class ReaderDOMTests: XCTestCase {
    @MainActor
    private func read(cards: String) async throws -> RMPProfile {
        let store: [String: Any] = [
            "teacher": ["__typename": "Teacher", "legacyId": 123, "firstName": "Fictional", "lastName": "Instructor",
                        "school": ["__ref": "school"], "numRatings": 4, "avgRating": 4.5, "avgDifficulty": 2,
                        "ratings(first:5)": ["__ref": "connection"]],
            "school": ["__typename": "School", "legacyId": 2649, "name": "Pasadena City College"],
            "connection": ["edges": ["__refs": ["edge"]]],
            "edge": ["node": ["__ref": "rating"]],
            "rating": ["__typename": "Rating", "legacyId": 456, "class": "MATH005A",
                       "comment": "FICTIONAL: Clear &amp; helpful.\nWeekly practice.",
                       "date": "2026-06-01 00:00:00 +0000 UTC", "helpfulRating": 5, "difficultyRating": 2]
        ]
        let json = String(data: try JSONSerialization.data(withJSONObject: store), encoding: .utf8)!
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900), configuration: configuration)
        defer { webView.stopLoading() }
        let html = """
        <!doctype html><html><head><meta charset="utf-8"></head><body>
        \(cards)
        <script>window.__RELAY_STORE__ = \(json); window.fixtureReady = true;</script>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.ratemyprofessors.com/professor/123")!)
        let deadline = Date().addingTimeInterval(5)
        while (try? await webView.evaluateJavaScript("window.fixtureReady === true")) as? Bool != true {
            guard Date() < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(10))
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("Sources/Classwise/Resources/RMPReader.js"))
        let result = try await webView.evaluateJavaScript(script)
        let profiles = try JSONDecoder().decode([RMPProfile].self, from: Data(try XCTUnwrap(result as? String).utf8))
        return try XCTUnwrap(profiles.first)
    }

    private func card(comment: String, course: String = "MATH 005A", date: String = "Jun 1st, 2026", reviewID: String? = nil, professorID: String = "123", metrics: String = "") -> String {
        let flagLink = reviewID.map { "<a href=\"/flag/professor-rating/\(professorID)/\($0)\">Flag review</a>" } ?? ""
        return """
        <div class="Rating__RatingBody">
          <div class="RatingHeader__StyledClass">\(course)</div>
          <div class="RatingHeader__RatingTimeStamp">\(date)</div>
          <div class="Comments__StyledComments">\(comment)</div>
          \(flagLink)\(metrics)
        </div>
        """
    }

    @MainActor
    func testEncodedSourceAndVisibleDOMReviewAreCountedOnce() async throws {
        let profile = try await read(cards: card(comment: "FICTIONAL: Clear &amp; helpful.  Weekly practice."))
        XCTAssertEqual(profile.reviews.count, 1)
        XCTAssertEqual(profile.reviews[0].id, "456", "Retain the original source review identity")
        XCTAssertEqual(profile.reviews[0].text, "FICTIONAL: Clear & helpful.\nWeekly practice.", "Only HTML decoding changes the source wording")
    }

    @MainActor
    func testDistinctCommentOnSameCourseAndDateIsRetained() async throws {
        let cards = card(comment: "FICTIONAL: Clear &amp; helpful. Weekly practice.") +
            card(comment: "FICTIONAL: Clear &amp; helpful. Weekly quizzes.")
        let profile = try await read(cards: cards)
        XCTAssertEqual(profile.reviews.count, 2)
        XCTAssertTrue(profile.reviews.contains { $0.text == "FICTIONAL: Clear & helpful. Weekly quizzes." })
    }

    @MainActor
    func testIdenticalWordingOnDifferentCourseOrDateIsNotMerged() async throws {
        let comment = "FICTIONAL: Clear &amp; helpful. Weekly practice."
        let cards = card(comment: comment) + card(comment: comment, date: "Jun 2nd, 2026") +
            card(comment: comment, course: "MATH 005B")
        let profile = try await read(cards: cards)
        XCTAssertEqual(profile.reviews.count, 3)
        XCTAssertEqual(Set(profile.reviews.map(\.date)), ["2026-06-01", "2026-06-02"])
    }

    @MainActor
    func testPublicSourceIDMergesUTCAndVisiblePostedDateWithoutDuplicate() async throws {
        let metrics = """
        <div class="CardNumRating__StyledCardNumRating">Quality <span class="CardNumRating__CardNumRatingNumber">4</span></div>
        <div class="CardNumRating__StyledCardNumRating">Difficulty <span class="CardNumRating__CardNumRatingNumber">3</span></div>
        """
        let profile = try await read(cards: card(comment: "FICTIONAL: Clear &amp; helpful. Weekly practice.", date: "May 31st, 2026", reviewID: "456", metrics: metrics))
        XCTAssertEqual(profile.reviews.count, 1)
        let review = try XCTUnwrap(profile.reviews.first)
        XCTAssertEqual(review.id, "456")
        XCTAssertEqual(review.date, "2026-05-31", "The displayed posted date comes from the visible review card")
        XCTAssertEqual(review.text, "FICTIONAL: Clear & helpful. Weekly practice.")
        XCTAssertEqual(review.rating, 4)
        XCTAssertEqual(review.difficulty, 3)
    }

    @MainActor
    func testDistinctSourceIDsPreserveIdenticalCommentsOnSameDay() async throws {
        let comment = "FICTIONAL: Clear &amp; helpful. Weekly practice."
        let profile = try await read(cards: card(comment: comment, reviewID: "456") + card(comment: comment, reviewID: "789"))
        XCTAssertEqual(profile.reviews.count, 2)
        XCTAssertEqual(Set(profile.reviews.map(\.id)), ["456", "789"])
        XCTAssertEqual(Set(profile.reviews.map(\.text)).count, 1)
    }

    @MainActor
    func testFlagLinkForDifferentProfessorCannotReplaceSourceReview() async throws {
        let profile = try await read(cards: card(comment: "FICTIONAL: Clear &amp; helpful. Weekly practice.", date: "May 31st, 2026", reviewID: "456", professorID: "999"))
        XCTAssertEqual(profile.reviews.count, 1)
        XCTAssertEqual(profile.reviews.first?.date, "2026-06-01")
        XCTAssertEqual(profile.reviews.first?.id, "456")
    }
}
