import Foundation
import XCTest
@testable import Classwise
@testable import ClasswiseCore

private final class RefreshFixtureProtocol: URLProtocol {
    static var handler: ((RefreshFixtureProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}
    func reply(_ body: Data, status: Int = 200) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class ScheduleRefreshTests: XCTestCase {
    private var directory: URL!
    private var version = "c1"
    private var instructorName = "Alpha Fixture"
    private var seats = 3
    private var manifest: RefreshFixtureProtocol?
    private var hold = false
    private var fail = false
    private var calls = 0
    private var day = "mon"
    private func fixture() throws -> AppModel {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RefreshFixtureProtocol.self]
        RefreshFixtureProtocol.handler = { [weak self] request in
            Task { @MainActor in
                guard let self else { return }
                self.calls += 1
                XCTAssertEqual(request.request.url?.host, "schedule.invalid")
                if self.hold && request.request.url!.path.hasSuffix("manifest") { self.manifest = request; return }
                self.respond(request)
            }
        }
        let api = ScheduleAPIClient(base: URL(string: "https://schedule.invalid"), key: "fixture",
                                    session: URLSession(configuration: config))
        let model = AppModel(pcc: PCCClient(scheduleAPI: api), cache: ReportCache(directory: directory), choices: ProfileChoiceStore(directory: directory))
        let term = Term(termCode: "202670", termName: "Fictional semester", termDisplayControl: "Y")
        model.terms = [term]; model.termID = term.id; model.searchedTerm = term
        model.course = try Course("MATH 005AH"); model.showingResults = true
        return model
    }
    private func respond(_ request: RefreshFixtureProtocol) {
        if fail { request.reply(Data(), status: 503); return }
        let path = request.request.url!.path
        let data: Any
        if path.hasSuffix("/terms") { data = [["termCode": "202730", "name": "Future fixture"], ["termCode": "202670", "name": "Fall fixture"]] }
        else if path.hasSuffix("manifest") { data = [:] }
        else if path.hasSuffix("catalog") { data = [["key": "MATH 005AH", "subject": "MATH", "number": "005AH", "title": "Fictional calculus"]] }
        else if path.hasSuffix("availability") { data = [["crn": "12345", "availability": ["seatsAvailable": seats, "capacity": 30]]] }
        else { data = [["crn": "12345", "courseKey": "MATH 005AH", "instructors": [["assignmentId": "fixture", "role": "primary", "name": instructorName]],
                       "meetings": [["days": [day], "formatCode": "L"]], "availability": ["seatsAvailable": seats, "capacity": 30, "waitlistCount": 2]]] }
        let body = try! JSONSerialization.data(withJSONObject: ["data": data, "meta": ["term": "202670", "catalogVersion": version,
                    "availabilityVersion": "a\(seats)", "sourceCheckedAt": ISO8601DateFormatter().string(from: Date()), "stale": false]])
        request.reply(body)
    }
    private func close(_ model: AppModel) {
        model.cancel(); RefreshFixtureProtocol.handler = nil
        try? FileManager.default.removeItem(at: directory)
    }
    private func waitForManifest() async throws {
        for _ in 0..<100 { if manifest != nil { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Missing delayed request")
    }
    func testRevisitedClassReappearsWithoutSearchingOrCheckingAgain() async throws {
        let model = try fixture(); defer { close(model) }
        await model.refreshSchedule()
        let profile = RMPProfile(id: "fixture-profile", firstName: "Alpha", lastName: "Fixture", school: "Fixture school", schoolID: nil, department: "Math", rating: 4, difficulty: 2, ratingCount: 1, wouldTakeAgain: nil, reviews: [])
        model.professors[0].profile = profile; model.professors[0].state = .ready
        model.selectedID = model.professors[0].id
        let course = try XCTUnwrap(model.course)
        model.goHome()
        XCTAssertFalse(model.showingResults)
        let before = calls
        model.openClass(course)
        XCTAssertTrue(model.showingResults)
        XCTAssertFalse(model.busy, "Every professor was already checked")
        XCTAssertEqual(model.professors.first?.profile?.id, "fixture-profile")
        XCTAssertEqual(model.selectedID, "alpha fixture")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls, before, "No new schedule search for a class revisited this session")
    }

    func testRefreshPreservesProfileSelectionFiltersAndReviewsButRemovesChangedAssignments() async throws {
        let model = try fixture(); defer { close(model) }
        await model.refreshSchedule()
        let review = Review(id: "fixture-review", course: "MATH005AH", text: "Fictional review", date: "2026-01-01", rating: 4, difficulty: 2, online: false)
        let profile = RMPProfile(id: "fixture-profile", firstName: "Alpha", lastName: "Fixture", school: "Fixture school", schoolID: nil, department: "Math", rating: 4, difficulty: 2, ratingCount: 1, wouldTakeAgain: nil, reviews: [review])
        model.professors[0].profile = profile; model.professors[0].state = .ready; model.professors[0].reviewsComplete = true
        model.selectedID = model.professors[0].id; model.availableDays = [.monday]; model.sort = .difficulty
        let generation = model.professors[0].generation
        seats = 7; await model.refreshSchedule()
        XCTAssertEqual(model.selectedID, "alpha fixture")
        XCTAssertEqual(model.professors[0].profile, profile); XCTAssertTrue(model.professors[0].reviewsComplete)
        XCTAssertEqual(model.professors[0].generation, generation)
        XCTAssertEqual(model.professors[0].sections[0].details?.seatsOpen, 7)
        XCTAssertEqual(model.availableDays, [.monday]); XCTAssertEqual(model.sort, .difficulty)
        instructorName = "Beta Fixture"; version = "c2"; await model.refreshSchedule()
        XCTAssertNil(model.selectedID); XCTAssertNil(model.professors[0].profile)
        XCTAssertNotEqual(model.professors[0].generation, generation)
        XCTAssertFalse(model.summariesEnabled)
    }
    func testTermDiscoveryPreservesSelectionAndFailureRetainsPublishedTerms() async throws {
        let model = try fixture(); defer { close(model) }
        await model.loadTerms(refresh: true)
        XCTAssertEqual(model.terms.map(\.termCode), ["202730", "202670"])
        XCTAssertEqual(model.termID, "202670")
        fail = true
        await model.loadTerms(refresh: true, quietly: true)
        XCTAssertEqual(model.terms.count, 2); XCTAssertEqual(model.termID, "202670")
        XCTAssertNil(model.error)
    }
    func testActivationRetriesFailedInitialTermDiscovery() async throws {
        let model = try fixture(); defer { close(model) }
        model.terms = []; model.termID = ""; fail = true
        await model.loadTerms()
        XCTAssertNotNil(model.error); XCTAssertTrue(model.terms.isEmpty)
        fail = false
        await model.refreshPublishedTermsIfNeeded(onActivation: true)
        XCTAssertEqual(model.terms.count, 2); XCTAssertEqual(model.termID, "202730")
        XCTAssertNil(model.error)
    }
    func testUpdatedMeetingThatHidesSelectionReturnsToOverview() async throws {
        let model = try fixture(); defer { close(model) }
        await model.refreshSchedule(); model.selectedID = model.professors[0].id; model.availableDays = [.monday]
        day = "fri"; version = "c2"; await model.refreshSchedule()
        XCTAssertNil(model.selectedID); XCTAssertTrue(model.filtered.isEmpty)
    }
    func testSupersededRefreshCannotPublishOrBackOffNewSearch() async throws {
        let model = try fixture(); defer { close(model) }
        await model.refreshSchedule(); let before = model.professors
        hold = true
        let refresh = Task { await model.refreshSchedule() }
        try await waitForManifest()
        model.changeSearch(); model.scheduleMetadata = nil
        instructorName = "Wrong Fixture"; version = "c2"
        respond(manifest!); manifest = nil
        await refresh.value
        XCTAssertEqual(model.professors.map(\.generation), before.map(\.generation)); XCTAssertNil(model.scheduleMetadata)
        XCTAssertEqual(model.scheduleRetrySeconds, 60)
    }
    func testSupersededInitialSearchCannotPublishScheduleMetadata() async throws {
        let model = try fixture(); defer { close(model) }
        model.input = "MATH 005AH"; hold = true
        model.start()
        try await waitForManifest()
        model.changeSearch()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(model.scheduleMetadata); XCTAssertFalse(model.showingResults)
        XCTAssertTrue(model.professors.isEmpty)
        manifest = nil
    }
    func testConcurrentRefreshIsBoundedAndCancellationDoesNotBecomeFailure() async throws {
        let model = try fixture(); defer { close(model) }
        await model.refreshSchedule(); hold = true; let before = calls
        let refresh = Task { await model.refreshSchedule() }
        try await waitForManifest()
        await model.refreshSchedule()
        XCTAssertEqual(calls, before + 1)
        refresh.cancel(); await refresh.value
        XCTAssertEqual(model.scheduleRetrySeconds, 60)
        manifest = nil
    }
    func testOfflineFailureRetainsScheduleExpiresCountsAndRecovers() async throws {
        let model = try fixture(); defer { close(model) }
        await model.refreshSchedule(); let checked = model.scheduleMetadata!.checkedAt!
        model.expireAvailability(at: checked.addingTimeInterval(899))
        XCTAssertEqual(model.professors[0].sections[0].details?.seatsOpen, 3)
        model.expireAvailability(at: checked.addingTimeInterval(900))
        XCTAssertNil(model.professors[0].sections[0].details?.seatsOpen)
        XCTAssertNil(model.professors[0].sections[0].details?.waitlistCount)
        fail = true; await model.refreshSchedule()
        XCTAssertEqual(model.professors.count, 1); XCTAssertEqual(model.scheduleRetrySeconds, 120)
        fail = false; seats = 5; await model.refreshSchedule()
        XCTAssertEqual(model.professors[0].sections[0].details?.seatsOpen, 5)
        XCTAssertEqual(model.scheduleRetrySeconds, 60)
    }
}
