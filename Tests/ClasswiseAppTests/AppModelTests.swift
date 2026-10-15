import Foundation
import XCTest
@testable import Classwise
@testable import ClasswiseCore

/// These tests exercise the app's real selection/cancellation queues. Profiles
/// are complete fictional fixtures, so no RMP page or actual model is contacted.
final class AppModelTests: XCTestCase {
    @MainActor
    func testRetryOfConservativeSummaryRegeneratesWithoutDiscardingProfile() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let before = fixture.model.professors[0].profile
        fixture.model.requestSelectedReport()
        try await waitUntil("first summary starts") { fixture.server.tags == ["a"] }
        fixture.server.complete(0)
        try await waitUntil("conservative summary completes") { fixture.model.professors[0].summary != nil && !fixture.model.loadingDetails }
        fixture.model.retrySummary(id: "a")
        XCTAssertNil(fixture.model.professors[0].summary)
        XCTAssertEqual(fixture.model.professors[0].profile, before)
        try await waitUntil("explicit summary retry starts") { fixture.server.tags == ["a", "a"] }
        fixture.server.complete(1)
        try await waitUntil("retry completes") { fixture.model.professors[0].summary != nil && !fixture.model.loadingDetails }
    }
    @MainActor
    func testDisabledSummariesSkipGenerationRetryAndPrewarm() async throws {
        let provider = DisabledSummarySpy()
        let fixture = try fixture(summaryProvider: provider, summariesEnabled: false)
        defer { fixture.close() }
        let model = fixture.model
        XCTAssertFalse(model.summariesEnabled)
        model.requestSelectedReport()
        model.retrySummary(id: "a")
        model.selectedID = "b"; model.requestSelectedReport()
        let term = Term(termCode: "202670", termName: "FICTIONAL test term", termDisplayControl: "Y")
        model.terms = [term]; model.termID = term.id; model.input = "MATH005A"
        model.start()
        try await waitUntil("disabled-mode search finishes") { !model.busy && model.showingResults }
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(fixture.server.tags.isEmpty)
        XCTAssertNil(model.summaryLoadingID)
        XCTAssertTrue(model.retryingIDs.isEmpty)
        XCTAssertFalse(AppModel(cache: ReportCache(directory: fixture.directory), choices: ProfileChoiceStore(directory: fixture.directory)).summariesEnabled)
    }

    @MainActor
    func testDisabledSummariesStillExpandRetryAndCacheReviews() async throws {
        let reader = DisabledReviewReader()
        let provider = DisabledSummarySpy()
        let fixture = try fixture(makeReader: { reader }, summaryProvider: provider, summariesEnabled: false)
        defer { fixture.close() }
        let model = fixture.model
        model.professors[0].reviewsComplete = false
        model.requestSelectedReport()
        try await waitUntil("review error") { model.professors[0].reviewIssue != nil && !model.loadingDetails }
        XCTAssertEqual(model.professors[0].profile?.reviews.count, 2)
        model.retryReviews(id: "a")
        try await waitUntil("review retry completes") { model.professors[0].reviewsComplete && !model.loadingDetails }
        XCTAssertEqual(reader.calls, 2)
        XCTAssertNil(model.professors[0].reviewIssue)
        XCTAssertEqual(model.professors[0].profile?.reviews.count, 3)
        XCTAssertNil(model.professors[0].summary)
        XCTAssertNil(model.summaryLoadingID)
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
        let saved = ReportCache(directory: fixture.directory).load(name: model.professors[0].name, course: model.course!, subject: model.professors[0].subjectCode, includeSummary: false)
        XCTAssertEqual(saved?.profile.reviews.count, 3)
        XCTAssertEqual(saved?.reviewsComplete, true)
    }

    @MainActor
    private func fixture(makeReader: @escaping @MainActor () -> any ProfileReader = { RMPBrowser() }, summaryProvider: (any SummaryProvider)? = nil, summariesEnabled: Bool = true) throws -> AppFixture {
        let server = AppTestServer()
        AppTestProtocol.server = server
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppTestProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BYE-AppTests-\(UUID())")
        let model = AppModel(pcc: PCCClient(session: session),
                             ollama: OllamaClient(model: "fictional-test-model", session: session), summaryProvider: summaryProvider,
                             cache: ReportCache(directory: directory), choices: ProfileChoiceStore(directory: directory), summariesEnabled: summariesEnabled, makeReader: makeReader)
        model.course = try Course("MATH 005A")
        model.professors = ["a", "b", "c"].map { id in
            let reviews = (1...2).map { number in
                Review(id: "test-\(id)-\(number)", course: "MATH005A",
                       text: "FICTIONAL TEST REVIEW \(id): clear explanations and weekly practice.",
                       date: "2026-01-01", rating: 5, difficulty: 2, online: true)
            }
            let section = Section(crn: id, title: "FICTIONAL Calculus", start: "2026-01-01", end: "2026-05-01",
                                  formats: ["OD"], meetings: [], status: "O")
            let profile = RMPProfile(id: id, firstName: "Fictional", lastName: id.uppercased(),
                                     school: "Pasadena City College", schoolID: 2649, department: "Math",
                                     rating: 5, difficulty: 2, ratingCount: 20, wouldTakeAgain: 90, reviews: reviews)
            var professor = Professor(id: id, name: profile.name, sections: [section])
            professor.profile = profile; professor.state = .ready; professor.reviewsComplete = true
            return professor
        }
        model.showingResults = true; model.selectedID = "a"
        return AppFixture(model: model, server: server, session: session, directory: directory)
    }

    @MainActor
    func testInjectedAppleProviderPublishesAndCachesOnlyItsOwnEvidence() async throws {
        let fixture = try fixture(summaryProvider: SuccessfulAppleFixture()); defer { fixture.close() }
        fixture.model.requestSelectedReport()
        try await waitUntil("Apple summary published") { fixture.model.professors[0].summary != nil }
        let professor = fixture.model.professors[0]
        let saved = ReportCache(directory: fixture.directory).load(name: professor.name, course: fixture.model.course!,
            subject: professor.subjectCode, summaryProvider: "apple-fixture|success")
        XCTAssertEqual(saved?.summary, professor.summary)
        XCTAssertEqual(saved?.summary?.evidence, professor.profile?.reviews)
        XCTAssertEqual(saved?.summary?.positives.first?.reviewIDs, ["test-a-1", "test-a-2"])
        XCTAssertNil(ReportCache(directory: fixture.directory).load(name: professor.name, course: fixture.model.course!, subject: professor.subjectCode)?.summary)
        XCTAssertTrue(fixture.server.tags.isEmpty)
    }

    @MainActor
    func testUnavailableAppleProviderKeepsSourceDataWithoutOllamaFallback() async throws {
        let fixture = try fixture(summaryProvider: UnavailableAppleFixture()); defer { fixture.close() }
        let original = fixture.model.professors[0].profile
        fixture.model.requestSelectedReport()
        try await waitUntil("Apple readiness failure") { fixture.model.professors[0].summaryIssue != nil }
        XCTAssertEqual(fixture.model.professors[0].profile, original)
        XCTAssertNil(fixture.model.professors[0].summary)
        XCTAssertTrue(fixture.model.professors[0].summaryIssue!.contains("Apple Intelligence"))
        XCTAssertTrue(fixture.server.tags.isEmpty, "Must not fall back to Ollama")
        fixture.model.retrySummary(id: "a")
        try await waitUntil("Apple retry finishes") { !fixture.model.loadingDetails }
        XCTAssertTrue(fixture.server.tags.isEmpty)
    }

    @MainActor
    private func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out: \(message)")
                throw URLError(.timedOut)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    func testRatingsPassBlocksAIUntilItFinishes() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let model = fixture.model
        model.busy = true
        model.requestSelectedReport()
        await Task.yield()
        XCTAssertTrue(fixture.server.tags.isEmpty)
        XCTAssertTrue(model.retryingIDs.isEmpty)

        model.busy = false
        model.requestSelectedReport()
        try await waitUntil("first summary request") { fixture.server.tags == ["a"] }
        XCTAssertEqual(model.summaryLoadingID, "a")
        fixture.server.complete(0)
        try await waitUntil("summary finished") { model.professors[0].summary != nil && !model.loadingDetails }
        XCTAssertEqual(model.professors[0].summary?.analyzedCount, 2)
    }

    @MainActor
    func testReturningToActiveProfessorDiscardsQueuedProfessor() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let model = fixture.model
        model.requestSelectedReport()
        try await waitUntil("A starts") { fixture.server.tags == ["a"] }
        model.selectedID = "b"; model.requestSelectedReport()
        XCTAssertTrue(model.retryingIDs.contains("b"))
        model.selectedID = "a"; model.requestSelectedReport()
        XCTAssertFalse(model.retryingIDs.contains("b"))

        fixture.server.complete(0)
        try await waitUntil("A finishes without B") { !model.loadingDetails && model.retryingIDs.isEmpty }
        XCTAssertEqual(fixture.server.tags, ["a"])
        XCTAssertNil(model.professors[1].summary)
    }

    @MainActor
    func testOnlyLatestPendingProfessorIsSummarized() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let model = fixture.model
        model.requestSelectedReport()
        try await waitUntil("A starts") { fixture.server.tags == ["a"] }
        model.selectedID = "b"; model.requestSelectedReport()
        model.selectedID = "c"; model.requestSelectedReport()
        XCTAssertFalse(model.retryingIDs.contains("b"))
        XCTAssertTrue(model.retryingIDs.contains("c"))

        fixture.server.complete(0)
        try await waitUntil("C follows A") { fixture.server.tags == ["a", "c"] }
        XCTAssertEqual(model.summaryLoadingID, "c")
        fixture.server.complete(1)
        try await waitUntil("C completes") { !model.loadingDetails && model.professors[2].summary != nil }
        XCTAssertNil(model.professors[1].summary)
    }

    @MainActor
    func testSelectingCompletedReportDiscardsPendingWork() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let model = fixture.model
        model.professors[2].summary = try SummaryBuilder.validate(
            Data("{\"positives\":[],\"concerns\":[]}".utf8),
            reviews: model.professors[2].profile!.reviews, course: model.course!)
        model.requestSelectedReport()
        try await waitUntil("A starts") { fixture.server.tags == ["a"] }
        model.selectedID = "b"; model.requestSelectedReport()
        model.selectedID = "c"; model.requestSelectedReport()
        XCTAssertFalse(model.retryingIDs.contains("b"))

        fixture.server.complete(0)
        try await waitUntil("no unnecessary pending request") { !model.loadingDetails }
        XCTAssertEqual(fixture.server.tags, ["a"])
    }

    @MainActor
    func testStoppedProfessorCanBeReopenedAfterAnotherReport() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let model = fixture.model
        model.requestSelectedReport()
        try await waitUntil("A starts") { fixture.server.tags == ["a"] }
        model.cancelDetails()
        XCTAssertFalse(model.loadingDetails)
        XCTAssertTrue(model.retryingIDs.isEmpty)

        model.selectedID = "b"; model.requestSelectedReport()
        try await waitUntil("B starts after cancellation") { fixture.server.tags == ["a", "b"] }
        fixture.server.complete(1)
        try await waitUntil("B finishes") { !model.loadingDetails && model.professors[1].summary != nil }
        model.selectedID = "a"; model.requestSelectedReport()
        try await waitUntil("A reopens") { fixture.server.tags == ["a", "b", "a"] }
        fixture.server.complete(2)
        try await waitUntil("reopened A finishes") { !model.loadingDetails && model.professors[0].summary != nil }
    }

    @MainActor
    func testOldCancellationDoesNotClearNewSearchSummaryState() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let model = fixture.model
        model.requestSelectedReport()
        try await waitUntil("old A request") { fixture.server.tags == ["a"] }
        model.changeSearch()
        model.course = try Course("MATH 005B")
        model.professors = [model.professors[2]]
        model.showingResults = true; model.selectedID = "c"; model.requestSelectedReport()
        try await waitUntil("new C request") { fixture.server.tags == ["a", "c"] }
        // The cancelled A task must not clear C's state in its catch/defer path.
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.summaryLoadingID, "c")
        XCTAssertTrue(model.retryingIDs.contains("c"))
        XCTAssertNil(model.professors[0].summary)
        fixture.server.complete(0) // A cancelled response is ignored by the transport.
        fixture.server.complete(1)
        try await waitUntil("new C finishes") { !model.loadingDetails && model.professors[0].summary != nil }
        XCTAssertEqual(model.professors[0].id, "c")
    }

    @MainActor
    func testRefreshCancelsOldModelWorkAndUsesNewPCCResult() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let model = fixture.model
        let term = Term(termCode: "202670", termName: "FICTIONAL test term", termDisplayControl: "Y")
        model.terms = [term]; model.termID = term.id; model.searchedTerm = term
        model.requestSelectedReport()
        try await waitUntil("A starts before refresh") { fixture.server.tags == ["a"] }
        model.refresh()
        try await waitUntil("mock PCC refresh completes") { !model.busy && model.showingResults && model.professors.isEmpty }
        XCTAssertEqual(fixture.server.scheduleRequests, 1)
        XCTAssertNil(model.summaryLoadingID)
        XCTAssertTrue(model.retryingIDs.isEmpty)
        XCTAssertNil(model.error)
        fixture.server.complete(0)
        await Task.yield()
        XCTAssertTrue(model.professors.isEmpty)
    }

    @MainActor
    func testChangedReviewTextRejectsInFlightSummaryAndCacheEvenWithSameIDs() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let model = fixture.model
        model.requestSelectedReport()
        try await waitUntil("original evidence starts") { fixture.server.tags == ["a"] }
        let old = model.professors[0].profile!.reviews[0]
        model.professors[0].profile!.reviews[0] = Review(id: old.id, course: old.course, text: "CHANGED FICTIONAL evidence", date: old.date, rating: old.rating, difficulty: old.difficulty, online: old.online)
        fixture.server.complete(0)
        try await waitUntil("fresh evidence is retried") { fixture.server.tags == ["a", "a"] }
        XCTAssertNil(model.professors[0].summary)
        XCTAssertNil(ReportCache(directory: fixture.directory).load(name: model.professors[0].name, course: model.course!)?.summary)
        fixture.server.complete(1)
        try await waitUntil("fresh summary finishes") { !model.loadingDetails && model.professors[0].summary != nil }
    }

    @MainActor
    func testSummaryFailureKeepsRatingsAndCanBeRetried() async throws {
        let fixture = try fixture(); defer { fixture.close() }
        let model = fixture.model
        let before = model.professors[0].profile
        model.requestSelectedReport()
        try await waitUntil("first A request") { fixture.server.tags == ["a"] }
        fixture.server.complete(0, status: 503)
        try await waitUntil("summary failure is shown") { !model.loadingDetails && model.professors[0].summaryIssue != nil }
        XCTAssertEqual(model.professors[0].profile, before)
        XCTAssertNil(model.professors[0].summary)

        model.retrySummary(id: "a")
        try await waitUntil("A retry starts") { fixture.server.tags == ["a", "a"] }
        fixture.server.complete(1)
        try await waitUntil("retry succeeds") { !model.loadingDetails && model.professors[0].summary != nil }
        XCTAssertNil(model.professors[0].summaryIssue)
        XCTAssertEqual(model.professors[0].profile, before)
    }
    @MainActor
    func testProfileChangeDuringSummaryCannotRestoreOrCacheOldSummary() async throws {
        let hub = RecoveryHub()
        let fixture = try fixture(makeReader: { hub.reader() }); defer { fixture.close() }
        let model = fixture.model
        let replacement = RMPProfile(id: "42", firstName: "Fictional", lastName: "A", school: "Pasadena City College", schoolID: 2649,
                                     department: "Math", rating: 3, difficulty: 4, ratingCount: 0, wouldTakeAgain: nil, reviews: [])
        hub.options = [replacement]
        model.professors[0].candidates = [replacement]
        model.requestSelectedReport()
        try await waitUntil("old summary begins") { fixture.server.tags == ["a"] }
        model.chooseProfile(id: "a", profileID: "42")
        XCTAssertNil(model.professors[0].profile); XCTAssertNil(model.professors[0].summary)
        model.selectedID = nil
        fixture.server.complete(0)
        try await waitUntil("replacement and old summary finish") { !model.busy && !model.loadingDetails }
        XCTAssertEqual(model.professors[0].profile?.id, "42")
        XCTAssertNil(model.professors[0].summary)
        XCTAssertEqual(model.professors[1].profile?.id, "b")
        XCTAssertEqual(ReportCache(directory: fixture.directory).load(name: "Fictional A", course: try Course("MATH005A"), subject: "")?.profile.id, "42")
    }

    @MainActor
    func testPreviewRetryPausesDispatchOfQueuedSummaries() async throws {
        let hub = RecoveryHub(); hub.holdCandidates = true
        let fixture = try fixture(makeReader: { hub.reader() }); defer { fixture.close() }
        let model = fixture.model
        model.requestSelectedReport()
        try await waitUntil("A begins") { fixture.server.tags == ["a"] }
        model.selectedID = "b"; model.requestSelectedReport()
        model.professors[2].profile = nil; model.professors[2].state = .unavailable
        model.retryProfessor(id: "c")
        try await waitUntil("preview begins") { hub.waiting["c"] != nil }
        fixture.server.complete(0)
        try await waitUntil("A finishes during preview") { model.summaryLoadingID == nil }
        XCTAssertEqual(fixture.server.tags, ["a"])
        hub.waiting.removeValue(forKey: "c")!.resume(returning: [])
        try await waitUntil("B resumes after preview") { fixture.server.tags == ["a", "b"] }
        fixture.server.complete(1)
        try await waitUntil("B finishes") { !model.loadingDetails }
    }

}

