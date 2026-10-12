import XCTest
import Foundation
@testable import BYEAPI
import ClasswiseCore

final class RMPClientTests: XCTestCase {
    private func transport(_ server: APIServer) -> RMPTransport {
        APIProtocol.server = server
        return RMPTransport(protocolClasses: [APIProtocol.self], spacing: 0, retryDelay: 0)
    }
    private func teacher(_ id: Int = 42) -> [String: Any] {
        ["id": Data("Teacher-\(id)".utf8).base64EncodedString(), "legacyId": id,
         "firstName": "Fictional", "lastName": "Instructor", "department": NSNull(),
         "avgRating": 4.5, "avgDifficulty": 2.1, "numRatings": 55, "wouldTakeAgainPercent": 88,
         "school": ["id": "U2Nob29sLTI2NDk=", "legacyId": 2649, "name": "Pasadena City College"],
         "courseCodes": [["courseName": "MATH005A", "courseCount": 20]]]
    }
    private func profileData(_ change: ((inout [String: Any]) -> Void)? = nil) throws -> Data {
        var node = teacher()
        node["ratings"] = ["edges": [["node": ["id": "source-review-1", "class": "MATH005A",
                     "comment": "Original wording & punctuation.", "date": "invalid source date",
                     "helpfulRating": 4, "difficultyRating": 2, "isForOnlineClass": true]]],
                           "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]
        change?(&node)
        return try JSONSerialization.data(withJSONObject: ["data": ["node": node]])
    }
    func testNativeSessionHasNoPersistentTrackingStores() {
        let config = RMPTransport.configuration()
        XCTAssertNil(config.httpCookieStorage); XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.httpCookieAcceptPolicy, .never)
        XCTAssertNil(config.urlCredentialStorage); XCTAssertNil(config.urlCache)
        XCTAssertEqual(config.httpMaximumConnectionsPerHost, 2)
        XCTAssertEqual(config.timeoutIntervalForRequest, 15)
        XCTAssertEqual(config.httpAdditionalHeaders?["User-Agent"] as? String, "BYE/0.2")
    }
    func testMinimalProfileRequestKeepsSourceValuesAndDoesNotSendCourseByDefault() async throws {
        let server = APIServer { _, _ in Reply(data: try self.profileData(), headers: ["Set-Cookie": "tracking=123; Path=/; Secure"]) }
        let client = RMPClient(transport: transport(server))
        for _ in 0..<2 {
            let result = try await client.profile(id: "42")
            XCTAssertEqual(result.profile.id, "42"); XCTAssertEqual(result.profile.department, "")
            XCTAssertEqual(result.profile.reviews.first?.id, "source-review-1")
            XCTAssertEqual(result.profile.reviews.first?.text, "Original wording & punctuation.")
            XCTAssertEqual(result.profile.reviews.first?.date, "invalid source date")
            XCTAssertEqual(result.profile.reviews.first?.rating, 4)
            XCTAssertEqual(result.profile.courseCounts?.first?.count, 20)
        }
        XCTAssertEqual(server.requests.count, 2)
        for request in server.requests {
            XCTAssertEqual(request.url, RMPTransport.endpoint); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Forwarded-For"))
            let body = try body(request), variables = try XCTUnwrap(body["variables"] as? [String: Any])
            XCTAssertEqual(Set(body.keys), ["query", "variables"])
            XCTAssertEqual(Set(variables.keys), ["id", "count"])
            XCTAssertEqual(variables["count"] as? Int, 3)
        }
    }
    func testExplicitFilterAndCursorAreSentOnlyWhenSuppliedAndCountIsCapped() async throws {
        let server = APIServer { _, _ in Reply(data: try self.profileData()) }
        let client = RMPClient(transport: transport(server))
        _ = try await client.profile(id: "42", count: 100, cursor: "next", courseFilter: "MATH005A")
        let vars = try XCTUnwrap(try body(server.requests[0])["variables"] as? [String: Any])
        XCTAssertEqual(vars["courseFilter"] as? String, "MATH005A")
        XCTAssertEqual(vars["cursor"] as? String, "next"); XCTAssertEqual(vars["count"] as? Int, 50)
    }
    func testSearchSendsOnlyNameSchoolAndPaginationAndRetainsDuplicateIDsForMatcher() async throws {
        let node = teacher()
        let data = try JSONSerialization.data(withJSONObject: ["data": ["search": ["teachers": ["edges": [["node": node], ["node": node]], "pageInfo": ["hasNextPage": false]]]]])
        let server = APIServer { _, _ in Reply(data: data) }
        let result = try await RMPClient(transport: transport(server)).search(name: "Fictional Instructor")
        XCTAssertEqual(IdentityMatcher.eligible(name: "Fictional Instructor", candidates: result.profiles).count, 1)
        let vars = try XCTUnwrap(try body(server.requests[0])["variables"] as? [String: Any])
        XCTAssertEqual(Set(vars.keys), ["query", "count"])
        let query = try XCTUnwrap(vars["query"] as? [String: Any])
        XCTAssertEqual(Set(query.keys), ["text", "schoolID"])
        XCTAssertEqual(query["schoolID"] as? String, "U2Nob29sLTI2NDk=")
    }
    func testMissingSearchConnectionAndGraphQLErrorsAreNotEmptyMatches() async throws {
        for (data, expected) in [(Data("{\"data\":{}}".utf8), RMPAPIError.malformedResponse),
                                 (Data("{\"errors\":[{\"message\":\"private query details\"}]}".utf8), .graphql)] {
            let server = APIServer { _, _ in Reply(data: data) }
            do { _ = try await RMPClient(transport: transport(server)).search(name: "Fictional Instructor"); XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? RMPAPIError, expected); XCTAssertFalse(error.localizedDescription.contains("private query")) }
            XCTAssertEqual(server.requests.count, 1)
        }
    }
    func testIdentityMustComeFromResponseAndAgreeWithExpectedID() async throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0.removeValue(forKey: "id"); $0.removeValue(forKey: "legacyId") },
            { $0["legacyId"] = 43 },
            { $0["id"] = "invalid" },
            { $0["id"] = Data("Teacher-43".utf8).base64EncodedString(); $0["legacyId"] = 43 }
        ]
        for change in changes {
            let server = APIServer { _, _ in Reply(data: try self.profileData(change)) }
            do { _ = try await RMPClient(transport: transport(server)).profile(id: "42"); XCTFail("Must reject identity") }
            catch { XCTAssertEqual(error as? RMPAPIError, .invalidIdentity) }
        }
    }
    func testInvalidSourceScoresRemainUnavailableAndMissingDateIsNotToday() async throws {
        let server = APIServer { _, _ in Reply(data: try self.profileData { node in
            node["avgRating"] = 10; node["wouldTakeAgainPercent"] = -1
            node["ratings"] = ["edges": [["node": ["id": "x", "comment": "Text", "helpfulRating": 0]]], "pageInfo": ["hasNextPage": false]]
        }) }
        let result = try await RMPClient(transport: transport(server)).profile(id: "42")
        XCTAssertNil(result.profile.rating); XCTAssertNil(result.profile.wouldTakeAgain)
        XCTAssertNil(result.profile.reviews.first?.rating); XCTAssertEqual(result.profile.reviews.first?.date, "")
    }
    func testPaginationRejectsRepeatedCursorAndDuplicateReviewIDs() async throws {
        for duplicate in [false, true] {
            let server = APIServer { _, _ in Reply(data: try self.profileData { node in
                var ratings = node["ratings"] as! [String: Any]
                if duplicate { let edges = ratings["edges"] as! [[String: Any]]; ratings["edges"] = edges + edges }
                else { ratings["pageInfo"] = ["hasNextPage": true, "endCursor": "same"] }
                node["ratings"] = ratings
            }) }
            do { _ = try await RMPClient(transport: transport(server)).profile(id: "42", cursor: "same"); XCTFail("Must stop pagination") }
            catch { XCTAssertEqual(error as? RMPAPIError, .pagination) }
        }
    }
    func testOversizedSourcePageCannotExceedRequestedPreview() async throws {
        let server = APIServer { _, _ in Reply(data: try self.profileData { node in
            var ratings = node["ratings"] as! [String: Any]
            ratings["edges"] = (0..<4).map { ["node": ["id": "review-\($0)", "comment": "Source text"]] }
            node["ratings"] = ratings
        }) }
        do { _ = try await RMPClient(transport: transport(server)).profile(id: "42"); XCTFail("Reject oversized preview") }
        catch { XCTAssertEqual(error as? RMPAPIError, .malformedResponse) }
        XCTAssertEqual(server.requests.count, 1)
    }
    func testAuditCanDisableAutomaticRetries() async throws {
        let server = APIServer { _, _ in Reply(status: 503) }
        APIProtocol.server = server
        let client = RMPClient(transport:RMPTransport(protocolClasses:[APIProtocol.self],spacing:0,retryDelay:0,maximumAttempts:1))
        do { _ = try await client.profile(id:"42"); XCTFail("Expected failure") } catch { }
        XCTAssertEqual(server.requests.count,1)
    }
    func testTransientHTTPFailuresRetryAtMostThreeTimes() async throws {
        let server = APIServer { _, attempt in Reply(data: Data("{}".utf8), status: attempt < 2 ? 503 : 200) }
        _ = try await transport(server).send(Data("{}".utf8))
        XCTAssertEqual(server.requests.count, 3)
        let failed = APIServer { _, _ in Reply(status: 503) }
        do { _ = try await transport(failed).send(Data()); XCTFail("Must fail") }
        catch { XCTAssertEqual(error as? RMPAPIError, .http(503)) }
        XCTAssertEqual(failed.requests.count, 3)
    }
    func testPermanentHTTPFailureAndLongRetryAfterDoNotRetryEarly() async throws {
        for status in [403, 429, 302] {
            let server = APIServer { _, _ in Reply(status: status, headers: ["Retry-After": "120", "Location": "https://unrelated.invalid/"]) }
            do { _ = try await transport(server).send(Data()); XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? RMPAPIError, .http(status)) }
            XCTAssertEqual(server.requests.count, 1)
            XCTAssertEqual(server.requests.first?.url, RMPTransport.endpoint)
        }
    }
    func testRetryAfterSupportsSecondsAndHTTPDates() {
        XCTAssertEqual(RMPTransport.retryAfter("2"), 2)
        XCTAssertEqual(RMPTransport.retryAfter("-2"), 0)
        XCTAssertNil(RMPTransport.retryAfter("invalid"))
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let delay = RMPTransport.retryAfter(parser.string(from: Date().addingTimeInterval(10)))!
        XCTAssertTrue((8...10).contains(delay))
    }
    func testRateLimitCooldownAlsoDelaysAnAlreadyReservedRequest() async throws {
        let gate = RequestGate(spacing: 0.05)
        try await gate.acquire()
        let start = Date()
        let reserved = Task { try await gate.acquire() }
        try await Task.sleep(for: .milliseconds(10))
        await gate.deferRequests(until: start.addingTimeInterval(0.15))
        try await reserved.value
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.14)
        await gate.release(); await gate.release()
    }
    func testSharedTransportBoundsConcurrencyAcrossManyCalls() async throws {
        let server = APIServer { _, _ in Reply(data: Data("{}".utf8), delay: 0.03) }
        let transport = transport(server)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try await transport.send(Data()) } }
            try await group.waitForAll()
        }
        XCTAssertEqual(server.requests.count, 8); XCTAssertEqual(server.maxActive, 2)
    }
    func testCancellationInterruptsRetryWaitWithoutAnotherRequest() async throws {
        let server = APIServer { _, _ in Reply(status: 429, headers: ["Retry-After": "10"]) }
        let transport = transport(server)
        let task = Task { try await transport.send(Data()) }
        while server.requests.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        try await Task.sleep(for: .milliseconds(20)); task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(server.requests.count, 1)
    }
    func testCancellationInterruptsQueuedRequest() async throws {
        let server = APIServer { _, _ in Reply(data: Data("{}".utf8), delay: 0.2) }
        let transport = transport(server)
        let a = Task { try await transport.send(Data()) }, b = Task { try await transport.send(Data()) }
        while server.requests.count < 2 { try await Task.sleep(for: .milliseconds(2)) }
        let queued = Task { try await transport.send(Data()) }
        try await Task.sleep(for: .milliseconds(20)); queued.cancel()
        do { _ = try await queued.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        _ = try await a.value; _ = try await b.value
        XCTAssertEqual(server.requests.count, 2)
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: APIProtocol.body(request)) as? [String: Any])
    }
}

