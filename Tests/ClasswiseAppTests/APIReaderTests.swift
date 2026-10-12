import XCTest
import Foundation
import BYEAPI
@testable import Classwise
@testable import ClasswiseCore

@MainActor
final class APIReaderTests: XCTestCase {
    private let professor = Professor(id: "p", name: "Fictional Instructor", sections: [])
    private func reader(_ handler: @escaping ([String: Any], Int) throws -> [String: Any]) -> RMPAPIReader {
        ReaderAPIProtocol.calls = []; ReaderAPIProtocol.handler = handler
        return RMPAPIReader(client: RMPClient(transport: RMPTransport(protocolClasses: [ReaderAPIProtocol.self], spacing: 0, retryDelay: 0)))
    }
    private nonisolated func node(_ id: Int = 42, lastName: String = "Instructor", school: Int = 2649) -> [String: Any] {
        ["id": Data("Teacher-\(id)".utf8).base64EncodedString(), "legacyId": id, "firstName": "Fictional", "lastName": lastName,
         "department": id == 42 ? "Mathematics" : "History", "avgRating": 4.5, "avgDifficulty": 2,
         "numRatings": 100, "school": ["legacyId": school, "name": school == 2649 ? "Pasadena City College" : "Other School"],
         "courseCodes": [["courseName": "MATH005A", "courseCount": 50], ["courseName": "MATH005B", "courseCount": 50]]]
    }
    private nonisolated func search(_ nodes: [[String: Any]], next: String? = nil) -> [String: Any] {
        ["data": ["search": ["teachers": ["edges": nodes.map { ["node": $0] }, "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any? ?? NSNull()]]]]]
    }
    private nonisolated func page(vars: [String: Any], node: [String: Any]? = nil, total: Int = 100, idPrefix: String? = nil) -> [String: Any] {
        var profile = node ?? self.node()
        let offset = (vars["cursor"] as? String).flatMap(Int.init) ?? 0
        let count = min(vars["count"] as? Int ?? 3, max(0, total - offset))
        let filter = vars["courseFilter"] as? String
        profile["ratings"] = ["edges": (offset..<(offset + count)).map { index in
            ["node": ["id": "\(idPrefix ?? filter ?? "all")-\(index)", "class": filter ?? "MATH005A", "comment": "Original \(index)", "date": "2026-01-01", "helpfulRating": 4, "difficultyRating": 2]]
        }, "pageInfo": ["hasNextPage": offset + count < total, "endCursor": "\(offset + count)"]]
        return ["data": ["node": profile]]
    }
    func testSingleDuplicateCandidateVerifiesOnceAndMultipleDepartmentsRequireChoice() async throws {
        var reader = reader { vars, _ in vars["query"] != nil ? self.search([self.node(), self.node()]) : self.page(vars: vars) }
        guard case .verified(let profile) = try await reader.lookupOutcome(professor) else { return XCTFail("Expected verified") }
        XCTAssertEqual(profile.id, "42"); XCTAssertEqual(profile.reviews.count, 3)
        XCTAssertEqual(ReaderAPIProtocol.calls.count, 2)
        reader = self.reader { _, _ in self.search([self.node(), self.node(43)]) }
        guard case .selectionRequired(let choices, _) = try await reader.lookupOutcome(professor) else { return XCTFail("Expected choice") }
        XCTAssertEqual(choices.count, 2); XCTAssertEqual(ReaderAPIProtocol.calls.count, 1)
    }
    func testWrongSchoolsAreExcludedAndCompoundSurnameStillMatches() async throws {
        let reader = reader { vars, _ in
            if vars["query"] != nil { return self.search([self.node(school: 99), self.node(lastName: "Instructor/Other")]) }
            return self.page(vars: vars, node: self.node(lastName: "Instructor/Other"))
        }
        let compound = Professor(id: "p", name: "Fictional Instructor Other", sections: [])
        guard case .verified(let profile) = try await reader.lookupOutcome(compound) else { return XCTFail("Expected compound verification") }
        XCTAssertEqual(profile.schoolID, 2649)
    }
    func testProfilePayloadMustReverifySchoolAndName() async throws {
        for bad in [node(school: 99), node(lastName: "Different")] {
            let reader = reader { vars, _ in vars["query"] != nil ? self.search([self.node()]) : self.page(vars: vars, node: bad) }
            guard case .selectionRequired = try await reader.lookupOutcome(professor) else { return XCTFail("Expected re-selection") }
        }
    }
    func testAdditionalSearchPagesOnlyWhenNeededAndBoundedToThree() async throws {
        var reader = reader { vars, _ in
            if vars["query"] != nil { return vars["cursor"] == nil ? self.search([], next: "next") : self.search([self.node()]) }
            return self.page(vars: vars)
        }
        guard case .verified = try await reader.lookupOutcome(professor) else { return XCTFail("Expected later match") }
        XCTAssertEqual(ReaderAPIProtocol.calls.count, 3)
        reader = self.reader { _, index in self.search([], next: "\(index)") }
        let candidates = try await reader.candidates(professor, discoverAll: false)
        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(ReaderAPIProtocol.calls.count, 4)
    }
    func testDiscoveryRetainsCandidatesAfterLaterPageFailure() async throws {
        let reader = reader { _, index in
            if index == 0 { return self.search([self.node(), self.node(43)], next: "next") }
            throw URLError(.timedOut)
        }
        let candidates = try await reader.candidates(professor, discoverAll: true)
        XCTAssertEqual(Set(candidates.map(\.id)), ["42", "43"])
        XCTAssertEqual(ReaderAPIProtocol.calls.count, 4, "One initial page plus bounded retries of next page")
    }
    func testAllCourseExpansionCapsAt50AndExplicitFilterCanAddSeparate50() async throws {
        let reader = reader { vars, _ in self.page(vars: vars) }
        let preview = try await reader.preview(professor, profileID: "42")
        var progress: [Int] = []
        let all = try await reader.expand(professor, profile: preview) { progress.append($0.reviews.count) }
        XCTAssertEqual(all.reviews.count, 50); XCTAssertEqual(progress, [23, 43, 50])
        XCTAssertTrue(ReaderAPIProtocol.calls.allSatisfy { $0["courseFilter"] == nil })
        let expanded = try await reader.expand(professor, profile: all, courseFilter: "MATH005B") { _ in }
        XCTAssertEqual(expanded.reviews.count, 100)
        XCTAssertEqual(expanded.reviewCoverage?["course|MATH005B"]?.reviewIDs.count, 50)
        XCTAssertEqual(expanded.reviewCoverage?["all"]?.reviewIDs.count, 50)
        XCTAssertEqual(expanded.rating, all.rating); XCTAssertEqual(expanded.id, all.id)
        let before = ReaderAPIProtocol.calls.count
        _ = try await reader.expand(professor, profile: expanded, courseFilter: "MATH005B") { _ in XCTFail("Already complete") }
        XCTAssertEqual(before, ReaderAPIProtocol.calls.count)
    }
    func testLaterReviewFailurePreservesPartialCoverageForRetry() async throws {
        let reader = reader { vars, index in
            if index >= 2 { throw URLError(.timedOut) }
            return self.page(vars: vars)
        }
        let preview = try await reader.preview(professor, profileID: "42")
        var partial = preview
        do { _ = try await reader.expand(professor, profile: preview) { partial = $0 }; XCTFail("Expected failure") }
        catch { XCTAssertEqual(partial.reviews.count, 23); XCTAssertEqual(partial.reviewCoverage?["all"]?.nextCursor, "23") }
        ReaderAPIProtocol.handler = { vars, _ in self.page(vars: vars) }
        let full = try await reader.expand(professor, profile: partial) { _ in }
        XCTAssertEqual(full.reviews.count, 50)
        XCTAssertEqual(Set(full.reviews.map(\.id)).count, 50)
    }
    func testStoppingExpansionPreservesPublishedPageAndPreventsNextRequest() async throws {
        let reader = reader { vars, _ in self.page(vars: vars) }
        let preview = try await reader.preview(professor, profileID: "42")
        var partial = preview
        do {
            _ = try await reader.expand(professor, profile: preview) { partial = $0; reader.stop() }
            XCTFail("Stopped generation must cancel")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(partial.reviews.count, 23)
        XCTAssertEqual(ReaderAPIProtocol.calls.count, 2)
    }
    func testEmptyContinuingPageStopsWithoutDiscardingPriorReviews() async throws {
        let reader = reader { vars, index in
            if index == 0 { return self.page(vars: vars) }
            var node = self.node(); node["ratings"] = ["edges": [], "pageInfo": ["hasNextPage": true, "endCursor": "new"]]
            return ["data": ["node": node]]
        }
        let preview = try await reader.preview(professor, profileID: "42")
        do { _ = try await reader.expand(professor, profile: preview) { _ in XCTFail("No progress") }; XCTFail("Must fail") }
        catch { XCTAssertEqual(error as? RMPAPIError, .pagination) }
        XCTAssertEqual(preview.reviews.count, 3); XCTAssertEqual(ReaderAPIProtocol.calls.count, 2)
    }

    private func matchingPreview(_ reader: RMPAPIReader, labels: [String]) async throws -> RMPProfile {
        var profile = try await reader.preview(professor, profileID: "42")
        profile.reviews = []
        profile.courseCounts = labels.map { ReviewCourseCount(label: $0, count: nil) }
        return profile
    }

    func testMatchingRetrievalRequestsRawEquivalentLabelsAndSharesFiftyRatingLimit() async throws {
        let labels = ["MATH 05A", "math5a", "MATH5A5B", "MATH15A", "5A"]
        let reader = reader { vars, _ in
            var node = self.node(); node["courseCodes"] = labels.map { ["courseName": $0, "courseCount": 40] }
            return self.page(vars: vars, node: node, total: 40)
        }
        let profile = try await matchingPreview(reader, labels: labels)
        let course = try Course("MATH005A")
        let full = try await reader.expand(professor, profile: profile, matching: course) { _ in }
        XCTAssertEqual(full.reviews.count, 50)
        XCTAssertEqual(ReviewFilter.thisCourse.retrievedIDs(in: full, course: course).count, 50)
        XCTAssertTrue(ReviewFilter.thisCourse.finished(in: full, course: course))
        XCTAssertEqual(ReaderAPIProtocol.calls.dropFirst().compactMap { $0["courseFilter"] as? String }, ["MATH 05A", "MATH 05A", "math5a"])
        XCTAssertEqual(ReaderAPIProtocol.calls.last?["count"] as? Int, 10)
        XCTAssertEqual(full.reviewCoverage?["course|math5a"]?.hasNextPage, true, "Combined cap must not falsely exhaust source coverage")
        let count = ReaderAPIProtocol.calls.count
        _ = try await reader.expand(professor, profile: full, matching: course) { _ in XCTFail("Already capped") }
        XCTAssertEqual(ReaderAPIProtocol.calls.count, count)
    }

    func testMatchingRetrievalDeduplicatesIDsAndPreservesOverallCoverage() async throws {
        let reader = reader { vars, _ in
            var node = self.node(); node["courseCodes"] = NSNull()
            return self.page(vars: vars, node: node, total: vars["courseFilter"] as? String == "MATH 5A" ? 10 : 20, idPrefix: "shared")
        }
        let profile = try await matchingPreview(reader, labels: ["MATH 5A", "MATH05A"])
        let course = try Course("MATH005A")
        let full = try await reader.expand(professor, profile: profile, matching: course) { _ in }
        XCTAssertEqual(full.reviews.count, 20)
        XCTAssertEqual(ReviewFilter.thisCourse.retrievedIDs(in: full, course: course).count, 20)
        XCTAssertTrue(ReviewFilter.thisCourse.finished(in: full, course: course))
        XCTAssertEqual(full.reviewCoverage?["all"], profile.reviewCoverage?["all"])
        XCTAssertEqual(Set(full.courseCounts?.map(\.label) ?? []), ["MATH 5A", "MATH05A"])
        XCTAssertEqual(full.rating, profile.rating)
    }

    func testMatchingFailureRetrySkipsFinishedLabelAndResumesCursor() async throws {
        var failing = true
        let reader = reader { vars, _ in
            if failing, vars["courseFilter"] as? String == "math5a", vars["cursor"] as? String == "20" { throw URLError(.timedOut) }
            var node = self.node(); node["courseCodes"] = NSNull()
            return self.page(vars: vars, node: node, total: vars["courseFilter"] as? String == "MATH 5A" ? 5 : 30)
        }
        let profile = try await matchingPreview(reader, labels: ["MATH 5A", "math5a"])
        let course = try Course("MATH005A")
        var partial = profile
        do {
            _ = try await reader.expand(professor, profile: profile, matching: course) { partial = $0 }
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(partial.reviews.count, 25)
            XCTAssertEqual(partial.reviewCoverage?["course|math5a"]?.nextCursor, "20")
            XCTAssertFalse(ReviewFilter.thisCourse.finished(in: partial, course: course))
        }
        failing = false
        let before = ReaderAPIProtocol.calls.count
        let full = try await reader.expand(professor, profile: partial, matching: course) { _ in }
        XCTAssertEqual(full.reviews.count, 35)
        XCTAssertEqual(ReaderAPIProtocol.calls.count, before + 1)
        XCTAssertEqual(ReaderAPIProtocol.calls.last?["cursor"] as? String, "20")
        XCTAssertTrue(ReviewFilter.thisCourse.finished(in: full, course: course))
    }

    func testMatchingRetrievalContinuesAfterCrossLabelDuplicatesLeaveBudget() async throws {
        let reader = reader { vars, _ in
            var node = self.node(); node["courseCodes"] = NSNull()
            return self.page(vars: vars, node: node, total: vars["courseFilter"] as? String == "MATH 5A" ? 10 : 100, idPrefix: "shared")
        }
        let profile = try await matchingPreview(reader, labels: ["MATH 5A", "math5a"])
        let course = try Course("MATH005A")
        let full = try await reader.expand(professor, profile: profile, matching: course) { _ in }
        XCTAssertEqual(full.reviews.count, 50)
        XCTAssertEqual(ReviewFilter.thisCourse.retrievedIDs(in: full, course: course).count, 50)
        XCTAssertEqual(ReaderAPIProtocol.calls.last?["cursor"] as? String, "40")
        XCTAssertEqual(ReaderAPIProtocol.calls.last?["count"] as? Int, 10)
    }

    func testMatchingRetrievalFallbackAndEmptyCompletedLabels() async throws {
        let reader = reader { vars, _ in
            var node = self.node(); node["courseCodes"] = NSNull()
            return self.page(vars: vars, node: node, total: 0)
        }
        let profile = try await matchingPreview(reader, labels: ["MATH5A5B"])
        let course = try Course("MATH005A")
        let full = try await reader.expand(professor, profile: profile, matching: course) { _ in }
        XCTAssertEqual(ReaderAPIProtocol.calls.last?["courseFilter"] as? String, "MATH005A")
        XCTAssertTrue(ReviewFilter.thisCourse.finished(in: full, course: course))
    }

    func testMatchingRetrievalStopsBeforeNextLabel() async throws {
        let reader = reader { vars, _ in
            var node = self.node(); node["courseCodes"] = NSNull()
            return self.page(vars: vars, node: node, total: 2)
        }
        let profile = try await matchingPreview(reader, labels: ["MATH 5A", "math5a"])
        var partial = profile
        do {
            _ = try await reader.expand(professor, profile: profile, matching: try Course("MATH005A")) { partial = $0; reader.stop() }
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(partial.reviews.count, 2)
        XCTAssertEqual(ReaderAPIProtocol.calls.count, 2)
    }

    func testMatchingRetrievalReverifiesEveryLabel() async throws {
        let reader = reader { vars, _ in
            var node = self.node(lastName: vars["courseFilter"] as? String == "math5a" ? "Wrong" : "Instructor")
            node["courseCodes"] = NSNull()
            return self.page(vars: vars, node: node, total: 2)
        }
        let profile = try await matchingPreview(reader, labels: ["MATH 5A", "math5a"])
        var partial = profile
        do {
            _ = try await reader.expand(professor, profile: profile, matching: try Course("MATH005A")) { partial = $0 }
            XCTFail("Expected identity failure")
        } catch { XCTAssertTrue(error is ProfileIdentityMismatch) }
        XCTAssertEqual(partial.reviews.count, 2)
        XCTAssertTrue(partial.reviews.allSatisfy { $0.course == "MATH 5A" })
    }
    func testCourseCountMergeKeepsFirstSeenOrderAndLatestCount() {
        let first = ["MATH005B", "MATH005A", "MATH 5A"].map { ReviewCourseCount(label: $0, count: 1) }
        let page = [ReviewCourseCount(label: "MATH005A", count: 9), ReviewCourseCount(label: "MATH05A", count: 2)]
        let merged = RMPAPIReader.mergeCourseCounts(first, page)
        XCTAssertEqual(merged?.map(\.label), ["MATH005B", "MATH005A", "MATH 5A", "MATH05A"])
        XCTAssertEqual(merged?.first { $0.label == "MATH005A" }?.count, 9)
        XCTAssertEqual(RMPAPIReader.mergeCourseCounts(first, nil), first, "A page without metadata keeps known labels")
        XCTAssertEqual(RMPAPIReader.mergeCourseCounts(nil, page), page)
    }
}

private final class ReaderAPIProtocol: URLProtocol {
    private static let lock = NSLock()
    static var calls: [[String: Any]] = []
    static var handler: (([String: Any], Int) throws -> [String: Any])!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var bytes = request.httpBody ?? Data()
            if bytes.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(contentsOf: buffer.prefix(n)) }
            }
            let body = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            let vars = body["variables"] as! [String: Any]
            Self.lock.lock(); let index = Self.calls.count; Self.calls.append(vars); Self.lock.unlock()
            let result = try Self.handler(vars, index)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: result)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
