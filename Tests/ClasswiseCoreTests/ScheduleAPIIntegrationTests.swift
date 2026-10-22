import Foundation
import XCTest
@testable import ClasswiseCore

private final class ScheduleFixtureProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class ScheduleAPIIntegrationTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_792_526_400)
    override func tearDown() { ScheduleFixtureProtocol.handler = nil }
    private func client(cache: URL? = nil) -> ScheduleAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScheduleFixtureProtocol.self]
        let instant = instant
        return ScheduleAPIClient(base: URL(string: "https://schedule.invalid"), key: "fixture-key",
            session: URLSession(configuration: config), cacheDirectory: cache, now: { instant })
    }
    private func envelope(_ data: Any, term: String = "202670", catalog: String = "c1", availability: String = "a1", stale: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": data, "meta": ["term": term, "catalogVersion": catalog,
            "availabilityVersion": availability, "sourceCheckedAt": ISO8601DateFormatter().string(from: instant), "stale": stale]])
    }
    private var catalog: [[String: Any]] { [["key": "MATH 005AH", "subject": "MATH", "number": "005AH", "title": "Fictional calculus"]] }
    private func section(names: [String] = ["Alpha Fixture", "Beta Fixture"], meetings: Bool = true, seats: Int = 3) -> [[String: Any]] {
        [["crn": "12345", "courseKey": "MATH 005AH", "units": "4", "instructors": names.enumerated().map { ["assignmentId": "fixture-\($0.offset)", "role": "primary", "name": $0.element] },
          "meetings": meetings ? [["days": ["mon", "wed"], "beginTime": "0900", "endTime": "1030", "formatCode": "L", "building": "Fixture Hall", "room": "100", "sourceFields": ["ptrmDesc": "Full term"]]] : [],
          "availability": ["statusCode": "O", "seatsAvailable": seats, "capacity": 30, "waitlistCount": 2, "waitlistCapacity": 10]]]
    }
    func testCatalogAndAvailabilityVersionsFetchOnlyChangedResourcesAndKeepAssignments() async throws {
        let client = client(); var version = "c1", availability = "a1", requests: [String] = []
        ScheduleFixtureProtocol.handler = { [self] request in
            XCTAssertEqual(request.url?.host, "schedule.invalid")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "fixture-key")
            let path = request.url!.path; requests.append(path)
            let data: Any
            if path.hasSuffix("manifest") { data = [:] }
            else if path.hasSuffix("catalog") { data = catalog }
            else if path.hasSuffix("availability") { data = [["crn": "12345", "availability": ["seatsAvailable": 7, "capacity": 30]]] }
            else { data = section() }
            return (200, [:], try envelope(data, catalog: version, availability: availability))
        }
        let initial = try await client.courseRows(term: "202670", query: "math5ah")
        let professors = ScheduleParser.professors(rows: initial.rows, course: try Course("MATH 005AH"))
        XCTAssertEqual(professors.map(\.name), ["Alpha Fixture", "Beta Fixture"])
        XCTAssertTrue(professors.allSatisfy { $0.sections[0].schedule?.days == [.monday, .wednesday] })
        XCTAssertTrue(professors.allSatisfy { $0.sections[0].details?.seatsOpen == 3 })
        XCTAssertTrue(professors.allSatisfy { $0.sections[0].details?.termPart == "Full term" })
        requests = []; _ = try await client.courseRows(term: "202670", query: "MATH 005AH")
        XCTAssertEqual(requests.count, 1, "Unchanged metadata must not fetch catalog or sections")
        availability = "a2"; requests = []
        let changed = try await client.courseRows(term: "202670", query: "MATH 005AH")
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.last!.hasSuffix("availability"))
        XCTAssertEqual(changed.rows.first?["seatsAvail"], "7")
        version = "c2"; requests = []; _ = try await client.courseRows(term: "202670", query: "MATH 005AH")
        XCTAssertEqual(requests.count, 3)
    }
    func testStaleUnknownMeetingsAndEmptyAssignmentsDoNotDisappearOrInventCounts() async throws {
        let client = client()
        ScheduleFixtureProtocol.handler = { [self] request in
            let path = request.url!.path
            return (200, [:], try envelope(path.hasSuffix("manifest") ? [:] : path.hasSuffix("catalog") ? catalog : section(names: [], meetings: false), stale: true))
        }
        let result = try await client.courseRows(term: "202670", query: "MATH 005AH")
        let professors = ScheduleParser.professors(rows: result.rows, course: try Course("MATH 005AH"))
        XCTAssertEqual(professors.count, 1)
        XCTAssertFalse(professors[0].canSearch)
        XCTAssertNil(professors[0].sections[0].details?.seatsOpen)
        XCTAssertNil(professors[0].sections[0].details?.waitlistCount)
        XCTAssertEqual(professors[0].sections[0].delivery, "Delivery details unavailable")
    }
    func testSemestersAndCatalogPublicationRacesAreRejected() async throws {
        let client = client(); var wrongTerm = true
        ScheduleFixtureProtocol.handler = { [self] request in
            let path = request.url!.path
            return (200, [:], try envelope(path.hasSuffix("catalog") ? catalog : [:], term: wrongTerm ? "202730" : "202670", catalog: path.hasSuffix("catalog") ? "c2" : "c1"))
        }
        do { _ = try await client.courseRows(term: "202670", query: "MATH 005AH"); XCTFail("Accepted another semester") } catch {}
        wrongTerm = false
        do { _ = try await client.courseRows(term: "202670", query: "MATH 005AH"); XCTFail("Mixed catalog generations") } catch {}
    }
    func testRateLimitCooldownAndFailuresNeverFallBackToPCC() async throws {
        let client = client(); var calls = 0
        ScheduleFixtureProtocol.handler = { request in
            calls += 1; XCTAssertEqual(request.url?.host, "schedule.invalid")
            return (429, ["Retry-After": "120"], Data())
        }
        for _ in 0..<2 { do { _ = try await client.terms(); XCTFail("Expected failure") } catch {} }
        XCTAssertEqual(calls, 1)
    }
    func testCatalogDiskCacheIsCourseOnlyAndRevalidatesBeforePublishingSuggestions() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let client = client(cache: cache); var title = "First fixture", offline = false
        ScheduleFixtureProtocol.handler = { [self] request in
            if offline { throw URLError(.notConnectedToInternet) }
            return (200, [:], try envelope([["key": "MATH 005AH", "subject": "MATH", "number": "005AH", "title": title]]))
        }
        _ = try await client.catalogRows(term: "202670")
        title = "Updated fixture"
        let refreshed = try await client.catalogRows(term: "202670")
        XCTAssertEqual(CourseSuggestions.catalog(rows: refreshed).first?.title, title)
        offline = true
        let cached = try await client.catalogRows(term: "202670")
        XCTAssertEqual(CourseSuggestions.catalog(rows: cached).first?.title, title)
        let text = try String(contentsOf: cache.appendingPathComponent("202670.json"))
        XCTAssertFalse(text.contains("instructor")); XCTAssertFalse(text.contains("seats"))
        do { _ = try await client.catalogRows(term: "202730"); XCTFail("Substituted cached semester") } catch {}
    }
    func testConditionalReadReusesBodyOnlyForMatchingResource() async throws {
        let client = client(); var calls = 0
        ScheduleFixtureProtocol.handler = { [self] request in
            calls += 1
            if calls == 1 { return (200, ["ETag": "fixture-tag"], try envelope(catalog)) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "fixture-tag")
            return (304, [:], Data())
        }
        _ = try await client.catalogRows(term: "202670")
        let reused = try await client.catalogRows(term: "202670")
        XCTAssertEqual(CourseSuggestions.catalog(rows: reused).first?.course.key, "MATH005AH")
    }
}
