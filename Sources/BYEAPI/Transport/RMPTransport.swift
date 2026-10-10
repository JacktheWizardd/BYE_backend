import Foundation

public enum RMPAPIError: LocalizedError, Equatable {
    case http(Int), malformedResponse, graphql, invalidIdentity, pagination, network
    public var errorDescription: String? {
        switch self {
        case .http(429): return "RMP is limiting requests. Please try again later."
        case .http: return "RMP is unavailable. Please try again."
        case .malformedResponse, .graphql: return "RMP returned an unsupported response. Please try again later."
        case .invalidIdentity: return "The returned profile identity could not be verified."
        case .pagination: return "RMP’s review pagination stopped progressing. Retrieved reviews are still available."
        case .network: return "Couldn’t connect to RMP. Check your connection and try again."
        }
    }
}

/// One gate for previews, discoveries and detail requests across all readers.
actor RequestGate {
    private var active = 0
    private var nextStart = Date.distantPast
    private var cooldown = Date.distantPast
    private let spacing: TimeInterval
    init(spacing: TimeInterval) { self.spacing = spacing }
    func acquire() async throws {
        while active >= 2 { try await Task.sleep(for: .milliseconds(10)) }
        try Task.checkCancellation()
        active += 1
        let delay = max(0, nextStart.timeIntervalSinceNow)
        nextStart = Date().addingTimeInterval(delay + spacing)
        do {
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            // A rate-limit response can arrive while this lease is waiting for
            // its reserved start time. Recheck the shared cooldown before send.
            while cooldown > Date() {
                try await Task.sleep(for: .seconds(cooldown.timeIntervalSinceNow))
            }
            try Task.checkCancellation()
        } catch { active -= 1; throw error }
    }
    func release() { active -= 1 }
    func deferRequests(until date: Date) { cooldown = max(cooldown, date); nextStart = max(nextStart, date) }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// No browser session, authentication store, persistent cookies, URL cache or redirects.
public final class RMPTransport: @unchecked Sendable {
    public static let endpoint = URL(string: "https://www.ratemyprofessors.com/graphql")!
    private let session: URLSession
    private let gate: RequestGate
    private let retryDelay: TimeInterval
    public static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never; config.urlCredentialStorage = nil
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
        config.httpMaximumConnectionsPerHost = 2
        config.httpAdditionalHeaders = ["Accept": "application/json", "Content-Type": "application/json", "User-Agent": "BYE/0.2"]
        return config
    }
    public init(protocolClasses: [AnyClass]? = nil, spacing: TimeInterval = 0.1, retryDelay: TimeInterval = 0.5) {
        let config = Self.configuration()
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        gate = RequestGate(spacing: max(0, spacing)); self.retryDelay = max(0, retryDelay)
    }
    deinit { session.invalidateAndCancel() }

    func send(_ body: Data) async throws -> Data {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            awaitAttempt: do {
                try await gate.acquire()
                let result: (Data, URLResponse)
                do {
                    var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                    request.httpMethod = "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("BYE/0.2", forHTTPHeaderField: "User-Agent")
                    result = try await session.data(for: request)
                } catch {
                    await gate.release()
                    try Task.checkCancellation()
                    if let error = error as? URLError, error.code == .cancelled { throw CancellationError() }
                    let retryable: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost]
                    guard attempt < 2, let urlError = error as? URLError, retryable.contains(urlError.code) else { throw RMPAPIError.network }
                    try await Task.sleep(for: .seconds(retryDelay * pow(2, Double(attempt))))
                    break awaitAttempt
                }
                await gate.release()
                try Task.checkCancellation()
                guard let response = result.1 as? HTTPURLResponse, response.url == Self.endpoint else { throw RMPAPIError.malformedResponse }
                if (200..<300).contains(response.statusCode) {
                    guard result.0.count <= 4 * 1024 * 1024 else { throw RMPAPIError.malformedResponse }
                    return result.0
                }
                let status = response.statusCode
                guard attempt < 2, [429, 500, 502, 503, 504].contains(status) else { throw RMPAPIError.http(status) }
                let delay = Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After")) ?? retryDelay * pow(2, Double(attempt))
                // Do not retry sooner than requested; long waits become a recoverable failure.
                guard delay <= 30 else { throw RMPAPIError.http(status) }
                await gate.deferRequests(until: Date().addingTimeInterval(delay))
                try await Task.sleep(for: .seconds(delay))
            }
        }
        throw RMPAPIError.network
    }
    static func retryAfter(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return parser.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
    }
}
