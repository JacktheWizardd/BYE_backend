#if BYE_AUDIT
import XCTest
@testable import ClasswiseCore

private final class ForwardedBodyProtocol: URLProtocol {
    static var received = Data()
    override class func canInit(with request:URLRequest) -> Bool { true }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating:0,count:8192)
            while stream.hasBytesAvailable { let n = stream.read(&buffer,maxLength:buffer.count); if n<=0 { break }; data.append(buffer,count:n) }
        }
        Self.received = data
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("{\"data\":{}}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

final class CollectionGateTests: XCTestCase {
    func testForwardingPreservesPOSTBodyAndCanonicalReplayKey() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let log = try AuditLog(directory:folder)
        let http = try AuditHTTP(log:log,forwardingProtocols:[ForwardedBodyProtocol.self])
        var request = URLRequest(url:URL(string:"https://www.ratemyprofessors.com/graphql")!)
        request.httpMethod = "POST"; request.httpBody = Data("{\"query\":\"mock\",\"variables\":{\"count\":3}}".utf8)
        _ = try await http.send(request)
        XCTAssertEqual(ForwardedBodyProtocol.received,request.httpBody)
        await http.setOffline()
        request.httpBody = Data("{\"variables\":{\"count\":3},\"query\":\"mock\"}".utf8)
        let (data,_) = try await http.send(request)
        XCTAssertEqual(data,Data("{\"data\":{}}".utf8))
        let state = await http.state(); XCTAssertEqual(state["requests"],"1")
    }
    func testSerialSpacingAndMaximumAcrossConcurrentCallers() async throws {
        let gate = CollectionGate(policy:.init(spacing:0.06,duration:5,maximum:3))
        let starts = try await withThrowingTaskGroup(of:Double.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    _ = try await gate.acquire()
                    let start = ProcessInfo.processInfo.systemUptime
                    try await Task.sleep(for:.milliseconds(30))
                    await gate.release(status:200)
                    return start
                }
            }
            var values:[Double] = []; for try await value in group { values.append(value) }; return values.sorted()
        }
        XCTAssertGreaterThanOrEqual(starts[1]-starts[0],0.059)
        XCTAssertGreaterThanOrEqual(starts[2]-starts[1],0.059)
        do { _ = try await gate.acquire(); XCTFail("Request cap bypassed") } catch { }
        let state = await gate.state(); XCTAssertEqual(state["requests"],"3")
    }
    func testRateLimitAndAccessDenialStopQueuedRequests() async throws {
        for status in [401,403,429] {
            let gate = CollectionGate(policy:.init(spacing:0,duration:5,maximum:40))
            _ = try await gate.acquire(); await gate.release(status:status)
            do { _ = try await gate.acquire(); XCTFail("Stop condition bypassed") } catch { }
            let state = await gate.state(); XCTAssertEqual(state["requests"],"1")
        }
    }
    func testRepeatedServerFailuresAndDeadline() async throws {
        let gate = CollectionGate(policy:.init(spacing:0,duration:5,maximum:40))
        for _ in 0..<2 { _ = try await gate.acquire(); await gate.release(status:503) }
        do { _ = try await gate.acquire(); XCTFail("Repeated server failure bypassed") } catch { }
        let deadline = CollectionGate(policy:.init(spacing:0,duration:0.04,maximum:40))
        _ = try await deadline.acquire(); await deadline.release(status:200)
        try await Task.sleep(for:.milliseconds(60))
        do { _ = try await deadline.acquire(); XCTFail("Deadline bypassed") } catch { }
    }
    func testCancellationDoesNotConsumeQueuedRequest() async throws {
        let gate = CollectionGate(policy:.init(spacing:0,duration:5,maximum:40))
        _ = try await gate.acquire()
        let queued = Task { try await gate.acquire() }
        try await Task.sleep(for:.milliseconds(30)); queued.cancel()
        do { _ = try await queued.value; XCTFail("Cancellation bypassed") } catch { }
        await gate.release(status:200)
        let state = await gate.state(); XCTAssertEqual(state["requests"],"1")
    }
    func testOfflineReplayAndMissNeverOpenNetworkGate() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let log = try AuditLog(directory:folder)
        let http = try AuditHTTP(log:log,offline:true)
        let request = URLRequest(url:URL(string:"https://prod-apiweb.pasadena.edu/api/example")!)
        do { _ = try await http.send(request); XCTFail("Missing recording must fail closed") } catch { }
        let key = AuditLog.digest(Data(("GET "+request.url!.absoluteString).utf8))
        let bytes = Data("{\"fixture\":true}".utf8)
        let record:[String:Any] = ["status":200,"body_base64":bytes.base64EncodedString()]
        try JSONSerialization.data(withJSONObject:record).write(to:folder.appendingPathComponent("http/"+key+".json"))
        let (data,response) = try await http.send(request)
        XCTAssertEqual(data,bytes); XCTAssertEqual(response.statusCode,200)
        let state = await http.state(); XCTAssertEqual(state["requests"],"0")
    }
}
#endif
