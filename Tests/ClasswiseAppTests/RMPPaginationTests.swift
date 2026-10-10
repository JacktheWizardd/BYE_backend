import Foundation
import WebKit
import XCTest
@testable import Classwise
@testable import ClasswiseCore

/// Local pages deliberately hydrate after the embedded profile is readable.
/// These exercise RMPBrowser's actual WebKit loop without contacting RMP.
final class RMPPaginationTests: XCTestCase {
    @MainActor
    private func fixture(total: Int?, setup: String) async throws -> PaginationFixture {
        let reviews = (1...3).map {
            Review(id: "fixture-\($0)", course: "MATH005A", text: "FICTIONAL review \($0)",
                   date: "2026-01-01", rating: 5, difficulty: 2, online: true)
        }
        let initial = RMPProfile(id: "123", firstName: "Fictional", lastName: "Instructor",
                                 school: "Pasadena City College", schoolID: 2649, department: "Math",
                                 rating: 5, difficulty: 2, ratingCount: total, wouldTakeAgain: 90, reviews: reviews)
        let json = String(data: try JSONEncoder().encode(initial), encoding: .utf8)!
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900), configuration: configuration)
        let reader = RMPBrowser(webView: webView, readerScript: "JSON.stringify([window.fixtureProfile])")
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>button { display:block; width:200px; height:40px; }</style></head>
        <body><div id="reviews"></div><script>
        window.fixtureProfile = \(json);
        window.clickCount = 0;
        window.renderReviews = () => {
          document.getElementById('reviews').innerHTML = window.fixtureProfile.reviews.map(
            r => '<div class="Rating__RatingBody">' + r.text + '</div>').join('');
        };
        window.setReviewCount = count => {
          window.fixtureProfile.reviews = Array.from({length: count}, (_, index) => ({
            id: 'fixture-' + (index + 1), course: 'MATH005A', text: 'FICTIONAL review ' + (index + 1),
            date: '2026-01-01', rating: 5, difficulty: 2, online: true
          }));
          window.renderReviews();
        };
        window.makeMoreButton = (onClick, disabled = false) => {
          const button = document.createElement('button');
          button.textContent = 'Load More Ratings';
          button.disabled = disabled;
          button.onclick = () => { window.clickCount++; onClick(button); };
          document.body.appendChild(button);
          return button;
        };
        \(setup)
        window.fixtureReady = true;
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.ratemyprofessors.com/professor/123")!)
        let deadline = Date().addingTimeInterval(5)
        while (try? await webView.evaluateJavaScript("window.fixtureReady === true")) as? Bool != true {
            guard Date() < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(10))
        }
        return PaginationFixture(reader: reader, webView: webView, initial: initial)
    }

    @MainActor
    func testDelayedHydrationPublishesFiveThenPaginatesToSevenReviews() async throws {
        let fixture = try await fixture(total: 7, setup: """
        setTimeout(() => {
          window.setReviewCount(5);
          window.makeMoreButton(button => {
            setTimeout(() => { window.setReviewCount(7); button.remove(); }, 100);
          });
        }, 250);
        """)
        defer { fixture.reader.stop() }
        var published: [Int] = []
        let full = try await fixture.reader.collectReviews(fixture.initial) { published.append($0.reviews.count) }
        XCTAssertEqual(published, [3, 5, 7], "Hydration must update the report before pagination proceeds")
        XCTAssertEqual(full.reviews.count, 7)
        let clicks = try await fixture.webView.evaluateJavaScript("window.clickCount") as? Int
        XCTAssertEqual(clicks, 1)
    }

    @MainActor
    func testDisabledButtonWaitsUntilEnabledBeforePagination() async throws {
        let fixture = try await fixture(total: 5, setup: """
        window.renderReviews();
        const button = window.makeMoreButton(button => {
          window.setReviewCount(5); button.remove();
        }, true);
        setTimeout(() => { button.disabled = false; }, 250);
        """)
        defer { fixture.reader.stop() }
        var published: [Int] = []
        let full = try await fixture.reader.collectReviews(fixture.initial) { published.append($0.reviews.count) }
        XCTAssertEqual(published, [3, 5])
        XCTAssertEqual(full.reviews.count, 5)
        let clicks = try await fixture.webView.evaluateJavaScript("window.clickCount") as? Int
        XCTAssertEqual(clicks, 1)
    }

    @MainActor
    func testVisibleSSRButtonWaitsForItsClickHandler() async throws {
        let fixture = try await fixture(total: 5, setup: """
        window.renderReviews();
        window.handlerReady = false;
        window.clickedBeforeReady = false;
        const button = document.createElement('button');
        button.textContent = 'Load More Ratings';
        // SSR can expose the visible control before its application handler exists.
        button.addEventListener('click', () => {
          window.clickCount++;
          if (!window.handlerReady) window.clickedBeforeReady = true;
        });
        document.body.appendChild(button);
        setTimeout(() => {
          window.handlerReady = true;
          button.onclick = () => { window.setReviewCount(5); button.remove(); };
        }, 250);
        """)
        defer { fixture.reader.stop() }
        var published: [Int] = []
        let full = try await fixture.reader.collectReviews(fixture.initial) { published.append($0.reviews.count) }
        XCTAssertEqual(published, [3, 5])
        XCTAssertEqual(full.reviews.count, 5)
        let clicks = try await fixture.webView.evaluateJavaScript("window.clickCount") as? Int
        let clickedEarly = try await fixture.webView.evaluateJavaScript("window.clickedBeforeReady") as? Bool
        XCTAssertEqual(clicks, 1, "The rendered control must be clicked once, after its handler is ready")
        XCTAssertEqual(clickedEarly, false)
    }

    @MainActor
    func testVisibleSSRButtonWaitsForReactClickHandler() async throws {
        let fixture = try await fixture(total: 5, setup: """
        window.renderReviews();
        window.handlerReady = false;
        window.clickedBeforeReady = false;
        const button = document.createElement('button');
        button.textContent = 'Load More Ratings';
        button.addEventListener('click', () => {
          window.clickCount++;
          if (!window.handlerReady) window.clickedBeforeReady = true;
          button['__reactProps$fixture']?.onClick?.();
        });
        document.body.appendChild(button);
        setTimeout(() => {
          window.handlerReady = true;
          button['__reactProps$fixture'] = {
            onClick: () => { window.setReviewCount(5); button.remove(); }
          };
        }, 250);
        """)
        defer { fixture.reader.stop() }
        var published: [Int] = []
        let full = try await fixture.reader.collectReviews(fixture.initial) { published.append($0.reviews.count) }
        XCTAssertEqual(published, [3, 5])
        XCTAssertEqual(full.reviews.count, 5)
        let clicks = try await fixture.webView.evaluateJavaScript("window.clickCount") as? Int
        let clickedEarly = try await fixture.webView.evaluateJavaScript("window.clickedBeforeReady") as? Bool
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(clickedEarly, false)
    }

    @MainActor
    func testAbsentButtonWithKnownMissingReviewsThrowsAndPreservesPreview() async throws {
        let fixture = try await fixture(total: 9, setup: "window.renderReviews();")
        defer { fixture.reader.stop() }
        var published: [RMPProfile] = []
        do {
            _ = try await fixture.reader.collectReviews(fixture.initial) { published.append($0) }
            XCTFail("An unhydrated or incomplete page must not be treated as an exhausted review history")
        } catch {
            XCTAssertFalse(error is CancellationError)
            XCTAssertTrue(error.localizedDescription.contains("retry"), error.localizedDescription)
        }
        XCTAssertEqual(published, [fixture.initial], "A timeout must retain the original verified preview")
    }

    @MainActor
    func testCancellationInterruptsPaginationReadinessWait() async throws {
        let fixture = try await fixture(total: 9, setup: "window.renderReviews();")
        defer { fixture.reader.stop() }
        var published: [RMPProfile] = []
        let task = Task { @MainActor in
            try await fixture.reader.collectReviews(fixture.initial) { published.append($0) }
        }
        let deadline = Date().addingTimeInterval(5)
        while published.isEmpty {
            guard Date() < deadline else { task.cancel(); throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("The cancelled report must not finish as complete")
        } catch {
            XCTAssertTrue(error is CancellationError, error.localizedDescription)
        }
        XCTAssertEqual(published, [fixture.initial])
    }

    @MainActor
    func testTrulyExhaustedKnownCountFinishesWithoutClicking() async throws {
        let fixture = try await fixture(total: 3, setup: "window.renderReviews();")
        defer { fixture.reader.stop() }
        var published: [Int] = []
        let full = try await fixture.reader.collectReviews(fixture.initial) { published.append($0.reviews.count) }
        XCTAssertEqual(published, [3])
        XCTAssertEqual(full, fixture.initial)
        let clicks = try await fixture.webView.evaluateJavaScript("window.clickCount") as? Int
        XCTAssertEqual(clicks, 0)
    }

    @MainActor
    func testUnknownCountWaitsForRenderedHydrationBeforeFinishing() async throws {
        let fixture = try await fixture(total: nil, setup: """
        setTimeout(() => { window.setReviewCount(5); }, 250);
        """)
        defer { fixture.reader.stop() }
        var published: [Int] = []
        let full = try await fixture.reader.collectReviews(fixture.initial) { published.append($0.reviews.count) }
        XCTAssertEqual(published, [3, 5])
        XCTAssertEqual(full.reviews.count, 5)
    }
}

@MainActor
private struct PaginationFixture {
    let reader: RMPBrowser
    let webView: WKWebView
    let initial: RMPProfile
}
