import XCTest
@testable import ClasswiseCore

final class SharedProfileCacheTests: XCTestCase {
    private func profile() -> RMPProfile {
        RMPProfile(id: "42", firstName: "Fictional", lastName: "Instructor", school: "Pasadena City College", schoolID: 2649,
                   department: "Mathematics", rating: 4, difficulty: 2, ratingCount: 100, wouldTakeAgain: 90,
                   reviews: (0..<2).map { Review(id: "r\($0)", course: "MATH005A", text: "Original \($0)", date: "2026-01-01", rating: 4, difficulty: 2, online: nil) })
    }
    func testRawProfileReusedAcrossCoursesButSummaryDoesNotCrossCourse() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try Course("MATH005A"), b = try Course("MATH005B"), profile = profile(), now = Date()
        let summary = try SummaryBuilder.validate(Data("{\"positives\":[],\"concerns\":[]}".utf8), reviews: profile.reviews, course: a)
        ReportCache(directory: dir).save(CachedReport(profile: profile, summary: summary, checkedAt: now), name: profile.name, course: a)
        let restarted = ReportCache(directory: dir)
        XCTAssertEqual(restarted.load(name: profile.name, course: b)?.profile, profile)
        XCTAssertNil(restarted.load(name: profile.name, course: b)?.summary)
        XCTAssertEqual(restarted.load(name: profile.name, course: a)?.summary, summary)
        XCTAssertNil(restarted.load(name: profile.name, course: b, subject: "HIST"))
        XCTAssertEqual(restarted.load(name: profile.name, course: b, subject: "HIST", preferredProfileID: "42")?.profile, profile)
    }
    func testChangedReviewTextInvalidatesOtherCourseSummaryEvenWithSameIDs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ReportCache(directory: dir), a = try Course("MATH005A"), b = try Course("MATH005B")
        var profile = profile()
        let summary = try SummaryBuilder.validate(Data("{\"positives\":[],\"concerns\":[]}".utf8), reviews: profile.reviews, course: a)
        cache.save(CachedReport(profile: profile, summary: summary, checkedAt: Date()), name: profile.name, course: a)
        let original = profile.reviews[0]
        profile.reviews[0] = Review(id: original.id, course: original.course, text: "Changed source text", date: original.date, rating: 2, difficulty: 4, online: nil)
        cache.save(CachedReport(profile: profile, summary: nil, checkedAt: Date()), name: profile.name, course: b)
        XCTAssertNil(cache.load(name: profile.name, course: a)?.summary)
        XCTAssertEqual(cache.load(name: profile.name, course: a)?.profile.reviews.first?.text, "Changed source text")
    }
    func testSharedRawDataExpiryIsNotExtendedBySavingDetails() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ReportCache(directory: dir), course = try Course("MATH005A"), now = Date(), profile = profile()
        cache.save(CachedReport(profile: profile, summary: nil, checkedAt: now.addingTimeInterval(-86399)), name: profile.name, course: course)
        XCTAssertNotNil(cache.load(name: profile.name, course: course, now: now))
        XCTAssertNil(cache.load(name: profile.name, course: course, now: now.addingTimeInterval(2)))
        XCTAssertNil(cache.load(name: profile.name, course: course, now: now.addingTimeInterval(-86400)))
    }
    func testV3ContextAndReportRemainUntouchedAndAreMisses() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let course = try Course("MATH005A"), profile = profile()
        let key = "v3|fictional instructor|MATH005A|MATH"
        func file(_ value: String) -> URL { dir.appendingPathComponent(Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-") + ".json") }
        let index = try JSONEncoder().encode("42"), bytes = try JSONEncoder().encode(CachedReport(profile: profile, summary: nil, checkedAt: Date()))
        try index.write(to: file(key + "|index")); try bytes.write(to: file(key + "|profile|42"))
        XCTAssertNil(ReportCache(directory: dir).load(name: profile.name, course: course, preferredProfileID: "42"))
        XCTAssertEqual(try Data(contentsOf: file(key + "|index")), index)
        XCTAssertEqual(try Data(contentsOf: file(key + "|profile|42")), bytes)
    }
    func testReviewFiltersAreLocalPreserveLabelsAndCapEachFilter() throws {
        var profile = profile()
        profile.reviews = (0..<120).map { Review(id: "\($0)", course: $0 < 60 ? "MATH005A" : "MATH5B", text: "text", date: "2026-01-01", rating: 5, difficulty: 1, online: nil) }
        profile.reviewCoverage = ["all": ReviewCoverage(reviewIDs: (0..<50).map(String.init), nextCursor: "next", hasNextPage: true)]
        let course = try Course("MATH005A")
        XCTAssertEqual(ReviewFilter.thisCourse.reviews(in: profile, course: course).count, 50)
        XCTAssertEqual(ReviewFilter.source("MATH5B").reviews(in: profile, course: course).count, 50)
        XCTAssertEqual(Set(ReviewFilter.allCourses.reviews(in: profile, course: course).map(\.id)), Set((0..<50).map(String.init)))
        XCTAssertTrue(ReviewFilter.source("MATH005B").reviews(in: profile, course: course).isEmpty, "No shorthand guessing")
        XCTAssertEqual(ReviewFilter.source("MATH5B").requestLabel(course: course), "MATH5B")
        XCTAssertEqual(profile.rating, 4); XCTAssertEqual(profile.difficulty, 2)
    }
}
