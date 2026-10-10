import XCTest
@testable import Classwise
@testable import ClasswiseCore

@MainActor
final class CourseQueueTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < end else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private func fixture(_ directory: URL) throws -> (AppModel, CourseQueueHub) {
        let hub = CourseQueueHub()
        let model = AppModel(cache: ReportCache(directory: directory), choices: ProfileChoiceStore(directory: directory), makeReader: { CourseQueueReader(hub) })
        model.course = try Course("MATH005A"); model.showingResults = true
        let section = Section(crn: "1", title: "Fictional", start: "", end: "", formats: ["OD"], meetings: [], status: "O")
        var professor = Professor(id: "p", name: "Fictional Instructor", sections: [section])
        professor.subjectCode = "MATH"
        professor.profile = RMPProfile(id: "42", firstName: "Fictional", lastName: "Instructor", school: "Pasadena City College", schoolID: 2649, department: "Math", rating: 4, difficulty: 2, ratingCount: 10, wouldTakeAgain: nil, reviews: [], courseCounts: [ReviewCourseCount(label: "MATH005B", count: 10)])
        professor.state = .ready; professor.reviewsComplete = true
        model.professors = [professor]; model.selectedID = "p"
        return (model, hub)
    }
    func testLocalFiltersDoNotRequestAndExplicitRepeatedActionUsesOneDetailJob() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, hub) = try fixture(directory); defer { model.cancel() }
        _ = ReviewFilter.source("MATH005B").reviews(in: model.professors[0].profile!, course: model.course!)
        XCTAssertTrue(hub.filters.isEmpty)
        model.busy = true; model.findMoreReviews(id: "p", filter: .source("MATH005B"))
        await Task.yield(); XCTAssertTrue(hub.filters.isEmpty)
        model.busy = false
        model.findMoreReviews(id: "p", filter: .source("unknown"))
        await Task.yield(); XCTAssertTrue(hub.filters.isEmpty)
        for _ in 0..<5 { model.findMoreReviews(id: "p", filter: .source("MATH005B")) }
        try await wait { hub.continuation != nil }
        XCTAssertEqual(hub.filters, ["MATH005B"])
        for _ in 0..<5 { model.findMoreReviews(id: "p", filter: .source("MATH005B")) }
        var full = model.professors[0].profile!
        full.reviews = [Review(id: "new", course: "MATH005B", text: "Fictional source", date: "2026-01-01", rating: 4, difficulty: 2, online: nil)]
        full.reviewCoverage = ["course|MATH005B": ReviewCoverage(reviewIDs: ["new"], nextCursor: nil, hasNextPage: false)]
        model.selectedID = nil
        hub.continuation!.resume(returning: full); hub.continuation = nil
        try await wait { model.loadingDetailsID == nil }
        model.findMoreReviews(id: "p", filter: .source("MATH005B"))
        await Task.yield()
        XCTAssertEqual(hub.filters.count, 1)
        XCTAssertEqual(model.professors[0].profile?.rating, 4)
        let cached = ReportCache(directory: directory).load(name: "Fictional Instructor", course: try Course("MATH005C"))
        XCTAssertEqual(cached?.profile.reviews.first?.id, "new")
    }
    func testExplicitFilterFailureRetainsPublishedPartialDataAndRetryResumesIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, hub) = try fixture(directory); defer { model.cancel() }
        model.findMoreReviews(id: "p", filter: .source("MATH005B"))
        try await wait { hub.continuation != nil }
        var partial = model.professors[0].profile!
        partial.reviews = [Review(id: "one", course: "MATH005B", text: "Retained fictional review", date: "", rating: 4, difficulty: 2, online: nil)]
        partial.reviewCoverage = ["course|MATH005B": ReviewCoverage(reviewIDs: ["one"], nextCursor: "cursor", hasNextPage: true)]
        hub.callback?(partial); model.selectedID = nil
        hub.continuation!.resume(throwing: URLError(.timedOut)); hub.continuation = nil
        try await wait { model.loadingDetailsID == nil }
        XCTAssertEqual(model.professors[0].profile?.reviews.count, 1)
        XCTAssertNotNil(model.courseReviewIssues["p|MATH005B"])
        model.findMoreReviews(id: "p", filter: .source("MATH005B"))
        try await wait { hub.continuation != nil }
        XCTAssertEqual(hub.inputs.last?.reviewCoverage?["course|MATH005B"]?.nextCursor, "cursor")
        model.selectedID = nil
        hub.continuation!.resume(returning: partial); hub.continuation = nil
        try await wait { model.loadingDetailsID == nil }
        XCTAssertNil(model.courseReviewIssues["p|MATH005B"])
    }
}

@MainActor
private final class CourseQueueHub {
    var filters: [String] = []
    var inputs: [RMPProfile] = []
    var continuation: CheckedContinuation<RMPProfile, Error>?
    var callback: ((RMPProfile) -> Void)?
}
@MainActor
private final class CourseQueueReader: CourseProfileReader {
    let hub: CourseQueueHub
    init(_ hub: CourseQueueHub) { self.hub = hub }
    func stop() { }
    func candidates(_ professor: Professor, discoverAll: Bool) async throws -> [RMPProfile] { [] }
    func preview(_ professor: Professor, profileID: String) async throws -> RMPProfile { throw URLError(.unsupportedURL) }
    func expand(_ professor: Professor, profile: RMPProfile, onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile { profile }
    func expand(_ professor: Professor, profile: RMPProfile, courseFilter: String?, onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile {
        hub.filters.append(courseFilter ?? "all"); hub.inputs.append(profile)
        // Preserve the real callback for partial-result publication tests.
        return try await withoutActuallyEscaping(onProfile) { callback in
            hub.callback = callback
            defer { hub.callback = nil }
            return try await withCheckedThrowingContinuation { hub.continuation = $0 }
        }
    }
}
