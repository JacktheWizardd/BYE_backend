import XCTest
import JavaScriptCore
@testable import ClasswiseCore

final class ReaderTests: XCTestCase {
    private func run(store: [String: Any], path: String) throws -> [RMPProfile] {
        let context = JSContext()!
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        let json = String(data: try JSONSerialization.data(withJSONObject: store), encoding: .utf8)!
        context.evaluateScript("var window = {__RELAY_STORE__: \(json)}; var location = {pathname:'\(path)'}; var document = {querySelectorAll: () => []};")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("Sources/Classwise/Resources/RMPReader.js"))
        let result = context.evaluateScript(script)?.toString()
        XCTAssertNil(exception, exception ?? "")
        return try JSONDecoder().decode([RMPProfile].self, from: Data(try XCTUnwrap(result).utf8))
    }
    private var store: [String: Any] {
        ["teacher": ["__typename":"Teacher", "legacyId":123, "firstName":"Test", "lastName":"Person", "school":["__ref":"school"], "numRatings":18, "avgRating":4.8, "avgDifficulty":2.1, "wouldTakeAgainPercent":-1, "ratings(first:5)":["__ref":"connection"]],
         "school": ["__typename":"School", "legacyId":2649, "name":"Pasadena City College"],
         "connection": ["edges":["__refs":["edge"]]], "edge":["node":["__ref":"rating"]],
         "rating": ["__typename":"Rating", "legacyId":456, "comment":"Fictional fixture: clear lectures.", "class":"ETH014", "date":"2026-06-01 00:00:00 +0000 UTC", "helpfulRating":5, "difficultyRating":1, "isForOnlineClass":true],
         "unrelatedRating": ["__typename":"Rating", "legacyId":999, "comment":"Must not appear in this teacher's connection."]]
    }
    func testReadsPublicPageFieldsAndOnlyOwnedRatings() throws {
        let profiles = try run(store: store, path: "/professor/123")
        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profile.rating, 4.8); XCTAssertEqual(profile.difficulty, 2.1)
        XCTAssertEqual(profile.ratingCount, 18) // Source header, not a derived distribution count.
        XCTAssertNil(profile.wouldTakeAgain) // -1 means unavailable, not negative feedback.
        XCTAssertEqual(profile.reviews.count, 1); XCTAssertEqual(profile.reviews[0].id, "456")
        XCTAssertEqual(profile.reviews[0].date, "2026-06-01")
    }
    func testEmptyOrBlockedPageProducesNoProfiles() throws {
        XCTAssertTrue(try run(store: [:], path: "/professor/123").isEmpty)
    }
    func testSearchPageDoesNotLeakReviewDataIntoCandidates() throws {
        let profiles = try run(store: store, path: "/search/professors/2649")
        XCTAssertEqual(profiles.count, 1); XCTAssertTrue(profiles[0].reviews.isEmpty)
    }
    func testNoRatingsMeansUnknownNotZeroScore() throws {
        var data = store
        var teacher = data["teacher"] as! [String: Any]; teacher["numRatings"] = 0; teacher["avgRating"] = 0; teacher["avgDifficulty"] = 0
        data["teacher"] = teacher
        let profile = try XCTUnwrap(try run(store: data, path: "/professor/123").first)
        XCTAssertNil(profile.rating); XCTAssertNil(profile.difficulty)
    }
}
