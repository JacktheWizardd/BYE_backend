import Foundation
import WebKit
import ClasswiseCore

/// Reads public, rendered RMP pages. No private GraphQL endpoint, account, or anti-bot bypass.
@MainActor
final class RMPBrowser: NSObject, WKNavigationDelegate, ProfileReader {
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
        let handlerGuard = """
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
            var absentSamples = 0
            for _ in 0..<125 {
                try Task.checkCancellation()
                clicked = try await webView.evaluateJavaScript(code) as? Bool ?? false
                if clicked { break }
                let state = try await webView.evaluateJavaScript("""
                (() => ({present: [...document.querySelectorAll('button')].some(b => /^(show|load) more$/i.test(b.textContent.trim())),
                         ready: document.readyState === 'complete'}))()
                """) as? [String: Any] ?? [:]
                if state["present"] as? Bool == false, state["ready"] as? Bool == true {
                    absentSamples += 1
                    if absentSamples >= 6 { return nil }
                } else { absentSamples = 0 }
                try await Task.sleep(for: .milliseconds(120))
            }
            guard clicked else { throw AppError.message("RMP’s additional results are not ready. Try again.") }
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
            let count = search ? Set(profiles.map(\.id)).count : (profiles.first(where: { $0.id == profileID })?.reviews.count ?? 0)
            if count > before { return profiles }
        }
        throw AppError.message("Additional RMP results took too long to arrive. The information already retrieved is still available.")
    }
    func candidates(_ professor: Professor, discoverAll: Bool = false) async throws -> [RMPProfile] {
        guard professor.canSearch else { throw AppError.message("PCC has not named this instructor yet.") }
        try await load(professor.searchURL)
        return try await searchCandidates(name: professor.name, discoverAll: discoverAll)
    }
    /// Also used with local HTML to test the real search pagination loop.
    func searchCandidates(name: String, discoverAll: Bool = false) async throws -> [RMPProfile] {
        var retained = try await readWhenReady()
        for _ in 0..<3 {
            let eligible = IdentityMatcher.eligible(name: name, candidates: retained)
            if !discoverAll, !eligible.isEmpty { return eligible }
            let before = Set(retained.map(\.id)).count
            do {
                guard let next = try await clickMore(search: true, before: before) else { break }
                retained = merge(retained, next)
                if Set(retained.map(\.id)).count <= before { break }
            } catch is CancellationError { throw CancellationError() }
            catch {
                // A page may have partially arrived before its timeout.
                if let latest = try? await read() { retained = merge(retained, latest) }
                try Task.checkCancellation()
                let eligible = IdentityMatcher.eligible(name: name, candidates: retained)
                if !eligible.isEmpty { return eligible }
                throw error
            }
        }
        return IdentityMatcher.eligible(name: name, candidates: retained)
    }
    private func merge(_ old: [RMPProfile], _ new: [RMPProfile]) -> [RMPProfile] {
        Array(Dictionary((old + new).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }).values)
    }
    func preview(_ professor: Professor, profileID: String) async throws -> RMPProfile {
        guard profileID.range(of: "^[0-9]+$", options: .regularExpression) != nil else { throw ProfileIdentityMismatch() }
        try await load(URL(string: "https://www.ratemyprofessors.com/professor/\(profileID)")!)
        let profiles = try await readWhenReady()
        guard var profile = profiles.first(where: { $0.id == profileID }) else {
            if !profiles.isEmpty { throw ProfileIdentityMismatch() }
            throw AppError.message("The RMP profile could not be read. Try again.")
        }
        guard IdentityMatcher.matches(name: professor.name, profile: profile) else { throw ProfileIdentityMismatch() }
        profile.reviews = Array(Ordering.reviews(profile.reviews, by: .recent).prefix(3))
        webView.stopLoading()
        return profile
    }
    /// Compatibility entry point for development checks; the app uses typed outcomes.
    func lookup(_ professor: Professor, initialReviewsOnly: Bool = false,
                onProfile: @MainActor (RMPProfile) -> Void = { _ in }) async throws -> RMPProfile {
        switch try await lookupOutcome(professor) {
        case .verified(let profile):
            if initialReviewsOnly { return profile }
            return try await expand(professor, profile: profile, onProfile: onProfile)
        case .selectionRequired: throw AppError.message("Multiple PCC profiles require an explicit choice.")
        case .unavailable(let message): throw AppError.message(message)
        }
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
        profile.reviews = Array(profile.reviews.prefix(50))
        onProfile(profile)
        for _ in 0..<10 {
            if profile.reviews.count >= 50 { break }
            let before = profile.reviews.count
            guard let profiles = try await clickMore(before: before, profileID: profile.id) else { break }
            guard let next = profiles.first(where: { $0.id == profile.id }) else {
                throw AppError.message("The professor’s review page could not be verified.")
            }
            profile = next
            profile.reviews = Array(profile.reviews.prefix(50))
            onProfile(profile)
            if profile.reviews.count <= before { break }
        }
        return profile
    }
}
