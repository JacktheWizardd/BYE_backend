import XCTest
@testable import ClasswiseCore

/// BYE review loading against fixture responses shaped like the website's /api/reviews/* routes. No network.
final class ByeReviewTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock(); private var urls: [URL] = []
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
    }

    private func client(_ routes: @escaping @Sendable (String, [String: String]) -> (Int, String), recorder: Recorder = Recorder()) -> ByeReviewClient {
        ByeReviewClient(site: "https://bye.example/", fetch: { request in
            let url = try XCTUnwrap(request.url)
            recorder.add(url)
            XCTAssertEqual(request.httpMethod ?? "GET", "GET")
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query = Dictionary(uniqueKeysWithValues: (parts?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let (status, body) = routes(url.lastPathComponent, query)
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
    }

    private static func page(_ ids: Range<Int>, next: Int?) -> String {
        let items = ids.map { #"{"id":"r\#($0)","quality":4,"difficulty":2,"body":"Clear lectures.","date":"2026-10-1\#($0 % 10)T10:00:00.000Z","courseId":"1058","course":"MATH 005A"}"# }
        return #"{"data":{"reviews":[\#(items.joined(separator: ","))],"nextOffset":\#(next.map(String.init) ?? "null")}}"#
    }

    func testLoadsScoresAndEveryPage() async throws {
        let recorder = Recorder()
        let bye = client({ route, query in
            switch route {
            case "resolve": return (200, #"{"data":{"professor":{"id":"7","first_name":"Ada","last_name":"Byron"},"course":null,"match":"matched"}}"#)
            case "profile": return (200, #"{"data":{"professorId":"7","count":25,"quality":4.2,"difficulty":2.5,"courses":[]}}"#)
            default: return (200, query["offset"] == "0" ? Self.page(0..<20, next: 20) : Self.page(20..<25, next: nil))
            }
        }, recorder: recorder)
        let set = try await bye.load(instructor: "Ada Byron", course: try Course("MATH 5A"))
        XCTAssertTrue(set.matched)
        XCTAssertEqual(set.count, 25); XCTAssertEqual(set.quality, 4.2); XCTAssertNil(set.ratingIssue)
        XCTAssertEqual(set.reviews.count, 25); XCTAssertTrue(set.complete)
        XCTAssertEqual(set.reviews.first?.rating, 4)
        let resolve = try XCTUnwrap(recorder.all.first)
        XCTAssertEqual(resolve.path, "/api/reviews/resolve")
        XCTAssertTrue(resolve.query?.contains("instructor=Ada%20Byron") ?? false)
    }

    func testUnmatchedNameNeverGuesses() async throws {
        let recorder = Recorder()
        let bye = client({ _, _ in (200, #"{"data":{"professor":null,"course":null,"match":"ambiguous"}}"#) }, recorder: recorder)
        let set = try await bye.load(instructor: "Sam Lee", course: try Course("MATH 5A"))
        XCTAssertFalse(set.matched); XCTAssertTrue(set.reviews.isEmpty)
        XCTAssertEqual(recorder.all.count, 1, "No profile or list request without an exact match")
    }

    func testScoresOutageStillListsReviews() async throws {
        let bye = client({ route, _ in
            switch route {
            case "resolve": return (200, #"{"data":{"professor":{"id":"7"},"match":"matched"}}"#)
            case "profile": return (503, #"{"error":{"code":"AGGREGATION_LIMIT","message":"BYE ratings are temporarily unavailable. Review browsing remains available.","retryable":true}}"#)
            default: return (200, Self.page(0..<3, next: nil))
            }
        })
        let set = try await bye.load(instructor: "Ada Byron", course: try Course("MATH 5A"))
        XCTAssertEqual(set.reviews.count, 3); XCTAssertNil(set.quality)
        XCTAssertEqual(set.ratingIssue, "BYE ratings are temporarily unavailable. Review browsing remains available.")
    }

    func testServerMessageSurfacesOnFailure() async throws {
        let bye = client({ _, _ in (429, #"{"error":{"code":"RATE_LIMITED","message":"Too many requests. Try again in a minute.","retryable":true}}"#) })
        do { _ = try await bye.load(instructor: "Ada Byron", course: try Course("MATH 5A")); XCTFail("expected failure") }
        catch { XCTAssertEqual((error as? AppError)?.errorDescription, "Too many requests. Try again in a minute.") }
    }

    func testDownloadsStopAtTheLimit() async throws {
        let bye = client({ route, query in
            switch route {
            case "resolve": return (200, #"{"data":{"professor":{"id":"7"},"match":"matched"}}"#)
            case "profile": return (200, #"{"data":{"count":500,"quality":3,"difficulty":3}}"#)
            default: let offset = Int(query["offset"] ?? "0")!; return (200, Self.page(offset..<offset + 20, next: offset + 20))
            }
        })
        let set = try await bye.load(instructor: "Ada Byron", course: try Course("MATH 5A"))
        XCTAssertEqual(set.reviews.count, ByeReviewClient.reviewLimit); XCTAssertFalse(set.complete)
    }

    func testInsecureSitesAreRefused() async throws {
        let bye = ByeReviewClient(site: "http://bye.example", fetch: { _ in XCTFail("no request"); throw URLError(.badURL) })
        do { _ = try await bye.load(instructor: "Ada Byron", course: try Course("MATH 5A")); XCTFail("expected failure") }
        catch { XCTAssertEqual((error as? AppError)?.errorDescription, "BYE reviews are not configured.") }
    }

    func testCourseFilterMatchesPaddedBYECodes() throws {
        let course = try Course("MATH 5A")
        let reviews = [Review(id: "a", course: "MATH 005A", text: "", date: "", rating: 4, difficulty: 2, online: nil),
                       Review(id: "b", course: "PHYS 001A", text: "", date: "", rating: 3, difficulty: 3, online: nil)]
        XCTAssertEqual(ReviewFilter.thisCourse.byeReviews(reviews, course: course).map(\.id), ["a"])
        XCTAssertEqual(ReviewFilter.allCourses.byeReviews(reviews, course: course).count, 2)
        XCTAssertEqual(ReviewFilter.source("PHYS1A").byeReviews(reviews, course: course).map(\.id), ["b"])
    }

    func testBothListsBYEFirstAndHoldsRMPUntilBYEFinishes() {
        let bye = [Review(id: "b1", course: "", text: "", date: "2026-01-01", rating: 2, difficulty: nil, online: nil)]
        let rmp = [Review(id: "r1", course: "", text: "", date: "2026-05-01", rating: 5, difficulty: nil, online: nil)]
        XCTAssertEqual(Ordering.merged(bye: bye, rmp: rmp, source: .both, byeLoaded: false, by: .highest).map(\.id), ["bye|b1"])
        XCTAssertEqual(Ordering.merged(bye: bye, rmp: rmp, source: .both, byeLoaded: true, by: .highest).map(\.id), ["bye|b1", "rmp|r1"])
        XCTAssertEqual(Ordering.merged(bye: bye, rmp: rmp, source: .rmp, byeLoaded: false, by: .recent).map(\.id), ["rmp|r1"])
        XCTAssertEqual(Ordering.merged(bye: bye, rmp: rmp, source: .bye, byeLoaded: true, by: .recent).map(\.id), ["bye|b1"])
    }
}
