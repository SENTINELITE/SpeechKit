import Foundation
import Testing
@testable import SpeechKit

@Suite("Relay facade integration")
@MainActor
struct SpeechRelayFacadeTests {
    @Test @MainActor func unsupportedFacadeAuthRetainsSafeCategory() async throws {
        let fixture = SecurityHTTPFixture { _ in Issue.record("Unsupported auth reached transport"); return .init() }
        let resolver = SpeechTokenResolver { _ -> String in
            Issue.record("Unsupported auth invoked resolver")
            return "synthetic-token"
        }
        let service = SpeechService(openAI: OpenAIConfiguration(credential: .vendorToken(resolver), fileEndpoint: fixture.url),
                                    urlSession: fixture.session(), elevenLabsRealtimeService: ElevenLabsService())
        let file = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: file) }
        await #expect(throws: SpeechFailure(.unsupportedAuthentication)) {
            try await service.transcribeAudioFile(provider: .openAI, file: file)
        }
        #expect(fixture.requests.isEmpty)
    }

    @Test(arguments: SpeechFileTranscriptionProvider.allCases.filter { $0.rawValue != "apple" }, [false, true])
    func everyFileProviderUsesRelayWithoutConfiguration(provider: SpeechFileTranscriptionProvider, proof: Bool) async throws {
        let fixture = SecurityHTTPFixture { request in
            if request.url?.path == "/speechkit/v1/session" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == (proof ? "Bearer synthetic-login" : nil))
                return .init(body: Data(#"{"ticket":"synthetic-relay-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8))
            }
            if proof { try expectContractProof(request, ticket: "synthetic-relay-ticket") }
            else { #expect(request.value(forHTTPHeaderField: "X-SpeechKit-Assertion") == nil) }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-relay-ticket")
            #expect(request.value(forHTTPHeaderField: "xi-api-key") == nil)
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == nil)
            #expect(request.url?.query == nil)
            return .init(body: Data(#"{"text":"synthetic transcript","transcript":"synthetic transcript","usage":{"type":"audio","seconds":0.1},"_request_id":"synthetic","status":"completed","steps":[{"content":[{"text":"synthetic transcript"}]}]}"#.utf8))
        }
        let relay = SpeechRelay(url: fixture.url, authentication: proof ? .appAttestAndBearer(SpeechTokenResolver { _ in "synthetic-login" }) : .none)
        let service = SpeechService(urlSession: fixture.session(), elevenLabsRealtimeService: ElevenLabsService())
        service.relay = relay
        service.relaySession = SpeechRelaySession(relay: relay, session: fixture.session(), attester: ContractAppAttest())
        let file = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try await service.transcribeAudioFile(provider: provider, file: file) == "synthetic transcript")
        #expect(fixture.requests.count == 2)
        #expect(fixture.requests.last?.url == (try relay.route(provider: provider, capability: .fileTranscription)))
        await service.clearCredentials()
    }

    @Test func optionsOnlyConfigurationInheritsRelayAndDirectCredentialWins() async throws {
        let relay = SpeechRelay(url: URL(string: "https://relay.example")!, authentication: .none)
        let service = SpeechService(relay: relay, openAI: OpenAIConfiguration(prompt: "synthetic prompt"))
        let inherited = try #require(try await service.resolvedOpenAIConfiguration(capability: .fileTranscription))
        #expect(inherited.credentialKind == .relay)
        #expect(inherited.prompt == "synthetic prompt")
        #expect(inherited.fileEndpoint?.host == "relay.example")
        let direct = URL(string: "https://proxy.example/transcribe")!
        service.openAI = OpenAIConfiguration(credential: .bearer(SpeechTokenResolver { _ in "synthetic-direct" }), fileEndpoint: direct)
        let overridden = try #require(try await service.resolvedOpenAIConfiguration(capability: .fileTranscription))
        #expect(overridden.credentialKind == .bearer)
        #expect(overridden.fileEndpoint == direct)
        service.openAI = OpenAIConfiguration(apiKey: "synthetic-key")
        await #expect(throws: SpeechFailure(.invalidEndpoint)) {
            try await service.resolvedOpenAIConfiguration(capability: .fileTranscription)
        }
        await service.clearCredentials()
    }

    @Test func facadePolicyRejectsStaticCredentialsBeforeHTTP() async throws {
        let fixture = SecurityHTTPFixture { _ in Issue.record("Policy allowed HTTP"); return .init() }
        let service = SpeechService(openAI: OpenAIConfiguration(apiKey: "synthetic-key", fileEndpoint: fixture.url), credentialPolicy: .disallowStaticKeys)
        await #expect(throws: SpeechFailure(.staticKeysDisallowed)) {
            try await service.transcribeAudioFile(provider: .openAI, file: URL(fileURLWithPath: "/synthetic.wav"))
        }
        #expect(fixture.requests.isEmpty)
    }

    @Test func relayOnlyNeverMintsVendorTokensOrAcceptsDirectCredentials() async throws {
        let relay = SpeechRelay(url: URL(string: "https://relay.example")!, authentication: .none, tokenStrategy: .vendorTokensWhenAvailable)
        let service = SpeechService(relay: relay, credentialPolicy: .relayOnly)
        let config = try #require(try await service.resolvedOpenAIConfiguration(capability: .realtime))
        #expect(config.credentialKind == .relay)
        #expect(config.realtimeEndpoint?.host == "relay.example")
        service.openAI = OpenAIConfiguration(credential: .bearer(SpeechTokenResolver { _ in Issue.record("Direct resolver invoked"); return "synthetic" }), realtimeEndpoint: URL(string: "wss://proxy.example/realtime"))
        await #expect(throws: SpeechFailure(.unsupportedAuthentication)) {
            try await service.resolvedOpenAIConfiguration(capability: .realtime)
        }
    }
}
