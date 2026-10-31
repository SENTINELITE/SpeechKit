import Foundation
import Testing
@testable import SpeechKit

@Suite("Gemini complete routes")
struct GeminiSecurityTests {
    @Test(arguments: [true, false])
    func partialRoutesFailBeforeResolver(interactionsOnly: Bool) async throws {
        let credential = SpeechCredential.bearer(SpeechTokenResolver { _ in Issue.record("Incomplete route resolved a credential"); return "sentinel" })
        let proxy = URL(string: "https://proxy.example.com/v1beta/interactions")!
        let client = GeminiFileTranscriptionClient(credential: credential, endpoint: interactionsOnly ? proxy : nil,
            filesEndpoint: interactionsOnly ? nil : URL(string: "https://proxy.example.com/upload/v1beta/files"))
        await #expect(throws: SpeechFailure(.invalidEndpoint)) { try await client.makeRequest(file: URL(fileURLWithPath: "/synthetic.wav")) }
    }

    @Test(arguments: ["https://evil.example/upload", "http://relay.example/upload", "https://user:password@relay.example/upload", "https://relay.example/speechkit/v1/gemini/upload-sessions/../escape"])
    func maliciousUploadURLsAreDenied(value: String) throws {
        let client = GeminiFilesClient(credential: .apiKey("sentinel"), endpoint: URL(string: "https://relay.example/speechkit/v1/gemini/upload/v1beta/files"))
        #expect(throws: SpeechFailure(.invalidEndpoint)) { try client.validateUploadSession(URL(string: value)!, credential: .relay("sentinel-ticket")) }
    }

    @Test(arguments: ["../secret", "files/../secret", "id?key=sentinel", "id%2fsecret", "https://evil.example/x", "a/b"])
    func pollIdentifiersAreSingleSegments(identifier: String) throws {
        let interactions = GeminiFileTranscriptionClient(apiKey: "sentinel")
        #expect(throws: SpeechFailure(.invalidResponse)) { try interactions.makePollRequest(interactionID: identifier) }
        let files = GeminiFilesClient(apiKey: "sentinel")
        #expect(throws: SpeechFailure(.invalidResponse)) { try files.makeStateRequest(fileName: identifier, timeoutInterval: 1) }
    }

    @Test func explicitMixedRouteBindsOneCredentialToBothDestinations() async throws {
        let route = try GeminiRoute(interactions: URL(string: "https://interactions.proxy.example/v1beta/interactions")!,
            files: URL(string: "https://files.proxy.example/upload/v1beta/files")!,
            realtime: URL(string: "wss://live.proxy.example/live")!, originPolicy: .explicitMixedOrigins)
        var configuration = GeminiConfiguration()
        configuration.setRoute(route)
        #expect(configuration.fileEndpoint == route.interactions)
        let credential = SpeechCredential.bearer(SpeechTokenResolver { context in
            #expect(context.approvedDestinations == [route.interactions, route.files])
            return "synthetic-token"
        })
        let client = GeminiFileTranscriptionClient(credential: credential, endpoint: route.interactions,
            filesEndpoint: route.files, routeOriginPolicy: route.originPolicy)
        let file = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let request = try await client.makeRequest(file: file)
        #expect(request.url == route.interactions)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
        #expect(throws: SpeechFailure(.invalidEndpoint)) {
            try GeminiRoute(interactions: route.interactions, files: route.files, realtime: route.realtime)
        }
        let relayCredential = SpeechCredential.relay(SpeechTokenResolver { _ in Issue.record("Mixed relay route resolved"); return "synthetic" })
        let relayClient = GeminiFileTranscriptionClient(credential: relayCredential, endpoint: route.interactions,
            filesEndpoint: route.files, routeOriginPolicy: .explicitMixedOrigins)
        await #expect(throws: SpeechFailure(.invalidEndpoint)) { try await relayClient.makeRequest(file: file) }
    }

    @Test(arguments: [GeminiFileUploadStrategy.inline, .filesAPI, .automatic])
    func relayUploadAndBothPollsUseOneCredential(strategy: GeminiFileUploadStrategy) async throws {
        let count = ResolverCounter()
        let fixture = SecurityHTTPFixture { request in
            let path = request.url!.path
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-ticket-1")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == nil)
            if path.hasSuffix("/upload/v1beta/files") {
                var url = request.url!
                url.deleteLastPathComponent(); url.deleteLastPathComponent(); url.deleteLastPathComponent()
                // Preserve relay prefix while returning a relay-owned upload capability.
                let session = URL(string: "https://" + request.url!.host! + "/speechkit/v1/gemini/upload-sessions/opaque-session")!
                return .init(headers: ["X-Goog-Upload-URL": session.absoluteString])
            }
            if path.contains("/upload-sessions/") {
                return .init(body: Data(#"{"file":{"name":"files/opaque-file","uri":"synthetic-file-uri","mimeType":"audio/wav","state":"PROCESSING"}}"#.utf8))
            }
            if path.hasSuffix("/v1beta/files/opaque-file") {
                return .init(body: Data(#"{"name":"files/opaque-file","uri":"synthetic-file-uri","mimeType":"audio/wav","state":"ACTIVE"}"#.utf8))
            }
            if request.httpMethod == "GET" {
                return .init(body: Data(#"{"id":"opaque-interaction","status":"completed","steps":[{"content":[{"text":"synthetic transcript"}]}]}"#.utf8))
            }
            return .init(body: Data(#"{"id":"opaque-interaction","status":"in_progress"}"#.utf8))
        }
        let origin = fixture.url
        let credential = SpeechCredential.relay(SpeechTokenResolver { _ in
            "synthetic-ticket-\(await count.next())"
        }).withRelayTransport(origin: origin, pinnedPublicKeyHashes: [])
        let client = GeminiFileTranscriptionClient(credential: credential, endpoint: fixture.endpoint("speechkit/v1/gemini/v1beta/interactions"),
            filesEndpoint: fixture.endpoint("speechkit/v1/gemini/upload/v1beta/files"), urlSession: fixture.session())
        let file = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: file) }
        var options = GeminiFileTranscriptionOptions(uploadStrategy: strategy)
        options.inlineUploadThresholdBytes = 1
        options.processingMode = .background(pollInterval: 0.001)
        let result = try await client.transcribeAudioFileDetailed(file: file, options: options)
        #expect(result.text == "synthetic transcript")
        #expect(await count.value == 1)
        #expect(fixture.requests.allSatisfy { $0.url?.host == fixture.host })
        let paths = fixture.requests.map { $0.url!.path }
        if strategy != .inline {
            #expect(paths.contains("/speechkit/v1/gemini/upload-sessions/opaque-session"))
            #expect(paths.contains("/speechkit/v1/gemini/v1beta/files/opaque-file"))
        }
        #expect(paths.contains("/speechkit/v1/gemini/v1beta/interactions/opaque-interaction"))
    }
}

private actor ResolverCounter {
    private(set) var value = 0
    func next() -> Int { value += 1; return value }
}
