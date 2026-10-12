#if BYE_AUDIT
import Foundation
import CryptoKit

/// Compiled only into the explicitly requested measurement build.
public final class AuditLog: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    public let directory: URL
    public let origin = ProcessInfo.processInfo.systemUptime
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("events.jsonl")
        FileManager.default.createFile(atPath: path.path, contents: nil)
        handle = try FileHandle(forWritingTo: path)
    }
    public func event(_ type: String, _ fields: [String: Any] = [:]) {
        lock.lock(); defer { lock.unlock() }
        var value = fields
        value["event"] = type; value["utc"] = ISO8601DateFormatter().string(from: Date())
        value["monotonic_s"] = ProcessInfo.processInfo.systemUptime
        do { var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]); data.append(10); try handle.write(contentsOf: data); try handle.synchronize() }
        catch { FileHandle.standardError.write(Data("AUDIT LOG FAILURE: \(error)\n".utf8)) }
    }
    public func save(_ name: String, _ value: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

public enum AuditTrace { public static var log: AuditLog? }
public enum AuditSettings {
    public static var maximum: Int { min(40,max(1,Int(ProcessInfo.processInfo.environment["BYE_AUDIT_REQUEST_LIMIT"] ?? "40") ?? 40)) }
    public static var duration: Double { min(300,max(1,Double(ProcessInfo.processInfo.environment["BYE_AUDIT_DURATION"] ?? "300") ?? 300)) }
}

public actor CollectionGate {
    public struct Policy: Sendable {
        public var spacing: Double, duration: Double
        public var maximum: Int
        public init(spacing: Double = 2, duration: Double = 300, maximum: Int = 40) {
            self.spacing = spacing; self.duration = duration; self.maximum = maximum
        }
    }
    private let policy: Policy
    private var origin: Double?, lastStart = -Double.infinity
    private var active = false, count = 0, serverFailures = 0
    private var stopped: String?
    public init(policy: Policy = Policy()) { self.policy = policy }
    public func acquire() async throws -> (Int, Double) {
        let queued = ProcessInfo.processInfo.systemUptime
        while true {
            try Task.checkCancellation()
            let now = ProcessInfo.processInfo.systemUptime
            if let origin, now - origin >= policy.duration { stopped = stopped ?? "deadline" }
            if stopped != nil { throw URLError(.cancelled) }
            if count >= policy.maximum { stopped = "request_limit"; throw URLError(.cancelled) }
            if !active, now - lastStart >= policy.spacing {
                origin = origin ?? now; active = true; count += 1; lastStart = now
                return (count, now - queued)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    public func release(status: Int) {
        active = false
        if [401, 403, 429].contains(status) { stopped = "HTTP_\(status)" }
        serverFailures = status >= 500 ? serverFailures + 1 : 0
        if serverFailures >= 2 { stopped = "repeated_server_failures" }
    }
    public func stop(_ reason: String) { stopped = stopped ?? reason }
    public func state() -> [String: String] { ["requests": String(count), "stop_reason": stopped ?? "none", "active": String(active)] }
}

private final class AuditNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor AuditHTTP {
    public static var shared: AuditHTTP?
    private let log: AuditLog, gate: CollectionGate, session: URLSession
    private let recordings: URL
    private var offline: Bool
    private var graphqlFailures = 0
    public init(log: AuditLog, offline: Bool = false, forwardingProtocols: [AnyClass] = []) throws {
        self.log = log; self.offline = offline; gate = CollectionGate(policy:.init(duration:AuditSettings.duration,maximum:AuditSettings.maximum))
        recordings = log.directory.appendingPathComponent("http", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = forwardingProtocols; config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
        session = URLSession(configuration: config, delegate: AuditNoRedirect(), delegateQueue: nil)
    }
    public func setOffline() async {
        offline = true; await gate.stop("collection_finished"); session.invalidateAndCancel()
        log.event("offline_enabled", ["policy":"recorded responses only; no network fallback"])
    }
    public func state() async -> [String: String] { await gate.state() }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.scheme == "https",
              ["prod-apiweb.pasadena.edu", "www.ratemyprofessors.com"].contains(url.host ?? "") else {
            log.event("request_blocked", ["reason":"destination_not_allowed"]); throw URLError(.unsupportedURL)
        }
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 8192)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(buffer, count: n) }
        }
        if url.host == "www.ratemyprofessors.com" {
            guard let object = try? JSONSerialization.jsonObject(with:body) as? [String:Any],
                  let query = object["query"] as? String, !query.isEmpty else {
                log.event("request_blocked",["reason":"missing_graphql_body"]); throw URLError(.badURL)
            }
        }
        let canonicalBody = (try? JSONSerialization.jsonObject(with:body)).flatMap { try? JSONSerialization.data(withJSONObject:$0, options:[.sortedKeys]) } ?? body
        let key = AuditLog.digest(Data(((request.httpMethod ?? "GET") + " " + url.absoluteString).utf8) + canonicalBody)
        let responsePath = recordings.appendingPathComponent(key + ".json")
        if offline {
            guard let data = try? Data(contentsOf: responsePath), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let encoded = value["body_base64"] as? String, let bytes = Data(base64Encoded: encoded), let status = value["status"] as? Int,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"]) else {
                log.event("offline_cache_miss", ["key":key]); throw URLError(.resourceUnavailable)
            }
            log.event("replay_response", ["key":key,"bytes":bytes.count]); return (bytes,response)
        }
        let (number, wait) = try await gate.acquire()
        // Recheck after actor suspension: switching offline must never start another connection.
        if offline { await gate.release(status: 0); throw URLError(.cancelled) }
        var outbound = request; outbound.httpBodyStream = nil; outbound.httpBody = body
        outbound.timeoutInterval = 15; outbound.httpShouldHandleCookies = false
        let start = ProcessInfo.processInfo.systemUptime
        var fields: [String: Any] = ["request":number,"host":url.host!,"path":url.path,"key":key,"pacing_wait_s":wait]
        if let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            fields["variables"] = value["variables"]
            fields["operation"] = (value["query"] as? String)?.components(separatedBy: "{").first
        }
        log.event("request_start", fields)
        do {
            let (bytes, raw) = try await session.data(for: outbound)
            guard let response = raw as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            await gate.release(status: response.statusCode)
            fields["status"] = response.statusCode; fields["bytes"] = bytes.count
            fields["service_s"] = ProcessInfo.processInfo.systemUptime - start
            if let object = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any], let errors = object["errors"] as? [[String:Any]], !errors.isEmpty {
                graphqlFailures += 1; fields["graphql_errors"] = errors
                if graphqlFailures >= 2 { await gate.stop("repeated_graphql_failures") }
            } else { graphqlFailures = 0 }
            log.event("request_end", fields)
            let record: [String: Any] = ["url":url.absoluteString,"request_body_base64":body.base64EncodedString(),
                "status":response.statusCode,"body_base64":bytes.base64EncodedString(),"sha256":AuditLog.digest(bytes)]
            try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]).write(to: responsePath, options: .atomic)
            return (bytes,response)
        } catch {
            await gate.release(status: 0); await gate.stop("transport_or_recording_failure")
            fields["error"] = String(describing:error); fields["service_s"] = ProcessInfo.processInfo.systemUptime-start
            log.event("request_failure", fields); throw error
        }
    }
}

public final class AuditURLProtocol: URLProtocol, @unchecked Sendable {
    private var work: Task<Void, Never>?
    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    public override func startLoading() {
        work = Task {
            do {
                guard let http = AuditHTTP.shared else { throw URLError(.notConnectedToInternet) }
                let (data,response) = try await http.send(request)
                try Task.checkCancellation()
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    public override func stopLoading() { work?.cancel() }
}
#endif
