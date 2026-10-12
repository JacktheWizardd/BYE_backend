import XCTest
@testable import ClasswiseCore

final class CoreTests: XCTestCase {
    private func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json")!))
    }
    private var course: Course { try! Course("ETH 014") }
    private func review(_ id: String, course: String = "ETH014", date: String = "2026-06-01", rating: Double? = 5, difficulty: Double? = 1) -> Review {
        Review(id: id, course: course, text: "FICTIONAL TEST REVIEW: clear instruction and weekly writing.", date: date, rating: rating, difficulty: difficulty, online: true)
    }
    func testNormalizesCourseAndCommonCourseNumbering() throws {
        XCTAssertEqual(try Course(" eth014 \n").display, "ETH 014")
        XCTAssertEqual(try Course("pols c1000").key, "POLSC1000")
        XCTAssertThrowsError(try Course("eth")); XCTAssertThrowsError(try Course("ETH014; DROP"))
    }
    func testReviewMatchingDoesNotGuessBareNumbersOrCrossListedCourses() {
        XCTAssertTrue(course.matchesReview("eth 014"))
        XCTAssertFalse(course.matchesReview("014")); XCTAssertFalse(course.matchesReview("SOC014"))
        XCTAssertFalse(course.matchesReview("ETH014H"))
    }
    func testOfficialSummerFixtureCountsAndOnlineFormats() throws {
        let rows: [ScheduleRow] = try load("pcc-summer-2026-eth014", as: [ScheduleRow].self)
        let professors = ScheduleParser.professors(rows: rows, course: course)
        XCTAssertEqual(professors.count, 10)
        XCTAssertEqual(Set(professors.flatMap { $0.sections.map(\.crn) }).count, 14)
        let martha = try XCTUnwrap(professors.first { $0.name == "Martha Toscano" })
        XCTAssertTrue(martha.sections.contains { $0.fullyOnline })
        XCTAssertTrue(martha.sections.allSatisfy { $0.start.hasPrefix("2026-") && $0.end.hasPrefix("2026-") })
    }
    func testDeduplicatesMeetingsButKeepsMixedDelivery() throws {
        let json = """
        [
        {"subjCode":"ETH","courseNumbDisplay":"014","crn":"1","pfaName":"A Person","schdCode":"OD"},
        {"subjCode":"ETH","courseNumbDisplay":"014","crn":"1","pfaName":"A Person","schdCode":"L","monDay":"M","beginTime":"0900"},
        {"subjCode":"ETH","courseNumbDisplay":"014","crn":"2","pfaName":"A Person","schdCode":"OD","fwSectOpenInd":"X"}
        ]
        """
        let result = ScheduleParser.professors(rows: try JSONDecoder().decode([ScheduleRow].self, from: Data(json.utf8)), course: course)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].sections.count, 1)
        XCTAssertFalse(result[0].sections[0].fullyOnline)
        XCTAssertEqual(result[0].sections[0].meetings, ["Mon 9:00 AM"])
    }
    func testCompoundSurnameMatchesButWrongPersonDoesNot() throws {
        let candidates: [RMPProfile] = try load("fictional-profiles", as: [RMPProfile].self)
        XCTAssertEqual(IdentityMatcher.unique(name: "Martha Toscano", candidates: candidates)?.id, "fixture-1")
        XCTAssertNil(IdentityMatcher.unique(name: "Mary Toscano", candidates: candidates))
        XCTAssertNil(IdentityMatcher.unique(name: "Martha Johnson", candidates: candidates))
    }
    func testWrongSchoolAndAmbiguousMatchesRejected() throws {
        var candidates: [RMPProfile] = try load("fictional-profiles", as: [RMPProfile].self)
        let p = candidates[0]
        candidates.append(RMPProfile(id: "duplicate", firstName: p.firstName, lastName: p.lastName, school: p.school, schoolID: p.schoolID, department: p.department, rating: 4, difficulty: 2, ratingCount: 100, wouldTakeAgain: 80, reviews: []))
        XCTAssertNil(IdentityMatcher.unique(name: "Martha Toscano", candidates: candidates))
        let wrong = RMPProfile(id: "wrong", firstName: "Martha", lastName: "Toscano", school: "Other College", schoolID: 50, department: "", rating: 5, difficulty: 1, ratingCount: 10, wouldTakeAgain: 100, reviews: [])
        XCTAssertFalse(IdentityMatcher.matches(name: "Martha Toscano", profile: wrong))
    }
    func testMissingRatingsRemainNil() throws {
        let profiles: [RMPProfile] = try load("fictional-profiles", as: [RMPProfile].self)
        XCTAssertNil(profiles[1].rating); XCTAssertNil(profiles[1].difficulty); XCTAssertNil(profiles[1].wouldTakeAgain)
    }
    func testSummaryRejectsUnsupportedAndIsolatedThemes() throws {
        let json = """
        {"overview":"Feedback covers multiple courses.","positives":[
          {"text":"clear instruction","reviewIDs":["1","2"]},
          {"text":"invented support","reviewIDs":["1","fake"]},
          {"text":"isolated","reviewIDs":["1","1"]}
        ],"concerns":[{"text":"one complaint","reviewIDs":["1"]}]}
        """
        let summary = try SummaryBuilder.validate(Data(json.utf8), reviews: [review("1"), review("2", course: "SOC001")], course: course)
        XCTAssertEqual(summary.positives.count, 1); XCTAssertEqual(summary.concerns.count, 0)
        XCTAssertEqual(summary.analyzedCount, 2); XCTAssertEqual(summary.exactCourseCount, 1)
        XCTAssertEqual(summary.overview, "Common positive: clear instruction")
        XCTAssertFalse(summary.overview.contains("Feedback covers multiple courses"))
    }
    func testRejectedThemesCannotLeaveAnInventedOverview() throws {
        let json = """
        {"overview":"Attendance is optional and everyone earns an A.","positives":[
          {"text":"Invented claim","reviewIDs":["fake-1","fake-2"]},
          {"text":"Isolated claim","reviewIDs":["1","1"]}
        ],"concerns":[]}
        """
        let summary = try SummaryBuilder.validate(Data(json.utf8), reviews: [review("1"), review("2")], course: course)
        XCTAssertEqual(summary.overview, "Not enough feedback to identify recurring themes.")
        XCTAssertTrue(summary.positives.isEmpty)
        XCTAssertTrue(summary.concerns.isEmpty)
    }
    func testOverviewUsesOnlyAcceptedPositiveAndConcern() throws {
        let json = """
        {"overview":"Unsupported free text about textbook costs.","positives":[
          {"text":"clear instruction","reviewIDs":["1","2"]}
        ],"concerns":[
          {"text":"invented attendance policy","reviewIDs":["1","unknown"]},
          {"text":"weekly writing","reviewIDs":["1","2"]}
        ]}
        """
        let summary = try SummaryBuilder.validate(Data(json.utf8), reviews: [review("1"), review("2")], course: course)
        XCTAssertEqual(summary.overview, "Common positive: clear instruction\nCommon concern: weekly writing")
        XCTAssertEqual(summary.concerns.map(\.text), ["weekly writing"])
        XCTAssertFalse(summary.overview.contains("textbook"))
        XCTAssertFalse(summary.overview.contains("attendance"))
    }
    func testSingleReviewCannotEstablishRecurringTheme() throws {
        let json = Data("{\"overview\":\"Everyone agrees\",\"positives\":[],\"concerns\":[]}".utf8)
        let summary = try SummaryBuilder.validate(json, reviews: [review("1")], course: course)
        XCTAssertTrue(summary.overview.contains("Not enough feedback"))
    }
    func testMalformedAIResponseFailsInsteadOfDisplayingIt() {
        XCTAssertThrowsError(try SummaryBuilder.validate(Data("not json".utf8), reviews: [review("1")], course: course))
    }
    func testSummaryPrioritizesExactCourseAndCapsAt50() {
        let other = (0..<60).map { review("o\($0)", course: "SOC001", date: "2026-09-01") }
        let exact = [review("exact", date: "2025-01-01")]
        let selected = SummaryBuilder.selectedReviews(other + exact, course: course)
        XCTAssertEqual(selected.count, 50); XCTAssertEqual(selected.first?.id, "exact")
    }
    func testSufficientExactCourseEvidenceExcludesOtherCoursePolicies() {
        let selected = SummaryBuilder.selectedReviews([review("1"), review("2"), review("other", course: "SOC001")], course: course)
        XCTAssertEqual(Set(selected.map(\.id)), Set(["1", "2"]))
    }
    func testPromptTreatsReviewsAsUntrustedData() throws {
        let prompt = try SummaryBuilder.prompt(reviews: [review("1")], course: course)
        XCTAssertTrue(prompt.contains("untrusted data")); XCTAssertTrue(prompt.contains("TWO distinct supporting"))
        XCTAssertTrue(prompt.contains("ETH 014"))
    }
    func testReviewOrderingPutsMissingScoresLast() {
        let a = review("a", date: "2026-01-01", rating: 4, difficulty: 3)
        let b = review("b", date: "2026-06-01", rating: 5, difficulty: 1)
        let missing = review("missing", rating: nil, difficulty: nil)
        XCTAssertEqual(Ordering.reviews([missing, a, b], by: .highest).map(\.id), ["b", "a", "missing"])
        XCTAssertEqual(Ordering.reviews([missing, a, b], by: .lowest).map(\.id), ["a", "b", "missing"])
        XCTAssertEqual(Ordering.reviews([missing, a, b], by: .difficulty).map(\.id), ["b", "a", "missing"])
        XCTAssertEqual(Ordering.reviews([a, b], by: .recent).first?.id, "b")
    }
    func testProfessorSortingAndUnavailableLast() throws {
        let profiles: [RMPProfile] = try load("fictional-profiles", as: [RMPProfile].self)
        var a = Professor(id: "a", name: "A", sections: []); a.profile = profiles[0]; a.state = .ready
        var b = Professor(id: "b", name: "B", sections: []); b.state = .unavailable
        XCTAssertEqual(Ordering.professors([b, a], by: .rating, course: course).first?.id, "a")
    }

    func testAllSixReviewOrdersUseIndividualScoresAndDeterministicTies() {
        let a = review("a", date: "2026-01-01", rating: 2, difficulty: 4)
        let b = review("b", date: "2026-06-01", rating: 5, difficulty: 1)
        let c = review("c", date: "2026-06-01", rating: 5, difficulty: 1)
        let missing = review("missing", date: "", rating: nil, difficulty: nil)
        let values = [missing, c, a, b]
        XCTAssertEqual(ReviewSort.allCases.count, 6)
        for order in [ReviewSort.recent, .highest, .difficulty] {
            XCTAssertEqual(Ordering.reviews(values, by: order).map(\.id), ["b", "c", "a", "missing"])
        }
        for order in [ReviewSort.oldest, .lowest, .highestDifficulty] {
            XCTAssertEqual(Ordering.reviews(values, by: order).map(\.id), ["a", "b", "c", "missing"])
        }
        for order in ReviewSort.allCases {
            XCTAssertEqual(Ordering.reviews(values, by: order), Ordering.reviews(values.reversed(), by: order))
        }
    }

    func testReviewDatesAreChronologicalAcrossSourceFormatsAndInvalidDatesLast() {
        let values = [review("bad", date: "not a date"), review("empty", date: ""),
                      review("offset", date: "2026-01-01T01:00:00+02:00"),
                      review("day", date: "2026-01-01"),
                      review("utc", date: "2026-01-01 00:30:00 +0000 UTC"),
                      review("fraction", date: "2026-01-01T00:30:00.500Z")]
        XCTAssertEqual(Ordering.reviews(values, by: .recent).map(\.id), ["fraction", "utc", "day", "offset", "bad", "empty"])
        XCTAssertEqual(Ordering.reviews(values, by: .oldest).map(\.id), ["offset", "day", "utc", "fraction", "bad", "empty"])
    }

    func testEveryReviewSortStaysWithinActiveCourseFilter() throws {
        let profile = RMPProfile(id: "p", firstName: "Test", lastName: "Instructor", school: "PCC", schoolID: 2649,
                                 department: "Math", rating: 5, difficulty: 5, ratingCount: 3, wouldTakeAgain: nil,
                                 reviews: [review("a", course: "MATH5A", rating: 1), review("b", course: "MATH 005A", rating: 2), review("other", course: "MATH5B", rating: 5)])
        for order in ReviewSort.allCases {
            let sorted = Ordering.reviews(ReviewFilter.thisCourse.reviews(in: profile, course: try Course("MATH005A")), by: order)
            XCTAssertEqual(Set(sorted.map(\.id)), ["a", "b"])
        }
    }
    func testCacheExpiryAndIdentityValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ReportCache(directory: directory)
        let profiles: [RMPProfile] = try load("fictional-profiles", as: [RMPProfile].self)
        let time = Date()
        cache.save(CachedReport(profile: profiles[0], summary: nil, checkedAt: time), name: "Martha Toscano", course: course)
        XCTAssertNotNil(cache.load(name: "Martha Toscano", course: course, now: time.addingTimeInterval(10)))
        XCTAssertNil(cache.load(name: "Martha Toscano", course: course, now: time.addingTimeInterval(90000)))
        XCTAssertNil(cache.load(name: "Martha Toscano", course: try Course("SOC001")))
        cache.save(CachedReport(profile: profiles[1], summary: nil, checkedAt: time), name: "Martha Toscano", course: course)
        XCTAssertNil(cache.load(name: "Martha Toscano", course: course))
    }
}

