import Foundation
import Testing
@testable import SpeechKit

final class SecurityHTTPFixture: @unchecked Sendable {
    struct Response: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data("{}".utf8)
        var redirect: URL?
    }
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    let host = UUID().uuidString.lowercased() + ".invalid"
    let respond: @Sendable (URLRequest) throws -> Response
    let beforeResponse: (@Sendable (URLRequest) async -> Void)?
    init(beforeResponse: (@Sendable (URLRequest) async -> Void)? = nil,
         _ respond: @escaping @Sendable (URLRequest) throws -> Response) {
        self.beforeResponse = beforeResponse
        self.respond = respond
        SecurityURLProtocol.registry.add(self)
    }
    deinit { SecurityURLProtocol.registry.remove(host) }
    var requests: [URLRequest] { lock.withLock { recorded } }
    func record(_ request: URLRequest) { lock.withLock { recorded.append(request) } }
    var url: URL { URL(string: "https://" + host)! }
    func endpoint(_ path: String) -> URL { url.appendingPathComponent(path) }
    func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SecurityURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class SecurityFixtureRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private struct Entry { weak var fixture: SecurityHTTPFixture? }
    private var fixtures: [String: Entry] = [:]
    func add(_ fixture: SecurityHTTPFixture) { lock.withLock { fixtures[fixture.host] = Entry(fixture: fixture) } }
    func remove(_ host: String) { _ = lock.withLock { fixtures.removeValue(forKey: host) } }
    func get(_ host: String) -> SecurityHTTPFixture? { lock.withLock { fixtures[host]?.fixture } }
}

final class SecurityURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = SecurityFixtureRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let fixture = Self.registry.get(url.host ?? "") else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            captured.httpBody = data
        }
        fixture.record(captured)
        if let beforeResponse = fixture.beforeResponse {
            let request = captured
            Task.detached { @Sendable [self, request, fixture, beforeResponse] in
                await beforeResponse(request)
                deliverResponse(for: request, fixture: fixture)
            }
        } else { deliverResponse(for: captured, fixture: fixture) }
    }
    private func deliverResponse(for request: URLRequest, fixture: SecurityHTTPFixture) {
        do {
            let response = try fixture.respond(request)
            let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
            do {
                client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .allowed)
                client?.urlProtocol(self, didLoad: response.body)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

actor SecurityGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    private var opened = false
    func wait() async {
        entered = true
        if opened { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func open() { opened = true; waiting?.resume(); waiting = nil }
}

func securityAudioFile() throws -> URL {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
    // 100 ms, 16 kHz, mono signed PCM.
    var bytes = Data()
    func little<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) } }
    bytes.append(Data("RIFF".utf8)); little(UInt32(3236)); bytes.append(Data("WAVEfmt ".utf8))
    little(UInt32(16)); little(UInt16(1)); little(UInt16(1)); little(UInt32(16000)); little(UInt32(32000))
    little(UInt16(2)); little(UInt16(16)); bytes.append(Data("data".utf8)); little(UInt32(3200)); bytes.append(Data(repeating: 0, count: 3200))
    try bytes.write(to: file)
    return file
}

func assertNoSentinel(_ value: Any, sentinel: String = "SECURITY_SENTINEL", sourceLocation: SourceLocation = #_sourceLocation) {
    var dumped = ""
    dump(value, to: &dumped)
    #expect(!String(describing: value).contains(sentinel), sourceLocation: sourceLocation)
    #expect(!String(reflecting: value).contains(sentinel), sourceLocation: sourceLocation)
    #expect(!dumped.contains(sentinel), sourceLocation: sourceLocation)
    func walk(_ mirror: Mirror, depth: Int = 0) {
        guard depth < 10 else { return }
        for child in mirror.children {
            #expect(!String(reflecting: child.value).contains(sentinel), sourceLocation: sourceLocation)
            walk(Mirror(reflecting: child.value), depth: depth + 1)
        }
    }
    walk(Mirror(reflecting: value))
}
