import Foundation
import XCTest
@testable import ClasswiseCore

private final class OllamaFailureProtocol: URLProtocol {
    static var status = 500
    static var responseBody = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

final class OllamaFailureTests: XCTestCase {
    private func client() -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OllamaFailureProtocol.self]
        return OllamaClient(session: URLSession(configuration: configuration))
    }
    private var reviews: [Review] {
        (1...2).map { Review(id: String($0), course: "MATH005A", text: "Fictional test review", date: "", rating: 4, difficulty: 2, online: nil) }
    }
    override func tearDown() {
        OllamaFailureProtocol.status = 500
        OllamaFailureProtocol.responseBody = ""
    }
    func testTokenRepeatLimitOffersRetryWithoutClaimingModelIsMissing() async throws {
        OllamaFailureProtocol.status = 500
        OllamaFailureProtocol.responseBody = #"{"error":"prediction aborted, token repeat limit reached"}"#
        do {
            _ = try await client().summarize(reviews: reviews, course: Course("MATH005A"))
            XCTFail("A failed generation should not produce a summary")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The local model couldn’t finish this summary. Retry the summary. Your ratings and reviews are still available.")
            XCTAssertFalse(error.localizedDescription.lowercased().contains("install"))
            XCTAssertFalse(error.localizedDescription.contains("Open Ollama"))
        }
    }
    func testIncompleteModelOutputOffersClearRetryInsteadOfDecodingDetails() async throws {
        OllamaFailureProtocol.status = 200
        for body in ["not JSON", #"{"message":{"content":"{}"}}"#] {
            OllamaFailureProtocol.responseBody = body
            do {
                _ = try await client().summarize(reviews: reviews, course: Course("MATH005A"))
                XCTFail("Incomplete output must not become a summary")
            } catch {
                XCTAssertEqual(error.localizedDescription, "The local AI returned an incomplete summary. Retry the summary. Your ratings and original reviews are still available.")
                XCTAssertFalse(error.localizedDescription.contains("Install"))
            }
        }
    }
    func testMissingModelStillOffersInstallationGuidance() async throws {
        OllamaFailureProtocol.status = 404
        OllamaFailureProtocol.responseBody = #"{"error":"model not found"}"#
        do {
            _ = try await client().summarize(reviews: reviews, course: Course("MATH005A"))
            XCTFail("A missing model should not produce a summary")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Install qwen3:4b"))
            XCTAssertFalse(error.localizedDescription.contains("couldn’t finish"))
        }
    }
}
