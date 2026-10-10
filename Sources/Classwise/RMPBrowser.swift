import Foundation
import WebKit
import ClasswiseCore

/// Reads public, rendered RMP pages. No private GraphQL endpoint, account, or anti-bot bypass.
@MainActor
final class RMPBrowser: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var navigation: CheckedContinuation<Void, Error>?
    private var activeNavigation: WKNavigation?
    private var timeout: Task<Void, Never>?
    private let script: String
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900), configuration: configuration)
        let resource = Bundle.main.url(forResource: "RMPReader", withExtension: "js") ?? Bundle.module.url(forResource: "RMPReader", withExtension: "js")
        script = resource.flatMap { try? String(contentsOf: $0) } ?? "'[]'"
        super.init()
        webView.navigationDelegate = self
    }
    /// Local HTML injection lets integration tests exercise the actual WebKit pagination loop.
    init(webView: WKWebView, readerScript: String) {
        self.webView = webView; self.script = readerScript
        super.init()
        webView.navigationDelegate = self
    }
    func stop() {
        webView.stopLoading()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<Void, Error>) {
        timeout?.cancel(); timeout = nil
        let pending = navigation; navigation = nil; activeNavigation = nil
        pending?.resume(with: result)
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if navigation === activeNavigation { finish(.success(())) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if navigation === activeNavigation { finish(.success(())) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if navigation === activeNavigation { finish(.failure(error)) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if navigation === activeNavigation { finish(.failure(error)) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(AppError.message("RMP’s page stopped responding.")))
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Main-frame browsing stays on the public RMP site.
        if action.targetFrame?.isMainFrame == true, let host = action.request.url?.host,
           host != "www.ratemyprofessors.com" && host != "ratemyprofessors.com" {
            decisionHandler(.cancel); finish(.failure(AppError.message("RMP redirected to an unavailable page."))); return
        }
        decisionHandler(.allow)
    }
    private func load(_ url: URL) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                navigation = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(25)) } catch { return }
                    self?.webView.stopLoading()
                    self?.finish(.failure(AppError.message("RMP took too long to respond.")))
                }
                activeNavigation = webView.load(URLRequest(url: url, timeoutInterval: 25))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
        try Task.checkCancellation()
    }
    private func read() async throws -> [RMPProfile] {
        try Task.checkCancellation()
        let result = try await webView.evaluateJavaScript(script)
        guard let text = result as? String, let data = text.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([RMPProfile].self, from: data)
    }
    /// The source's embedded data often arrives before ads and other page resources finish.
    private func readWhenReady() async throws -> [RMPProfile] {
        for attempt in 0..<60 {
            try Task.checkCancellation()
            if let profiles = try? await read(), !profiles.isEmpty { return profiles }
            if attempt >= 5,
               (try? await webView.evaluateJavaScript("document.readyState")) as? String == "complete" { return [] }
            try await Task.sleep(for: .milliseconds(120))
        }
        return try await read()
    }
    private func clickMore(search: Bool = false, before: Int, profileID: String? = nil) async throws -> [RMPProfile]? {
        let expression = search ? "^(show|load) more$" : "^load more ratings$"
        let handlerGuard = search ? "" : """
          const hydrated = typeof button.onclick === 'function' || Object.keys(button).some(key =>
            key.startsWith('__react') && typeof button[key]?.onClick === 'function');
          if (!hydrated) return false;
        """
        let code = """
        (() => {
          const button = [...document.querySelectorAll('button')].find(b => /\(expression)/i.test(b.textContent.trim()));
          if (!button || button.disabled || !button.getClientRects().length) return false;
          \(handlerGuard)
          button.scrollIntoView({block: 'center'});
          button.click(); return true;
        })()
        """
        var clicked = false
        if search {
            clicked = try await webView.evaluateJavaScript(code) as? Bool ?? false
            guard clicked else { return nil }
        } else {
            // Embedded scores can arrive before React renders the review list/control.
            // Only the deeper report waits for hydration; ratings previews stay fast.
            var stableRenderedSamples = 0
            for _ in 0..<125 {
                try Task.checkCancellation()
                let profiles = try await read()
                guard let profile = profiles.first(where: { $0.id == profileID }) else {
                    throw AppError.message("The professor’s review page could not be verified.")
                }
                if profile.reviews.count > before { return profiles }
                let state = try await webView.evaluateJavaScript("""
                (() => {
                  const button = [...document.querySelectorAll('button')].find(b => /^load more ratings$/i.test(b.textContent.trim()));
                  return {buttonPresent: !!button,
                    rendered: document.querySelectorAll('[class*="Rating__RatingBody"]').length,
                    ready: document.readyState === 'complete'};
                })()
                """) as? [String: Any] ?? [:]
                if (state["buttonPresent"] as? Bool) == true {
                    // A disabled/loading button is never an exhaustion signal.
                    clicked = try await webView.evaluateJavaScript(code) as? Bool ?? false
                    if clicked { break }
                    stableRenderedSamples = 0
                } else {
                    if profile.reviews.count >= 50 { return nil }
                    if let total = profile.ratingCount, profile.reviews.count >= total { return nil }
                    if profile.ratingCount == nil, (state["rendered"] as? Int ?? 0) > 0,
                       state["ready"] as? Bool == true {
                        stableRenderedSamples += 1
                        if stableRenderedSamples >= 6 { return nil }
                    } else { stableRenderedSamples = 0 }
                }
                try await Task.sleep(for: .milliseconds(120))
            }
            guard clicked else {
                throw AppError.message("Additional RMP reviews are not available yet. The retrieved reviews are still available; retry to check again.")
            }
        }
        for _ in 0..<(search ? 30 : 80) {
            try await Task.sleep(for: .milliseconds(120))
            let profiles = try await read()
            let count = search ? profiles.count : (profiles.first(where: { $0.id == profileID })?.reviews.count ?? 0)
            if count > before { return profiles }
        }
        throw AppError.message("Additional RMP results took too long to arrive. The information already retrieved is still available.")
    }
    func lookup(_ professor: Professor, initialReviewsOnly: Bool = false,
                onProfile: @MainActor (RMPProfile) -> Void = { _ in }) async throws -> RMPProfile {
        guard professor.canSearch else { throw AppError.message("PCC has not named this instructor yet.") }
        try await load(professor.searchURL)
        var candidates = try await readWhenReady()
        // Expose more public search results when available, bounded to keep searches responsive.
        for _ in 0..<3 {
            let before = candidates.count
            guard let next = try await clickMore(search: true, before: before) else { break }
            candidates = Array(Dictionary((candidates + next).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }).values)
            if candidates.count <= before { break }
        }
        guard let match = IdentityMatcher.unique(name: professor.name, candidates: candidates) else {
            throw AppError.message("No unique matching PCC profile could be confirmed. Please check RMP yourself.")
        }
        try await load(match.url)
        let profiles = try await readWhenReady()
        guard var profile = profiles.first(where: { $0.id == match.id }), IdentityMatcher.matches(name: professor.name, profile: profile) else {
            throw AppError.message("The professor’s RMP page could not be verified.")
        }
        if initialReviewsOnly {
            profile.reviews = Array(Ordering.reviews(profile.reviews, by: .recent).prefix(3))
            webView.stopLoading()
            return profile
        }
        return try await collectReviews(profile, onProfile: onProfile)
    }
    func expand(_ professor: Professor, profile: RMPProfile,
                onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile {
        try await load(profile.url)
        let profiles = try await readWhenReady()
        guard let verified = profiles.first(where: { $0.id == profile.id }),
              IdentityMatcher.matches(name: professor.name, profile: verified) else {
            throw AppError.message("More reviews could not be retrieved. The verified rating and first reviews are still available.")
        }
        return try await collectReviews(verified, onProfile: onProfile)
    }
    func collectReviews(_ initial: RMPProfile,
                                onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile {
        var profile = initial
        onProfile(profile)
        for _ in 0..<10 {
            if profile.reviews.count >= 50 { break }
            let before = profile.reviews.count
            guard let profiles = try await clickMore(before: before, profileID: profile.id) else { break }
            guard let next = profiles.first(where: { $0.id == profile.id }) else {
                throw AppError.message("The professor’s review page could not be verified.")
            }
            profile = next
            onProfile(profile)
            if profile.reviews.count <= before { break }
        }
        return profile
    }
}
