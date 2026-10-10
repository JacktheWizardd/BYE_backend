import Foundation
import XCTest
@testable import ClasswiseCore

private actor LoadCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private final class ScheduleTestClock {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

private final class ScheduleStubProtocol: URLProtocol {
    static var reply: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.reply!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

final class ScheduleServicesTests: XCTestCase {
    override func tearDown() { ScheduleStubProtocol.reply = nil }
    private func rows(_ json: String) throws -> [ScheduleRow] {
        try JSONDecoder().decode([ScheduleRow].self, from: Data(json.utf8))
    }

    func testSameSemesterRequestsShareOneInFlightLoad() async throws {
        let cache = ScheduleCache(), counter = LoadCounter()
        let load: () async throws -> [ScheduleRow] = {
            await counter.increment()
            try await Task.sleep(nanoseconds: 40_000_000)
            return []
        }
        async let a = cache.rows(termCode: "202650", force: false, load: load)
        async let b = cache.rows(termCode: "202650", force: true, load: load)
        _ = try await (a, b)
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testCacheExpiresAtFiveMinutesAndRefreshBypassesCache() async throws {
        let clock = ScheduleTestClock(), counter = LoadCounter()
        let cache = ScheduleCache(now: clock.now)
        let load: () async throws -> [ScheduleRow] = { await counter.increment(); return [] }
        _ = try await cache.rows(termCode: "202650", force: false, load: load)
        clock.advance(299)
        _ = try await cache.rows(termCode: "202650", force: false, load: load)
        let cachedCount = await counter.count
        XCTAssertEqual(cachedCount, 1)
        clock.advance(1)
        _ = try await cache.rows(termCode: "202650", force: false, load: load)
        let expiredCount = await counter.count
        XCTAssertEqual(expiredCount, 2)
        _ = try await cache.rows(termCode: "202650", force: true, load: load)
        let refreshedCount = await counter.count
        XCTAssertEqual(refreshedCount, 3)
        _ = try await cache.rows(termCode: "202670", force: false, load: load)
        let otherTermCount = await counter.count
        XCTAssertEqual(otherTermCount, 4)
    }

    func testFailedScheduleCanBeRetried() async throws {
        let cache = ScheduleCache(), counter = LoadCounter()
        do {
            _ = try await cache.rows(termCode: "202650", force: false) {
                await counter.increment(); throw URLError(.timedOut)
            }
            XCTFail("Expected initial error")
        } catch { }
        _ = try await cache.rows(termCode: "202650", force: false) { await counter.increment(); return [] }
        let count = await counter.count
        XCTAssertEqual(count, 2)
    }

    func testCourseSearchReusesScheduleLoadedForSuggestions() async throws {
        let data = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "pcc-summer-2026-eth014", withExtension: "json")))
        var requests = 0
        ScheduleStubProtocol.reply = { request in
            requests += 1
            XCTAssertEqual(request.url?.path, "/api/classSchedule/202650")
            return (200, data)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScheduleStubProtocol.self]
        let client = PCCClient(session: URLSession(configuration: config))
        let term = Term(termCode: "202650", termName: "Summer 2026", termDisplayControl: "Y")
        let schedule = try await client.schedule(term: term)
        XCTAssertFalse(CourseSuggestions.match(rows: schedule, query: "eth").isEmpty)
        let professors = try await client.professors(course: Course("ETH014"), term: term)
        XCTAssertEqual(professors.count, 10)
        XCTAssertEqual(requests, 1)
        _ = try await client.professors(course: Course("ETH014"), term: term, force: true)
        XCTAssertEqual(requests, 2)
    }

    func testPartialReportCacheRoundTripAndOlderCompletionCompatibility() throws {
        let data = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "fictional-profiles", withExtension: "json")))
        let profile = try XCTUnwrap(JSONDecoder().decode([RMPProfile].self, from: data).first)
        let entry = CachedReport(profile: profile, summary: nil, checkedAt: Date(), reviewsComplete: false)
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CachedReport.self, from: encoded)
        XCTAssertEqual(decoded.reviewsComplete, false)
        var older = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        older.removeValue(forKey: "reviewsComplete")
        let oldDecoded = try JSONDecoder().decode(CachedReport.self, from: JSONSerialization.data(withJSONObject: older))
        XCTAssertNil(oldDecoded.reviewsComplete)
        XCTAssertTrue(oldDecoded.reviewsComplete ?? true, "Older reports were written after their complete review pass")
    }

    func testSuggestionsNormalizeCodeAndDeduplicatePublishedSections() throws {
        let sample = try rows("""
        [
          {"subjCode":"MATH","courseNumbDisplay":"005A","courseTitle":"Single Variable Calculus I","crn":"1","fwSectOpenInd":"O"},
          {"subjCode":"MATH","courseNumbDisplay":"005A","courseTitle":"Single Variable Calculus I","crn":"2","fwSectOpenInd":"C"},
          {"subjCode":"MATH","courseNumbDisplay":"005B","courseTitle":"Single Variable Calculus II","crn":"3","fwSectOpenInd":"O"},
          {"subjCode":"MATH","courseNumbDisplay":"005C","courseTitle":"Reserved course","crn":"4","fwSectOpenInd":"R"},
          {"subjCode":"MATH","courseNumbDisplay":"005D","courseTitle":"Hidden course","crn":"5","fwSectOpenInd":"X"},
          {"subjCode":"MATH","courseNumbDisplay":"005E","courseTitle":"No section","fwSectOpenInd":"O"}
        ]
        """)
        let exact = CourseSuggestions.match(rows: sample, query: "  math   005a ")
        XCTAssertEqual(exact.map(\.course.display), ["MATH 005A"])
        XCTAssertEqual(CourseSuggestions.match(rows: sample, query: "math").map(\.course.display), ["MATH 005A", "MATH 005B"])
        XCTAssertEqual(CourseSuggestions.match(rows: sample, query: "calculus", limit: 1).count, 1)
        XCTAssertTrue(CourseSuggestions.match(rows: sample, query: " ").isEmpty)
        XCTAssertTrue(CourseSuggestions.match(rows: sample, query: "math", limit: 0).isEmpty)
    }

    func testSuggestionsMatchTitlesAndPreferCourseCodes() throws {
        let sample = try rows("""
        [
          {"subjCode":"ART","courseNumbDisplay":"001","courseTitle":"Math in Art","crn":"1","fwSectOpenInd":"O"},
          {"subjCode":"MATH","courseNumbDisplay":"005A","courseTitle":"Single Variable Calculus I","crn":"2","fwSectOpenInd":"O"},
          {"subjCode":"ETH","courseNumbDisplay":"014","courseTitle":"Ethnic Studies","crn":"3","fwSectOpenInd":"O"}
        ]
        """)
        XCTAssertEqual(CourseSuggestions.match(rows: sample, query: "math").map(\.course.display), ["MATH 005A", "ART 001"])
        XCTAssertEqual(CourseSuggestions.match(rows: sample, query: "ethnic studies").first?.course.display, "ETH 014")
        XCTAssertEqual(CourseSuggestions.match(rows: sample, query: "variable calculus").first?.course.display, "MATH 005A")
    }
}