private final class StubProtocol: URLProtocol {
    static var reply: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.reply!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
final class ClientTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }
    override func tearDown() { StubProtocol.reply = nil }
    func testOnlyPublishedTermsAreOffered() async throws {
        StubProtocol.reply = { _ in (200, Data("[{\"termCode\":\"202650\",\"termName\":\"Summer 2026\",\"termDisplayControl\":\"Y\"},{\"termCode\":\"202730\",\"termName\":\"Spring 2027\",\"termDisplayControl\":\"N\"}]".utf8)) }
        let result = try await PCCClient(session: session()).terms()
        XCTAssertEqual(result.map(\.termCode), ["202650"])
    }
    func testPCCFailureIsActionable() async {
        StubProtocol.reply = { _ in (503, Data()) }
        do { _ = try await PCCClient(session: session()).terms(); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("PCC")) }
    }
    func testUnavailableOllamaDoesNotProduceSummary() async throws {
        StubProtocol.reply = { _ in throw URLError(.cannotConnectToHost) }
        let review = Review(id: "1", course: "ETH014", text: "Fictional test", date: "", rating: 5, difficulty: 1, online: nil)
        let second = Review(id: "2", course: "ETH014", text: "Another fictional test", date: "", rating: 5, difficulty: 1, online: nil)
        do { _ = try await OllamaClient(session: session()).summarize(reviews: [review, second], course: Course("ETH014")); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Open Ollama")) }
    }
    func testLocalRequestUsesConfiguredModelAndDisablesThinking() async throws {
        StubProtocol.reply = { request in
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count))
                }
            }
            let payload = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            XCTAssertEqual(payload["model"] as? String, "test-small-model")
            XCTAssertEqual(payload["think"] as? Bool, false)
            XCTAssertEqual(payload["stream"] as? Bool, false)
            XCTAssertEqual(payload["format"] as? String, "json")
            let content = "{\"overview\":\"Not enough feedback.\",\"positives\":[],\"concerns\":[]}"
            let data = try JSONSerialization.data(withJSONObject: ["message": ["content": content]])
            return (200, data)
        }
        let review = Review(id: "1", course: "ETH014", text: "Fictional test", date: "", rating: 5, difficulty: 1, online: nil)
        let second = Review(id: "2", course: "ETH014", text: "Another fictional test", date: "", rating: 5, difficulty: 1, online: nil)
        let summary = try await OllamaClient(model: "test-small-model", session: session()).summarize(reviews: [review, second], course: Course("ETH014"))
        XCTAssertEqual(summary.analyzedCount, 2)
    }
    func testSingleReviewAvoidsAnAIRequest() async throws {
        StubProtocol.reply = { _ in XCTFail("Insufficient feedback should not call Ollama"); throw URLError(.cannotConnectToHost) }
        let review = Review(id: "1", course: "ETH014", text: "Fictional test", date: "", rating: 5, difficulty: 1, online: nil)
        let summary = try await OllamaClient(session: session()).summarize(reviews: [review], course: Course("ETH014"))
        XCTAssertEqual(summary.analyzedCount, 1)
        XCTAssertEqual(summary.exactCourseCount, 1)
        XCTAssertTrue(summary.positives.isEmpty)
        XCTAssertTrue(summary.concerns.isEmpty)
        XCTAssertEqual(summary.overview, "Not enough feedback to identify recurring themes.")
    }
    func testZeroReviewsRemainActionableWithoutAIRequest() async throws {
        StubProtocol.reply = { _ in XCTFail("No reviews should not call Ollama"); throw URLError(.cannotConnectToHost) }
        do {
            _ = try await OllamaClient(session: session()).summarize(reviews: [], course: Course("ETH014"))
            XCTFail("Expected missing feedback error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No review text")) }
    }
    func testDefaultSummaryModelIsVerifiedBaselineAndConfigurable() {
        XCTAssertEqual(OllamaClient().model, "qwen3:4b")
        XCTAssertEqual(OllamaClient(model: "other-model").model, "other-model")
    }
}
