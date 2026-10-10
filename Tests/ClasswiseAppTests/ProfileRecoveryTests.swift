import XCTest
@testable import Classwise
@testable import ClasswiseCore

@MainActor
final class RecoveryHub {
    var options: [RMPProfile] = []
    var candidateCalls = 0
    var previewCalls: [String] = []
    var waiting: [String: CheckedContinuation<[RMPProfile], Error>] = [:]
    var holdCandidates = false
    var previewError: Error?
    var expansion: CheckedContinuation<RMPProfile, Error>?
    var expansionCallback: ((RMPProfile) -> Void)?
    var holdExpansion = false
    func reader() -> RecoveryReader { RecoveryReader(self) }
}
@MainActor
final class RecoveryReader: ProfileReader {
    let hub: RecoveryHub
    init(_ hub: RecoveryHub) { self.hub = hub }
    func stop() { } // Deliberately allow late completion to exercise generation guards.
    func candidates(_ professor: Professor, discoverAll: Bool) async throws -> [RMPProfile] {
        hub.candidateCalls += 1
        if hub.holdCandidates {
            return try await withCheckedThrowingContinuation { hub.waiting[professor.id] = $0 }
        }
        return IdentityMatcher.eligible(name: professor.name, candidates: hub.options)
    }
    func preview(_ professor: Professor, profileID: String) async throws -> RMPProfile {
        hub.previewCalls.append(profileID)
        if let error = hub.previewError { throw error }
        guard let profile = hub.options.first(where: { $0.id == profileID }), IdentityMatcher.matches(name: professor.name, profile: profile) else {
            throw ProfileIdentityMismatch()
        }
        return profile
    }
    func expand(_ professor: Professor, profile: RMPProfile, onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile {
        if hub.holdExpansion {
            return try await withCheckedThrowingContinuation { hub.expansion = $0 }
        }
        return profile
    }
}

final class ProfileRecoveryTests: XCTestCase {
    private func profile(_ id: String, department: String = "Math", lastName: String = "Instructor") -> RMPProfile {
        RMPProfile(id: id, firstName: "Fictional", lastName: lastName, school: "Pasadena City College", schoolID: 2649,
                   department: department, rating: 4, difficulty: 3, ratingCount: 0, wouldTakeAgain: nil, reviews: [])
    }
    @MainActor
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() {
            if Date() > deadline { XCTFail("Recovery operation timed out"); throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    @MainActor
    private func model(_ hub: RecoveryHub, directory: URL) throws -> AppModel {
        let model = AppModel(cache: ReportCache(directory: directory), choices: ProfileChoiceStore(directory: directory), makeReader: { hub.reader() })
        model.course = try Course("MATH005A"); model.showingResults = true
        var professor = Professor(id: "instructor", name: "Fictional Instructor", sections: [])
        professor.subjectCode = "MATH"; professor.subjectDescription = "Mathematics"
        model.professors = [professor]
        return model
    }
    @MainActor
    func testSearchConsultsManualChoiceBeforeCacheAndRefreshReverifies() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = RecoveryHub(); hub.options = [profile("1"), profile("2")]
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [RecoveryScheduleProtocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let cache = ReportCache(directory: directory), store = ProfileChoiceStore(directory: directory), course = try Course("MATH005A")
        for profile in hub.options { cache.save(CachedReport(profile: profile, summary: nil, checkedAt: Date()), name: "Fictional Instructor", course: course) }
        store.save(profileID: "1", name: "Fictional Instructor", subject: "MATH")
        let model = AppModel(pcc: PCCClient(session: session), cache: cache, choices: store, makeReader: { hub.reader() })
        defer { model.cancel() }
        model.terms = try JSONDecoder().decode([Term].self, from: Data("[{\"termCode\":\"202710\",\"termName\":\"Fictional Term\",\"termDisplayControl\":\"Y\"}]".utf8))
        model.termID = "202710"; model.input = "MATH005A"
        model.start(); try await wait { !model.busy }
        XCTAssertEqual(model.professors.first?.profile?.id, "1", "Preference must override automatic cache index 2")
        XCTAssertTrue(hub.previewCalls.isEmpty)
        model.start(force: true); try await wait { !model.busy }
        XCTAssertEqual(hub.previewCalls, ["1"], "Fresh retrieval revalidates the remembered identity")
        XCTAssertEqual(model.professors.first?.profile?.id, "1")
    }
    @MainActor
    func testSingleCandidateVerifiesAndMultipleDepartmentsAlwaysRequireSelection() async throws {
        let hub = RecoveryHub(), reader = hub.reader()
        let professor = Professor(id: "x", name: "Fictional Instructor", sections: [])
        hub.options = [profile("1")]
        guard case .verified(let single) = try await reader.lookupOutcome(professor) else { return XCTFail("Expected verified") }
        XCTAssertEqual(single.id, "1")
        hub.options.append(profile("2", department: "History"))
        guard case .selectionRequired(let options, _) = try await reader.lookupOutcome(professor) else { return XCTFail("Expected choice") }
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(hub.previewCalls, ["1"], "Ambiguity must not open a preferred department")
    }
    @MainActor
    func testInvalidPreferenceRequiresSelectionButTemporaryFailureDoesNotInvalidate() async throws {
        let hub = RecoveryHub(), professor = Professor(id: "x", name: "Fictional Instructor", sections: [])
        hub.options = [profile("1"), profile("2")]; hub.previewError = ProfileIdentityMismatch()
        guard case .selectionRequired(let options, let invalidated) = try await hub.reader().lookupOutcome(professor, preferredProfileID: "1") else { return XCTFail("Expected choice") }
        XCTAssertEqual(invalidated, "1"); XCTAssertEqual(options.map(\.id), ["2"])
        hub.previewError = URLError(.timedOut)
        guard case .unavailable = try await hub.reader().lookupOutcome(professor, preferredProfileID: "1") else { return XCTFail("Expected retry") }
    }
    @MainActor
    func testRetriesAreBoundedDeduplicatedAndPreserveOtherProfessors() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = RecoveryHub(); hub.holdCandidates = true
        let model = try model(hub, directory: directory)
        defer { model.cancel() }
        model.professors = (1...4).map { Professor(id: "\($0)", name: "Fictional Instructor", sections: []) }
        for id in ["1", "2", "3", "4", "1", "2"] { model.retryProfessor(id: id) }
        try await wait { hub.waiting.count == 2 }
        XCTAssertEqual(hub.candidateCalls, 2)
        XCTAssertTrue(model.busy)
        let first = hub.waiting.removeValue(forKey: "1")!; first.resume(returning: [])
        try await wait { hub.waiting["3"] != nil }
        XCTAssertEqual(model.professors[0].state, .unavailable)
        XCTAssertEqual(hub.candidateCalls, 3)
        let second = hub.waiting.removeValue(forKey: "2")!; second.resume(returning: [])
        try await wait { hub.waiting["4"] != nil }
        for id in ["3", "4"] { hub.waiting.removeValue(forKey: id)!.resume(returning: []) }
        try await wait { !model.busy }
        XCTAssertEqual(hub.candidateCalls, 4)
    }
    @MainActor
    func testChooserClosePreservesUnresolvedStateAndChoiceSavesOnlyAfterVerification() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = RecoveryHub(); hub.options = [profile("1"), profile("2", department: "History")]
        let model = try model(hub, directory: directory); defer { model.cancel() }
        model.retryProfessor(id: "instructor"); try await wait { !model.busy }
        XCTAssertEqual(model.professors[0].state, .selectionRequired)
        model.openChooser(id: "instructor"); model.chooserID = nil
        XCTAssertEqual(model.professors[0].state, .selectionRequired)
        model.openChooser(id: "instructor"); XCTAssertEqual(model.chooserProfessor?.candidates.count, 2)
        hub.previewError = URLError(.timedOut)
        model.chooseProfile(id: "instructor", profileID: "2"); try await wait { !model.busy }
        let choices = ProfileChoiceStore(directory: directory)
        XCTAssertNil(choices.choice(name: "Fictional Instructor", subject: "MATH"))
        XCTAssertEqual(model.professors[0].state, .unavailable)
        hub.previewError = nil
        model.retryProfessor(id: "instructor"); try await wait { !model.busy }
        XCTAssertEqual(model.professors[0].profile?.id, "2", "Retry verifies the explicitly chosen profile")
        XCTAssertEqual(choices.choice(name: "Fictional Instructor", subject: "MATH"), "2")
    }
    @MainActor
    func testProfileReplacementClearsDataAndRejectsLateReviewResponse() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = RecoveryHub(); hub.options = [profile("1"), profile("2")]; hub.holdExpansion = true
        let model = try model(hub, directory: directory); defer { model.cancel() }
        // Include a PCC section so selection resolves through the real filtered list.
        model.professors[0].sections = [Section(crn: "1", title: "Fictional", start: "", end: "", formats: ["OD"], meetings: [], status: "O")]
        model.professors[0].profile = hub.options[0]; model.professors[0].candidates = hub.options
        model.professors[0].state = .ready; model.selectedID = "instructor"
        model.requestSelectedReport(); try await wait { hub.expansion != nil }
        model.professors[0].summaryIssue = "old failure"; model.professors[0].reviewIssue = "old failure"
        model.chooseProfile(id: "instructor", profileID: "2")
        XCTAssertNil(model.professors[0].profile); XCTAssertNil(model.professors[0].summary)
        XCTAssertNil(model.professors[0].summaryIssue); XCTAssertNil(model.professors[0].reviewIssue)
        XCTAssertFalse(model.professors[0].reviewsComplete)
        model.selectedID = nil
        try await wait { !model.busy }
        hub.expansion!.resume(returning: hub.options[0]); hub.expansion = nil
        try await wait { !model.loadingDetails }
        XCTAssertEqual(model.professors[0].profile?.id, "2")
        let cache = ReportCache(directory: directory)
        XCTAssertEqual(cache.load(name: "Fictional Instructor", course: try Course("MATH005A"), subject: "MATH")?.profile.id, "2")
        XCTAssertNil(cache.load(name: "Fictional Instructor", course: try Course("MATH005A"), subject: "MATH", preferredProfileID: "1"))
    }
    @MainActor
    func testSearchCancellationRejectsLatePreviewAndLeavesRetryAvailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = RecoveryHub(); hub.holdCandidates = true; hub.options = [profile("1")]
        let model = try model(hub, directory: directory)
        model.retryProfessor(id: "instructor"); try await wait { !hub.waiting.isEmpty }
        model.cancel()
        hub.waiting.removeValue(forKey: "instructor")!.resume(returning: hub.options)
        await Task.yield()
        XCTAssertNil(model.professors[0].profile); XCTAssertEqual(model.professors[0].state, .pending)
        XCTAssertFalse(model.busy)
        XCTAssertNil(ReportCache(directory: directory).load(name: "Fictional Instructor", course: try Course("MATH005A"), subject: "MATH"))
    }
    @MainActor
    func testFreshAmbiguityClearsPriorAutomaticReportUntilExplicitChoice() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = RecoveryHub(); hub.options = [profile("1"), profile("2")]
        let model = try model(hub, directory: directory); defer { model.cancel() }
        model.professors[0].profile = hub.options[0]; model.professors[0].state = .ready
        model.professors[0].summary = ReviewSummary(overview: "Old fictional summary", positives: [], concerns: [], analyzedCount: 0, exactCourseCount: 0, generatedAt: Date())
        model.retryProfessor(id: "instructor"); try await wait { !model.busy }
        XCTAssertEqual(model.professors[0].state, .selectionRequired)
        XCTAssertNil(model.professors[0].profile); XCTAssertNil(model.professors[0].summary)
        XCTAssertEqual(model.professors[0].candidates.count, 2)
    }
    @MainActor
    func testFreshRetryClearsExistingSummaryWhenReviewEvidenceChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = RecoveryHub(); hub.options = [profile("1")]
        let model = try model(hub, directory: directory); defer { model.cancel() }
        model.professors[0].profile = hub.options[0]
        model.professors[0].summary = ReviewSummary(overview: "Old fictional summary", positives: [], concerns: [], analyzedCount: 0, exactCourseCount: 0, generatedAt: Date())
        hub.options[0].reviews = [Review(id: "new", course: "MATH005A", text: "Fresh fictional evidence", date: "", rating: 4, difficulty: 2, online: nil)]
        model.retryProfessor(id: "instructor"); try await wait { !model.busy }
        XCTAssertNil(model.professors[0].summary)
        XCTAssertEqual(model.professors[0].profile?.reviews.first?.id, "new")
        XCTAssertNil(ReportCache(directory: directory).load(name: "Fictional Instructor", course: model.course!, subject: "MATH")?.summary)
    }
    @MainActor
    func testTemporaryFailurePreservesSavedPreferenceAndIdentityMismatchRemovesIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = RecoveryHub(); hub.options = [profile("1"), profile("2")]
        let model = try model(hub, directory: directory); defer { model.cancel() }
        let store = ProfileChoiceStore(directory: directory)
        store.save(profileID: "1", name: "Fictional Instructor", subject: "MATH")
        hub.previewError = URLError(.timedOut)
        model.retryProfessor(id: "instructor"); try await wait { !model.busy }
        XCTAssertEqual(store.choice(name: "Fictional Instructor", subject: "MATH"), "1")
        hub.previewError = ProfileIdentityMismatch()
        model.retryProfessor(id: "instructor"); try await wait { !model.busy }
        XCTAssertNil(store.choice(name: "Fictional Instructor", subject: "MATH"))
        XCTAssertEqual(model.professors[0].state, .selectionRequired)
        XCTAssertEqual(model.professors[0].candidates.map(\.id), ["2"])
    }
}

private final class RecoveryScheduleProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let rows = """
        [{"subjCode":"MATH","subjDesc":"Mathematics","courseNumbDisplay":"005A","crn":"1","pfaName":"Fictional Instructor","fwSectOpenInd":"O"}]
        """
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(rows.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
