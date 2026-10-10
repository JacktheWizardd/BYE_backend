import XCTest
@testable import ClasswiseCore

final class AppleSummaryCacheTests: XCTestCase {
    func testCorroborationRejectsUnsharedDetailsAndSentimentReversals() {
        func sources(_ a: String, _ b: String) -> [Review] {
            [a, b].enumerated().map { Review(id: "r\($0.offset)", course: "MATH005A", text: $0.element,
                date: "2026-01-01", rating: nil, difficulty: nil, online: nil) }
        }
        func check(_ text: String, _ a: String, _ b: String, concern: Bool = false) -> Bool {
            SummaryEvidence.corroborated(SummaryPoint(text: text, reviewIDs: ["r0", "r1"]), reviews: sources(a, b), concern: concern)
        }
        XCTAssertTrue(check("Clear explanations", "Clear explanations helped.", "The explanations were clear."))
        XCTAssertFalse(check("Clear lectures and caring teaching", "Clear lectures.", "Clear lectures and caring teaching."))
        XCTAssertFalse(check("Exams were difficult", "Excessive homework.", "Exams were difficult.", concern: true))
        XCTAssertFalse(check("Difficult exams", "Difficult exams.", "Difficult exams."))
        XCTAssertTrue(check("Difficult exams", "Difficult exams.", "Difficult exams.", concern: true))
        XCTAssertFalse(check("Excessive homework", "Homework was not excessive.", "Not excessive homework.", concern: true))
        XCTAssertFalse(check("Excessive homework", "Homework wasn't excessive.", "Homework wasn’t excessive.", concern: true))
        XCTAssertTrue(check("Not excessive homework", "Homework was not excessive.", "Not excessive homework."))
        // Conservative by design: semantic synonyms alone do not prove corroboration.
        XCTAssertFalse(check("Clear explanations", "Clear explanations.", "Wonderful explanations."))
        XCTAssertFalse(check("Not easy exams", "Not easy exams.", "Not easy exams."))
        let repaired = SummaryEvidence.corroboratedPoint(
            SummaryPoint(text: "Clear lectures and caring teaching", reviewIDs: ["r0", "r1"]),
            reviews: sources("Clear lectures.", "Clear lectures and caring teaching."), concern: false)
        XCTAssertEqual(repaired?.text, "Clear lectures")
    }
    private func reviews() -> [Review] {
        (0..<6).map { Review(id: "r\($0)", course: "MATH005A", text: String(repeating: "Complete fictional text. ", count: 10),
                            date: "2026-01-0\(6 - $0)", rating: 4, difficulty: 2, online: nil) }
    }
    func testCompactCitationMappingRejectsInvalidPairsAndParagraphs() {
        let reviews = reviews()
        XCTAssertEqual(SummaryEvidence.compactPoint("Helpful explanations", numbers: [1, 2], reviews: reviews)?.reviewIDs, ["r0", "r1"])
        for invalid in [[0, 1], [1, 7], [1, 1], [1], [1, 2, 3]] {
            XCTAssertNil(SummaryEvidence.compactPoint("Helpful explanations", numbers: invalid, reviews: reviews))
        }
        XCTAssertNil(SummaryEvidence.compactPoint("", numbers: [1, 2], reviews: reviews))
        XCTAssertNil(SummaryEvidence.compactPoint(String(repeating: "a", count: 97), numbers: [1, 2], reviews: reviews))
        XCTAssertNil(SummaryEvidence.compactPoint(String(repeating: "word ", count: 15), numbers: [1, 2], reviews: reviews))
        XCTAssertNil(SummaryEvidence.compactPoint("Helpful", numbers: [1, 2], reviews: [reviews[0], reviews[0]]))
    }
    func testBudgetKeepsWholeRecentReviewsAndIncludesOverhead() async throws {
        let reviews = reviews()
        let selected = try await SummaryEvidence.fit(reviews, budget: 100 + reviews[0].text.count * 2) {
            100 + $0.reduce(0) { $0 + $1.text.count }
        }
        XCTAssertEqual(selected, Array(reviews.prefix(2)))
        XCTAssertEqual(selected[0].text, reviews[0].text)
    }
    func testOversizedReviewOrOverheadCannotOverflowBudget() async throws {
        let selected = try await SummaryEvidence.fit(reviews(), budget: 20) { _ in 100 }
        XCTAssertTrue(selected.isEmpty)
        let zero = try await SummaryEvidence.fit(reviews(), budget: 0) { _ in XCTFail("Must not tokenize"); return 0 }
        XCTAssertTrue(zero.isEmpty)
    }
    func testCancelledBudgetSelectionStops() async throws {
        let reviews = reviews()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SummaryEvidence.fit(reviews, budget: 100) { _ in 1 }
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }
    func testCoursePriorityIsPreservedBeforeBudgeting() throws {
        let other = Review(id: "other", course: "HIST001", text: "Other course", date: "2026-10-10", rating: 5, difficulty: 1, online: nil)
        let selected = SummaryBuilder.selectedReviews([other] + reviews(), course: try Course("MATH005A"))
        XCTAssertEqual(selected, reviews())
    }
    func testProviderCacheSurvivesRestartRejectsLegacyAndChangedEvidence() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let course = try Course("MATH005A"), provider = "apple-test|v1"
        var profile = RMPProfile(id: "42", firstName: "Fictional", lastName: "Instructor", school: "Pasadena City College", schoolID: 2649,
                                 department: "Math", rating: 4, difficulty: 2, ratingCount: 6, wouldTakeAgain: nil, reviews: reviews())
        let cache = ReportCache(directory: dir)
        var summary = try SummaryBuilder.validate(Data("{\"positives\":[],\"concerns\":[]}".utf8), reviews: Array(profile.reviews.prefix(2)), course: course)
        cache.save(CachedReport(profile: profile, summary: summary, checkedAt: Date()), name: profile.name, course: course)
        XCTAssertNil(cache.load(name: profile.name, course: course, summaryProvider: provider)?.summary)
        summary.providerIdentity = provider; summary.evidence = Array(profile.reviews.prefix(2))
        cache.save(CachedReport(profile: profile, summary: summary, checkedAt: Date()), name: profile.name, course: course, summaryProvider: provider)
        let restarted = ReportCache(directory: dir)
        XCTAssertEqual(restarted.load(name: profile.name, course: course, summaryProvider: provider)?.summary, summary)
        XCTAssertNil(restarted.load(name: profile.name, course: course, summaryProvider: "apple-test|v2")?.summary)
        XCTAssertNil(restarted.load(name: profile.name, course: try Course("MATH005B"), summaryProvider: provider)?.summary)
        XCTAssertNil(restarted.load(name: profile.name, course: course, subject: "HIST", summaryProvider: provider)?.summary)
        let old = profile.reviews[0]
        profile.reviews[0] = Review(id: old.id, course: old.course, text: "Changed text with same ID", date: old.date, rating: old.rating, difficulty: old.difficulty, online: nil)
        cache.save(CachedReport(profile: profile, summary: nil, checkedAt: Date()), name: profile.name, course: try Course("MATH005B"))
        XCTAssertNil(restarted.load(name: profile.name, course: course, summaryProvider: provider)?.summary)
    }
    func testAppleSummaryExpiresFromGenerationTime() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let course = try Course("MATH005A"), provider = "apple-test|v1", now = Date()
        let profile = RMPProfile(id: "42", firstName: "Fictional", lastName: "Instructor", school: "Pasadena City College", schoolID: 2649,
                                 department: "Math", rating: 4, difficulty: 2, ratingCount: 6, wouldTakeAgain: nil, reviews: reviews())
        var summary = try SummaryBuilder.validate(Data("{\"positives\":[],\"concerns\":[]}".utf8), reviews: profile.reviews, course: course)
        summary.providerIdentity = provider; summary.evidence = profile.reviews
        summary.generatedAt = now.addingTimeInterval(-86401)
        let cache = ReportCache(directory: dir)
        cache.save(CachedReport(profile: profile, summary: summary, checkedAt: now), name: profile.name, course: course, summaryProvider: provider)
        XCTAssertNotNil(cache.load(name: profile.name, course: course, summaryProvider: provider, now: now)?.profile)
        XCTAssertNil(cache.load(name: profile.name, course: course, summaryProvider: provider, now: now)?.summary)
    }
}
