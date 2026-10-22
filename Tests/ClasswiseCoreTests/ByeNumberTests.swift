import XCTest
@testable import ClasswiseCore

/// The BYE number flow against fixture responses shaped like the website's /api/reviews/* routes. No network.
final class ByeNumberTests: XCTestCase {
    private final class Log: @unchecked Sendable {
        private let lock = NSLock(); private var items: [URLRequest] = []
        func add(_ request: URLRequest) { lock.lock(); items.append(request); lock.unlock() }
        var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return items }
    }
    private func client(log: Log = Log(), _ routes: @escaping @Sendable (String, URLRequest) -> (Int, String, [String: String])) -> ByeNumberClient {
        ByeNumberClient(site: "https://bye.example/", fetch: { request in
            log.add(request)
            let url = try XCTUnwrap(request.url)
            let (status, body, headers) = routes(url.path.replacingOccurrences(of: "/api/reviews/", with: ""), request)
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!)
        })
    }
    private static let cookie = "__Secure-bye-review=aaa.bbb.ccc"

    func testSchoolEmailRuleMatchesTheWebsite() {
        XCTAssertEqual(ByeNumberClient.schoolEmail("  JDoe@GO.Pasadena.edu "), "jdoe@go.pasadena.edu")
        for bad in ["jdoe+1@go.pasadena.edu", "jdoe@gmail.com", "@go.pasadena.edu", "jdoe@go.pasadena.edu.evil.test", "j doe@go.pasadena.edu"] {
            XCTAssertNil(ByeNumberClient.schoolEmail(bad), bad)
        }
        XCTAssertEqual(ByeNumberClient.validCode(" 123456 "), "123456")
        XCTAssertNil(ByeNumberClient.validCode("12345")); XCTAssertNil(ByeNumberClient.validCode("12a456"))
    }

    func testBadEmailNeverReachesTheWebsite() async {
        let log = Log()
        let numbers = client(log: log) { _, _ in XCTFail("no request"); return (500, "", [:]) }
        do { _ = try await numbers.sendCode(email: "jdoe@gmail.com"); XCTFail("expected failure") }
        catch { XCTAssertEqual((error as? AppError)?.errorDescription, "Use your PCC school email, ending in @go.pasadena.edu.") }
        XCTAssertTrue(log.all.isEmpty)
    }

    func testSendVerifyAndClaimCarryOnlyTheSessionCookie() async throws {
        let log = Log()
        let numbers = client(log: log) { route, request in
            switch route {
            case "auth/send": return (200, #"{"data":{"sent":true,"retryAfter":60}}"#, [:])
            case "auth/verify":
                return (200, #"{"data":{"signedIn":true,"email":"jdoe@go.pasadena.edu"}}"#,
                        ["Set-Cookie": Self.cookie + "; Path=/api/reviews/; HttpOnly; SameSite=Strict; Secure; Max-Age=3600"])
            case "number":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), Self.cookie)
                return (200, #"{"data":{"number":42,"total":57}}"#, [:])
            default: return (404, "", [:])
            }
        }
        let wait = try await numbers.sendCode(email: "JDoe@go.pasadena.edu")
        XCTAssertEqual(wait, 60)
        let number = try await numbers.verify(email: "jdoe@go.pasadena.edu", code: "123456")
        XCTAssertEqual(number, ByeNumber(number: 42, total: 57))
        let requests = log.all
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/reviews/auth/send", "/api/reviews/auth/verify", "/api/reviews/number"])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://bye.example")
        }
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(requests[1].httpBody)) as? [String: String]
        XCTAssertEqual(sent, ["email": "jdoe@go.pasadena.edu", "code": "123456"], "Only the email and code are sent")
    }

    func testSessionIsDroppedAfterVerifying() async throws {
        let log = Log()
        let numbers = client(log: log) { route, _ in
            switch route {
            case "auth/verify": return (200, #"{"data":{"signedIn":true}}"#, ["Set-Cookie": Self.cookie + "; Path=/api/reviews/"])
            case "number": return (200, #"{"data":{"number":2,"total":2}}"#, [:])
            default: return (200, #"{"data":{"total":2}}"#, [:])
            }
        }
        _ = try await numbers.verify(email: "jdoe@go.pasadena.edu", code: "123456")
        let total = try await numbers.total()
        XCTAssertEqual(total, 2)
        let count = try XCTUnwrap(log.all.last)
        XCTAssertEqual(count.httpMethod ?? "GET", "GET")
        XCTAssertNil(count.value(forHTTPHeaderField: "Cookie"), "The count never carries the session")
        XCTAssertNil(count.value(forHTTPHeaderField: "Origin"))
    }

    func testWrongCodeShowsTheWebsiteMessageAndClaimsNothing() async {
        let log = Log()
        let numbers = client(log: log) { _, _ in
            (403, #"{"error":{"code":"INVALID_CODE","message":"That code is wrong or expired. Request a new one.","retryable":false}}"#, [:])
        }
        do { _ = try await numbers.verify(email: "jdoe@go.pasadena.edu", code: "000000"); XCTFail("expected failure") }
        catch { XCTAssertEqual((error as? AppError)?.errorDescription, "That code is wrong or expired. Request a new one.") }
        XCTAssertEqual(log.all.count, 1)
    }

    func testVerifyWithoutASessionCookieFailsClosed() async {
        let numbers = client { _, _ in (200, #"{"data":{"signedIn":true}}"#, [:]) }
        do { _ = try await numbers.verify(email: "jdoe@go.pasadena.edu", code: "123456"); XCTFail("expected failure") }
        catch { XCTAssertEqual((error as? AppError)?.errorDescription, "The code could not be confirmed. Request a new one.") }
    }

    func testOnlyTheReviewSessionCookieIsKept() {
        XCTAssertEqual(ByeNumberClient.sessionCookie("bye-review-local=a.b.c; Path=/api/reviews/; HttpOnly"), "bye-review-local=a.b.c")
        XCTAssertNil(ByeNumberClient.sessionCookie("tracker=1; Path=/"))
        XCTAssertNil(ByeNumberClient.sessionCookie("__Secure-bye-review=; Max-Age=0"))
        XCTAssertNil(ByeNumberClient.sessionCookie(nil))
    }

    func testLabels() {
        XCTAssertEqual(ByeNumber.label(1), "BYE-0001"); XCTAssertEqual(ByeNumber.label(12345), "BYE-12345"); XCTAssertEqual(ByeNumber.label(nil), "BYE-····")
    }
}
