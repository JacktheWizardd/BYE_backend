import WebKit
import XCTest
@testable import Classwise
@testable import ClasswiseCore

final class RMPSearchTests: XCTestCase {
    private func profile(_ id: String, lastName: String = "Instructor", schoolID: Int = 2649) -> RMPProfile {
        RMPProfile(id: id, firstName: "Fictional", lastName: lastName, school: schoolID == 2649 ? "Pasadena City College" : "Other College",
                   schoolID: schoolID, department: "Math", rating: 4, difficulty: 3, ratingCount: 0, wouldTakeAgain: nil, reviews: [])
    }
    @MainActor
    private func fixture(_ profiles: [RMPProfile], setup: String) async throws -> (RMPBrowser, WKWebView) {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let reader = RMPBrowser(webView: web, readerScript: "JSON.stringify(window.profiles)")
        let json = String(data: try JSONEncoder().encode(profiles), encoding: .utf8)!
        web.loadHTMLString("""
        <!doctype html><html><body><button id="more" style="display:block;width:200px;height:40px">Show More</button>
        <script>window.profiles = \(json); window.clicks = 0;
        const button = document.getElementById('more');
        \(setup)
        window.ready = true;</script></body></html>
        """, baseURL: URL(string: "https://www.ratemyprofessors.com/search/professors/2649"))
        let deadline = Date().addingTimeInterval(5)
        while (try? await web.evaluateJavaScript("window.ready")) as? Bool != true {
            if Date() > deadline { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(10))
        }
        return (reader, web)
    }
    @MainActor
    func testInitialEligibleCandidatesResolveWithoutClickingAndDeduplicateIDs() async throws {
        let a = profile("1")
        let (reader, web) = try await fixture([a, a], setup: "button.onclick = () => { window.clicks++; };")
        defer { reader.stop() }
        let result = try await reader.searchCandidates(name: a.name)
        XCTAssertEqual(result.map(\.id), ["1"])
        let clicks = try await web.evaluateJavaScript("window.clicks") as? Int
        XCTAssertEqual(clicks, 0)
    }
    @MainActor
    func testMultipleInitialProfilesRequireSelectionWithoutPagination() async throws {
        let (reader, web) = try await fixture([profile("1"), profile("2")], setup: "button.onclick = () => { window.clicks++; };")
        defer { reader.stop() }
        let result = try await reader.searchCandidates(name: "Fictional Instructor")
        XCTAssertEqual(result.count, 2)
        let clicks = try await web.evaluateJavaScript("window.clicks") as? Int
        XCTAssertEqual(clicks, 0)
    }
    @MainActor
    func testDelayedHandlerAndDisabledButtonWaitBeforeClicking() async throws {
        let next = String(data: try JSONEncoder().encode(profile("2")), encoding: .utf8)!
        let (reader, web) = try await fixture([profile("1", schoolID: 123)], setup: """
        button.disabled = true;
        setTimeout(() => { button.disabled = false; }, 120);
        setTimeout(() => { button.onclick = () => { window.clicks++; window.profiles.push(\(next)); button.remove(); }; }, 350);
        """)
        defer { reader.stop() }
        let result = try await reader.searchCandidates(name: "Fictional Instructor")
        XCTAssertEqual(result.map(\.id), ["2"])
        let clicks = try await web.evaluateJavaScript("window.clicks") as? Int
        XCTAssertEqual(clicks, 1)
    }
    @MainActor
    func testDelayedReactHandlerIsRecognized() async throws {
        let next = String(data: try JSONEncoder().encode(profile("2")), encoding: .utf8)!
        let (reader, _) = try await fixture([profile("1", lastName: "Other")], setup: """
        button.addEventListener('click', () => {
          if (button.__reactProps$fixture) button.__reactProps$fixture.onClick();
        });
        setTimeout(() => { button.__reactProps$fixture = {onClick: () => { window.clicks++; window.profiles.push(\(next)); button.remove(); }}; }, 250);
        """)
        defer { reader.stop() }
        let result = try await reader.searchCandidates(name: "Fictional Instructor")
        XCTAssertEqual(result.map(\.id), ["2"])
    }
    @MainActor
    func testPaginationTimeoutRetainsExistingCandidates() async throws {
        let (reader, web) = try await fixture([profile("1"), profile("2")], setup: "button.onclick = () => { window.clicks++; };")
        defer { reader.stop() }
        let result = try await reader.searchCandidates(name: "Fictional Instructor", discoverAll: true)
        XCTAssertEqual(Set(result.map(\.id)), ["1", "2"])
        let clicks = try await web.evaluateJavaScript("window.clicks") as? Int
        XCTAssertEqual(clicks, 1)
    }
    @MainActor
    func testAtMostThreeAdditionalSearchPages() async throws {
        let (reader, web) = try await fixture([profile("1", lastName: "Other")], setup: """
        button.onclick = () => { window.clicks++; const next = {...window.profiles[0], id: String(window.clicks + 1)}; window.profiles.push(next); };
        """)
        defer { reader.stop() }
        let result = try await reader.searchCandidates(name: "Fictional Instructor")
        XCTAssertTrue(result.isEmpty)
        let clicks = try await web.evaluateJavaScript("window.clicks") as? Int
        XCTAssertEqual(clicks, 3)
    }
    @MainActor
    func testCancellationInterruptsSearchHandlerWait() async throws {
        let (reader, _) = try await fixture([profile("1", lastName: "Other")], setup: "button.disabled = true;")
        defer { reader.stop() }
        let task = Task { try await reader.searchCandidates(name: "Fictional Instructor") }
        try await Task.sleep(for: .milliseconds(150)); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    }
}
