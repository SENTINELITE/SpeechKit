import Foundation
import Testing
@testable import SpeechKit

@Suite("Security boundaries")
struct SpeechSecurityTests {
    @MainActor @Test func diagnosticHolders() {
        let key = "SECURITY_SENTINEL"
        let endpoint = URL(string: "https://proxy.example.com/SECURITY_SENTINEL?key=SECURITY_SENTINEL")!
        let credentials: [Any] = [SpeechCredential.apiKey(key), SpeechResolvedCredential.apiKey(key), SpeechAccessToken(value: key),
                                 SpeechTokenResolver { _ in Issue.record("Formatting invoked a callback"); return key }]
        let configurations: [Any] = [ElevenLabsConfiguration(apiKey: key, fileEndpoint: endpoint), OpenAIConfiguration(apiKey: key, fileEndpoint: endpoint),
            GrokConfiguration(apiKey: key, fileEndpoint: endpoint), MetaConfiguration(apiKey: key, fileEndpoint: endpoint),
            GeminiConfiguration(apiKey: key, fileEndpoint: endpoint), MistralConfiguration(apiKey: key, fileEndpoint: endpoint),
            FishAudioConfiguration(apiKey: key, fileEndpoint: endpoint), CohereConfiguration(apiKey: key, fileEndpoint: endpoint), AquaConfiguration(apiKey: key, fileEndpoint: endpoint)]
        let clients: [Any] = [ElevenLabsFileTranscriptionClient(apiKey: key, endpoint: endpoint), OpenAIFileTranscriptionClient(apiKey: key, endpoint: endpoint),
            GrokFileTranscriptionClient(apiKey: key, endpoint: endpoint), MetaFileTranscriptionClient(apiKey: key, endpoint: endpoint),
            GeminiFileTranscriptionClient(apiKey: key, endpoint: endpoint), GeminiFilesClient(apiKey: key, endpoint: endpoint),
            MistralFileTranscriptionClient(apiKey: key, endpoint: endpoint), FishAudioFileTranscriptionClient(apiKey: key, endpoint: endpoint),
            CohereFileTranscriptionClient(apiKey: key, endpoint: endpoint), AquaFileTranscriptionClient(apiKey: key, endpoint: endpoint)]
        let services: [Any] = [ElevenLabsService(apiKey: key), OpenAIRealtimeService(apiKey: key), GrokRealtimeService(apiKey: key), MetaRealtimeService(apiKey: key),
            GeminiRealtimeService(apiKey: key), MistralRealtimeService(apiKey: key), FishAudioRealtimeService(apiKey: key), SpeechService(openAI: OpenAIConfiguration(apiKey: key))]
        for value in credentials + configurations + clients + services { assertNoSentinel(value) }
    }

    @Test func metaWireIsPreserved() throws {
        let message = MetaRealtimeOptions().handshakeMessage(secret: "SECURITY_SENTINEL")
        assertNoSentinel(message)
        assertNoSentinel(message.authorization)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as! [String: Any]
        #expect((json["authorization"] as? [String: String])?["accessToken"] == "Bearer SECURITY_SENTINEL")
    }

    @Test func errorsDiscardPayloads() {
        let error = NSError(domain: "SECURITY_SENTINEL", code: 1, userInfo: [NSLocalizedDescriptionKey: "SECURITY_SENTINEL",
            NSUnderlyingErrorKey: NSError(domain: "SECURITY_SENTINEL", code: 2), NSURLErrorFailingURLStringErrorKey: "https://SECURITY_SENTINEL.invalid/?token=SECURITY_SENTINEL"])
        assertNoSentinel(SpeechErrorBoundary.safe(error))
        assertNoSentinel(SpeechRealtimeErrorRedaction.redacted(error))
        #expect(SpeechRealtimeErrorRedaction.redactedDescription(error) == "The connection failed.")
        #expect(SpeechErrorBoundary.safe(CancellationError()) as? SpeechFailure == SpeechFailure(.cancelled))
    }