@MainActor
private struct AppFixture {
    let model: AppModel
    let server: AppTestServer
    let session: URLSession
    let directory: URL
    func close() {
        model.cancel(); session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class AppTestServer {
    private struct Request {
        let loader: AppTestProtocol
        let tag: String
        var stopped = false
        var completed = false
    }
    private let lock = NSLock()
    private var requests: [Request] = []
    private var scheduleCount = 0
    var tags: [String] { lock.lock(); defer { lock.unlock() }; return requests.map(\.tag) }
    var scheduleRequests: Int { lock.lock(); defer { lock.unlock() }; return scheduleCount }

    func start(_ loader: AppTestProtocol) {
        if loader.request.url?.path.contains("classSchedule/") == true {
            lock.lock(); scheduleCount += 1; lock.unlock()
            loader.reply(status: 200, data: Data("[]".utf8))
            return
        }
        guard loader.request.url?.path == "/api/chat" else {
            loader.client?.urlProtocol(loader, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let body = Self.body(loader.request)
        let tag = ["a", "b", "c"].first(where: { body.contains("test-\($0)-1") }) ?? "unknown"
        lock.lock(); requests.append(Request(loader: loader, tag: tag)); lock.unlock()
    }
    func stop(_ loader: AppTestProtocol) {
        lock.lock(); defer { lock.unlock() }
        if let index = requests.firstIndex(where: { $0.loader === loader }) { requests[index].stopped = true }
    }
    func complete(_ index: Int, status: Int = 200) {
        lock.lock()
        guard requests.indices.contains(index), !requests[index].stopped, !requests[index].completed else { lock.unlock(); return }
        requests[index].completed = true
        let loader = requests[index].loader
        lock.unlock()
        let content = "{\"positives\":[],\"concerns\":[]}"
        let data = try! JSONSerialization.data(withJSONObject: ["message": ["content": content]])
        loader.reply(status: status, data: data)
    }
    private static func body(_ request: URLRequest) -> String {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class AppTestProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var currentServer: AppTestServer?
    static var server: AppTestServer? {
        get { lock.lock(); defer { lock.unlock() }; return currentServer }
        set { lock.lock(); currentServer = newValue; lock.unlock() }
    }
    private var owner: AppTestServer?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        owner = Self.server
        guard let owner else { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
        owner.start(self)
    }
    override func stopLoading() { owner?.stop(self) }
    func reply(status: Int, data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private struct UnavailableAppleFixture: SummaryProvider {
    let cacheIdentity = "apple-fixture|not-ready"
    func summarize(reviews: [Review], course: Course) async throws -> ReviewSummary {
        throw AppError.message("Apple Intelligence model not ready; retry after setup.")
    }
}

private struct SuccessfulAppleFixture: SummaryProvider {
    let cacheIdentity = "apple-fixture|success"
    func summarize(reviews: [Review], course: Course) async throws -> ReviewSummary {
        let selected = SummaryBuilder.selectedReviews(reviews, course: course)
        let point = SummaryEvidence.compactPoint("Clear explanations", numbers: [1, 2], reviews: selected)!
        struct Output: Encodable { let positives: [SummaryPoint]; let concerns: [SummaryPoint] }
        let data = try JSONEncoder().encode(Output(positives: [point], concerns: []))
        var summary = try SummaryBuilder.validate(data, reviews: selected, course: course)
        summary.providerIdentity = cacheIdentity; summary.evidence = selected
        return summary
    }
}

private actor DisabledSummarySpy: SummaryProvider {
    nonisolated let cacheIdentity = "disabled-summary-spy"
    private(set) var calls = 0
    func prewarm() async { calls += 1 }
    func summarize(reviews: [Review], course: Course) async throws -> ReviewSummary {
        calls += 1
        throw URLError(.unsupportedURL)
    }
}

@MainActor
private final class DisabledReviewReader: ProfileReader {
    var calls = 0
    func stop() { }
    func candidates(_ professor: Professor, discoverAll: Bool) async throws -> [RMPProfile] { [] }
    func preview(_ professor: Professor, profileID: String) async throws -> RMPProfile { throw URLError(.unsupportedURL) }
    func expand(_ professor: Professor, profile: RMPProfile, onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile {
        calls += 1
        if calls == 1 { throw URLError(.timedOut) }
        var full = profile
        full.reviews.append(Review(id: "expanded", course: "MATH005A", text: "Fictional additional review", date: "2026-01-02", rating: 4, difficulty: 2, online: true))
        onProfile(full)
        return full
    }
}
