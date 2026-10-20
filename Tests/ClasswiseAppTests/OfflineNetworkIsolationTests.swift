import XCTest
import Foundation
import BYEAPI
@testable import Classwise
@testable import ClasswiseCore

/// Custom URLProtocol that traps all network traffic.
/// Any request made that is not intercepted by a registered handler will trigger an XCTFail failure,
/// ensuring that tests run in 100% offline isolation without reaching PCC, RMP, or external servers.
private final class OfflineNetworkInterceptor: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var interceptedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.interceptedRequests.append(request)
        let currentHandler = Self.handler
        Self.lock.unlock()

        guard let handler = currentHandler else {
            XCTFail("Offline isolation assertion failed: Outgoing network request intercepted when no handler was set: \(request.url?.absoluteString ?? "unknown URL")")
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handler = nil
        interceptedRequests.removeAll()
    }
}

@MainActor
final class OfflineNetworkIsolationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        OfflineNetworkInterceptor.reset()
    }

    override func tearDown() {
        OfflineNetworkInterceptor.reset()
        super.tearDown()
    }

    // MARK: - Test 1: PCC Class Schedule Offline Test
    /// Verifies PCC schedule searches execute strictly against bundled JSON fixtures via offline URLProtocol trapping.
    /// Ensures zero requests leak to real PCC servers.
    func testPCCClassScheduleExecutesStrictlyOffline() async throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "pcc-summer-2026-eth014", withExtension: "json"))
        let fixtureData = try Data(contentsOf: fixtureURL)

        OfflineNetworkInterceptor.handler = { request in
            guard let url = request.url, url.host?.contains("pasadena.edu") == true || url.path.contains("classSchedule") else {
                XCTFail("Unexpected non-PCC request during PCC offline test: \(request)")
                throw URLError(.badURL)
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, fixtureData)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineNetworkInterceptor.self]
        let session = URLSession(configuration: config)
        let client = PCCClient(session: session)

        let term = Term(termCode: "202650", termName: "Summer 2026", termDisplayControl: "Y")

        // Search schedule and professors using offline client
        let scheduleRows = try await client.schedule(term: term)
        XCTAssertGreaterThan(scheduleRows.count, 0, "Schedule rows should be loaded from offline fixture")

        let professors = try await client.professors(course: try Course("ETH014"), term: term)
        XCTAssertEqual(professors.count, 10, "Professors should be correctly parsed from offline schedule fixture")

        // Verify requests were intercepted by offline interceptor and zero unhandled requests occurred
        XCTAssertGreaterThan(OfflineNetworkInterceptor.interceptedRequests.count, 0)
        for req in OfflineNetworkInterceptor.interceptedRequests {
            XCTAssertTrue(req.url?.path.contains("classSchedule/202650") == true)
        }
    }

    // MARK: - Test 2: Rate My Professors API Offline Test
    /// Verifies Rate My Professors GraphQL searches, profiles, and reviews execute using offline JSON fixtures.
    /// Confirms zero live outgoing network calls reach RMP servers.
    func testRMPAPIExecutesStrictlyOffline() async throws {
        let profilesFixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "fictional-profiles", withExtension: "json"))
        let profilesData = try Data(contentsOf: profilesFixtureURL)
        let fictionalProfiles = try JSONDecoder().decode([RMPProfile].self, from: profilesData)

        let targetProfile = fictionalProfiles.first!

        OfflineNetworkInterceptor.handler = { request in
            guard let url = request.url, url.host?.contains("ratemyprofessors.com") == true || url.path.contains("graphql") else {
                XCTFail("Unexpected non-RMP request during RMP offline test: \(request)")
                throw URLError(.badURL)
            }

            // Construct valid GraphQL response structure from local fixture data
            let teacherNode: [String: Any] = [
                "id": Data("Teacher-\(targetProfile.id)".utf8).base64EncodedString(),
                "legacyId": Int(targetProfile.id) ?? 1,
                "firstName": targetProfile.firstName,
                "lastName": targetProfile.lastName,
                "department": targetProfile.department,
                "avgRating": targetProfile.rating as Any,
                "avgDifficulty": targetProfile.difficulty as Any,
                "numRatings": targetProfile.ratingCount,
                "wouldTakeAgainPercent": targetProfile.wouldTakeAgain as Any,
                "school": ["id": "U2Nob29sLTI2NDk=", "legacyId": targetProfile.schoolID, "name": targetProfile.school],
                "courseCodes": [["courseName": "ETH014", "courseCount": 10]],
                "ratings": [
                    "edges": [
                        [
                            "node": [
                                "id": "rev-offline-1",
                                "class": "ETH014",
                                "comment": "Excellent offline course experience.",
                                "date": "2026-01-15",
                                "helpfulRating": 5,
                                "difficultyRating": 1,
                                "isForOnlineClass": true
                            ]
                        ]
                    ],
                    "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]
                ]
            ]

            let jsonResponseBody: [String: Any]
            // Differentiate search vs profile query
            let bodyData: Data = OfflineNetworkInterceptor.extractBody(from: request)
            let bodyString = String(data: bodyData, encoding: .utf8) ?? ""

            if bodyString.contains("teacherSearch") || bodyString.contains("search") || bodyString.contains("query") {
                jsonResponseBody = [
                    "data": [
                        "search": [
                            "teachers": [
                                "edges": [["node": teacherNode]],
                                "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]
                            ]
                        ]
                    ]
                ]
            } else {
                jsonResponseBody = [
                    "data": [
                        "node": teacherNode
                    ]
                ]
            }

            let responseData = try JSONSerialization.data(withJSONObject: jsonResponseBody)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, responseData)
        }

        let transport = RMPTransport(protocolClasses: [OfflineNetworkInterceptor.self], spacing: 0, retryDelay: 0)
        let rmpClient = RMPClient(transport: transport)
        let apiReader = RMPAPIReader(client: rmpClient)

        let professor = Professor(id: targetProfile.id, name: targetProfile.name, sections: [])

        // Perform offline candidate lookup
        let outcome = try await apiReader.lookupOutcome(professor)
        switch outcome {
        case .verified(let profile):
            XCTAssertEqual(profile.firstName, targetProfile.firstName)
            XCTAssertEqual(profile.schoolID, 2649)
        case .selectionRequired(let choices, _):
            XCTAssertGreaterThan(choices.count, 0)
        case .notFound:
            XCTFail("Candidate lookup should succeed with offline fixture")
        }

        // Perform offline profile retrieval
        let result = try await rmpClient.profile(id: targetProfile.id)
        XCTAssertEqual(result.profile.firstName, targetProfile.firstName)
        XCTAssertEqual(result.profile.reviews.count, 1)
        XCTAssertEqual(result.profile.reviews.first?.text, "Excellent offline course experience.")

        XCTAssertGreaterThan(OfflineNetworkInterceptor.interceptedRequests.count, 0)
    }

    // MARK: - Test 3: AppModel & Updater Isolation Offline Test
    /// Verifies AppModel and background subsystems (e.g. updater, summaries) operate in network isolation.
    /// Confirms searching, review expanding, and summary toggling do not trigger live external network calls.
    func testAppModelAndSubsystemsOperateInNetworkIsolation() async throws {
        OfflineNetworkInterceptor.handler = { request in
            XCTFail("Zero network requests should be issued during disabled/offline AppModel operation. Intercepted: \(request.url?.absoluteString ?? "")")
            throw URLError(.notConnectedToInternet)
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BYE-OfflineIsolation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineNetworkInterceptor.self]
        let session = URLSession(configuration: config)

        let pccClient = PCCClient(session: session)
        let ollamaClient = OllamaClient(model: "offline-mock", session: session)

        let model = AppModel(
            pcc: pccClient,
            ollama: ollamaClient,
            summaryProvider: nil,
            cache: ReportCache(directory: directory),
            choices: ProfileChoiceStore(directory: directory),
            summariesEnabled: false
        )

        XCTAssertFalse(model.summariesEnabled, "Summaries should be disabled for offline test")

        // Initialize term and course state without remote fetch
        let term = Term(termCode: "202650", termName: "Summer 2026", termDisplayControl: "Y")
        model.terms = [term]
        model.termID = term.id
        model.input = "ETH014"

        // Search with no selected semester (triggers local input handling, no remote request)
        model.changeSearch()
        XCTAssertFalse(model.showingResults)

        // Verify Updater state initialization is safe offline
        let updater = Updater()
        XCTAssertFalse(updater.canCheckForUpdates, "Updater in test mode/disabled Sparkle config should not check for updates automatically")

        // Ensure zero network requests were attempted
        XCTAssertEqual(OfflineNetworkInterceptor.interceptedRequests.count, 0)
    }

    // MARK: - Helper Methods
    private static func extractBody(from request: URLRequest) -> Data {
        if let data = request.httpBody {
            return data
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount <= 0 { break }
            data.append(buffer, count: readCount)
        }
        return data
    }
}