private struct Reply {
    var data = Data(); var status = 200; var headers: [String: String] = [:]; var delay: TimeInterval = 0
}
private final class APIServer: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = [], active = 0, peak = 0
    let handler: (URLRequest, Int) throws -> Reply
    init(_ handler: @escaping (URLRequest, Int) throws -> Reply) { self.handler = handler }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return stored }
    var maxActive: Int { lock.lock(); defer { lock.unlock() }; return peak }
    func start(_ request: URLRequest) -> Int {
        lock.lock(); defer { lock.unlock() }
        stored.append(request); active += 1; peak = max(peak, active); return stored.count - 1
    }
    func finish() { lock.lock(); active -= 1; lock.unlock() }
}
private final class APIProtocol: URLProtocol, @unchecked Sendable {
    static var server: APIServer!
    private let lock = NSLock()
    private var finished = false
    private var owner: APIServer?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let server = Self.server!; owner = server
        var captured = request; captured.httpBody = Self.body(request)
        let index = server.start(captured)
        do {
            let reply = try server.handler(captured, index)
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
                guard finishOnce() else { return }
                let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: reply.data); client?.urlProtocolDidFinishLoading(self)
            }
        } catch { if finishOnce() { client?.urlProtocol(self, didFailWithError: error) } }
    }
    override func stopLoading() { _ = finishOnce() }
    private func finishOnce() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return false }; finished = true; owner?.finish(); return true
    }
    static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }
}
