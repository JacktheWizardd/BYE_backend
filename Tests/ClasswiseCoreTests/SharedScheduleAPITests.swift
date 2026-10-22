import Foundation
import XCTest
@testable import ClasswiseCore

private final class SharedScheduleProtocol: URLProtocol {
    static var response: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.response else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
final class SharedScheduleAPITests: XCTestCase {
    override func tearDown() { SharedScheduleProtocol.response = nil }
    func testSourceFreshnessExpiresAtFifteenMinutes() throws {
        let metadata = try JSONDecoder().decode(ScheduleMetadata.self, from: Data("{\"sourceCheckedAt\":\"2026-10-20T12:00:00.000Z\",\"stale\":false}".utf8))
        XCTAssertFalse(metadata.expired(at: metadata.checkedAt!.addingTimeInterval(899)))
        XCTAssertTrue(metadata.expired(at: metadata.checkedAt!.addingTimeInterval(900)))
        let unknown = try JSONDecoder().decode(ScheduleMetadata.self, from: Data("{}".utf8))
        XCTAssertTrue(unknown.expired())
    }
    func testOfficialTermsUseOnlyConfiguredBackendAndNeverSwitchSemester() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SharedScheduleProtocol.self]
        let session = URLSession(configuration: config)
        SharedScheduleProtocol.response = { request in
            XCTAssertEqual(request.url?.host, "schedule.invalid")
            XCTAssertEqual(request.url?.path, "/v1/terms")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "fixture-key")
            return (200, Data("{\"data\":[{\"termCode\":\"202730\",\"name\":\"Spring sample\"},{\"termCode\":\"202670\",\"name\":\"Fall sample\"}],\"meta\":{}}".utf8))
        }
        let client = ScheduleAPIClient(base: URL(string: "https://schedule.invalid"), key: "fixture-key", session: session)
        let terms = try await client.terms()
        XCTAssertEqual(terms.map(\.termCode), ["202730", "202670"])
        XCTAssertTrue(terms.allSatisfy { $0.termDisplayControl == "Y" })
    }
    func testUnconfiguredBackendFailsBeforeAnyNetworkRequest() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SharedScheduleProtocol.self]
        SharedScheduleProtocol.response = { _ in XCTFail("Unconfigured adapter made a request"); return (500, Data()) }
        let client = ScheduleAPIClient(base: nil, key: "", session: URLSession(configuration: config))
        do { _ = try await client.terms(); XCTFail("Expected configuration failure") } catch { }
    }
    func testFullCourseSuffixesRemainDistinct() throws {
        XCTAssertNotEqual(try Course("MATH 005AH"), try Course("MATH 005AL"))
        XCTAssertNotEqual(try Course("MATH 005A"), try Course("MATH 005AH"))
    }
}