    @Test(arguments: ["http://example.com", "https://user:pass@example.com", "https://example.com/?key=SECURITY_SENTINEL", "https://example.com/#fragment", "ftp://example.com"])
    func endpointRejectedBeforeResolution(endpoint: String) async {
        let credential = SpeechCredential.bearer(SpeechTokenResolver { _ in Issue.record("Resolver called for denied endpoint"); return "SECURITY_SENTINEL" })
        await #expect(throws: SpeechFailure(.invalidEndpoint)) {
            try await credential.resolved(for: .openAI, endpoint: URL(string: endpoint))
        }
    }

    @Test func endpointOriginsAndLoopback() throws {
        #expect(SpeechEndpointPolicy.sameOrigin(URL(string: "https://EXAMPLE.com")!, URL(string: "https://example.com:443/a")!))
        #expect(!SpeechEndpointPolicy.sameOrigin(URL(string: "https://example.com")!, URL(string: "https://example.com:444/a")!))
        try SpeechEndpointPolicy.validate(URL(string: "http://127.0.0.1:8800"))
        try SpeechEndpointPolicy.validate(URL(string: "ws://[::1]:8800"), websocket: true)
        #expect(throws: SpeechFailure(.invalidEndpoint)) { try SpeechEndpointPolicy.validate(URL(string: "http://127.0.0.2")) }
        #expect(throws: SpeechFailure(.invalidEndpoint)) { try SpeechEndpointPolicy.validate(URL(string: "wss://example.com")) }
    }

    @Test func sessionHasNoAmbientStorage() async throws {
        let fixture = SecurityHTTPFixture { _ in .init(headers: ["Set-Cookie": "session=SECURITY_SENTINEL", "Cache-Control": "max-age=3600"], body: Data("safe".utf8)) }
        let session = SpeechTransport.session(copying: fixture.session())
        let config = session.configuration
        #expect(config.urlCache == nil)
        #expect(config.httpCookieStorage == nil)
        #expect(config.urlCredentialStorage == nil)
        #expect(!config.httpShouldSetCookies)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
        let request = URLRequest(url: fixture.url)
        _ = try await SpeechTransport.data(for: request, session: session)
        _ = try await SpeechTransport.data(for: request, session: session)
        #expect(fixture.requests.count == 2)
        #expect(fixture.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
        session.invalidateAndCancel()
    }

    @Test(arguments: [301, 302, 303, 307, 308])
    func redirectedAudioIsNotReplayed(status: Int) async throws {
        let destination = SecurityHTTPFixture { _ in Issue.record("Denied destination received a request"); return .init() }
        let fixture = SecurityHTTPFixture { _ in .init(status: status, headers: ["Location": destination.url.absoluteString], redirect: destination.url) }
        var request = URLRequest(url: fixture.url)
        request.httpMethod = "POST"
        request.httpBody = Data("synthetic-audio".utf8)
        request.setValue("SECURITY_SENTINEL", forHTTPHeaderField: "xi-api-key")
        request.setValue("SECURITY_SENTINEL", forHTTPHeaderField: "x-goog-api-key")
        await #expect(throws: SpeechFailure(.redirectRefused, statusCode: status)) {
            try await SpeechTransport.data(for: request, session: SpeechTransport.session(copying: fixture.session()))
        }
        #expect(destination.requests.isEmpty)
    }

    @Test(arguments: [401, 403, 429, 500])
    func httpErrorsContainOnlyStatus(status: Int) async throws {
        let fixture = SecurityHTTPFixture { _ in .init(status: status, body: Data("SECURITY_SENTINEL".utf8)) }
        let file = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let client = OpenAIFileTranscriptionClient(apiKey: "SECURITY_SENTINEL", endpoint: fixture.endpoint("transcribe"), urlSession: fixture.session())
        do { _ = try await client.transcribeAudioFile(file: file); Issue.record("Expected server rejection") }
        catch { assertNoSentinel(error); #expect(error as? SpeechFailure == SpeechFailure(.server, statusCode: status)) }
    }

    @Test func policyRejectsBeforeResolution() async {
        let key = SpeechCredential.apiKey("SECURITY_SENTINEL")
        await #expect(throws: SpeechFailure(.staticKeysDisallowed)) {
            try await key.resolved(for: .openAI, endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions"), policy: .disallowStaticKeys)
        }
        let bearer = SpeechCredential.bearer(SpeechTokenResolver { _ in Issue.record("Policy invoked resolver"); return "sentinel" })
        await #expect(throws: SpeechFailure(.unsupportedAuthentication)) {
            try await bearer.resolved(for: .openAI, endpoint: URL(string: "https://proxy.example.com"), policy: .relayOnly)
        }
    }
    @Test(arguments: [301, 302, 303, 307, 308], [false, true])
    func redirectDelegateRefusesHTTPAndWebSocket(status: Int, websocket: Bool) async throws {
        let session = SpeechTransport.session()
        defer { session.invalidateAndCancel() }
        let source = URL(string: websocket ? "wss://relay.example/socket" : "https://relay.example/audio")!
        let destination = URL(string: websocket ? "ws://other.example/socket" : "http://other.example/audio")!
        let task: URLSessionTask = websocket ? session.webSocketTask(with: source) : session.dataTask(with: source)
        let response = HTTPURLResponse(url: source, statusCode: status, httpVersion: nil, headerFields: nil)!
        let allowed = await withCheckedContinuation { continuation in
            SpeechTransportDelegate().urlSession(session, task: task, willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: destination)) { continuation.resume(returning: $0) }
        }
        #expect(allowed == nil)
    }

}
