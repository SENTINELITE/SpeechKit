import Foundation
import Testing
@testable import SpeechKit

@Suite("Realtime authorization lifecycle")
@MainActor
struct SpeechLifecycleSecurityTests {
    struct Service {
        let start: @MainActor () async -> Void
        let stop: @MainActor () async -> Void
        let replace: @MainActor (SpeechCredential) -> Void
        let reset: @MainActor () async -> Void
        let state: @MainActor () -> SpeechRealtimeConnectionState
        let error: @MainActor () -> Error?
    }

    func service(_ provider: SpeechRealtimeProvider, credential: SpeechCredential, policy: SpeechCredentialPolicy = .allowStaticKeys) -> Service {
        let endpoint = URL(string: "wss://proxy.example.com/realtime")!
        switch provider {
        case .elevenLabs:
            let s = ElevenLabsService(credential: credential, realtimeEndpoint: endpoint, credentialPolicy: policy)
            return Service(start: s.startListening, stop: s.stopListening, replace: s.setCredential, reset: { await s.clearCredentials() }, state: { s.connectionState }, error: { s.lastError })
        case .openAI:
            let s = OpenAIRealtimeService(credential: credential, realtimeEndpoint: endpoint, credentialPolicy: policy)
            return Service(start: s.startListening, stop: s.stopListening, replace: s.setCredential, reset: { await s.clearCredentials() }, state: { s.connectionState }, error: { s.lastError })
        case .grok:
            let s = GrokRealtimeService(credential: credential, realtimeEndpoint: endpoint, credentialPolicy: policy)
            return Service(start: s.startListening, stop: s.stopListening, replace: s.setCredential, reset: { await s.clearCredentials() }, state: { s.connectionState }, error: { s.lastError })
        case .meta:
            let s = MetaRealtimeService(credential: credential, realtimeEndpoint: endpoint, credentialPolicy: policy)
            return Service(start: s.startListening, stop: s.stopListening, replace: s.setCredential, reset: { await s.clearCredentials() }, state: { s.connectionState }, error: { s.lastError })
        case .gemini:
            let s = GeminiRealtimeService(credential: credential, realtimeEndpoint: endpoint, credentialPolicy: policy)
            return Service(start: s.startListening, stop: s.stopListening, replace: s.setCredential, reset: { await s.clearCredentials() }, state: { s.connectionState }, error: { s.lastError })
        case .mistral:
            let s = MistralRealtimeService(credential: credential, realtimeEndpoint: endpoint, credentialPolicy: policy)
            return Service(start: s.startListening, stop: s.stopListening, replace: s.setCredential, reset: { await s.clearCredentials() }, state: { s.connectionState }, error: { s.lastError })
        case .fishAudio:
            let s = FishAudioRealtimeService(credential: credential, realtimeEndpoint: endpoint, credentialPolicy: policy)
            return Service(start: s.startListening, stop: s.stopListening, replace: s.setCredential, reset: { await s.clearCredentials() }, state: { s.connectionState }, error: { s.lastError })
        default: fatalError("Cloud fixture only")
        }
    }

    @Test(arguments: SpeechRealtimeProvider.allCases.filter { $0.rawValue != "apple" }, ["stop", "replace", "reset"])
    func pendingResolutionCannotStartAfterInvalidation(provider: SpeechRealtimeProvider, action: String) async {
        let gate = SecurityGate()
        let credential = SpeechCredential.bearer(SpeechTokenResolver { _ in
            await gate.wait()
            return "SECURITY_SENTINEL"
        })
        let s = service(provider, credential: credential)
        let task = Task { await s.start() }
        while !(await gate.entered) { await Task.yield() }
        #expect(s.state() == .connecting)
        switch action {
        case "stop": await s.stop()
        case "replace": s.replace(.apiKey("replacement-sentinel"))
        default: await s.reset()
        }
        await gate.open()
        await task.value
        #expect(s.state() == .disconnected)
        #expect(s.error() == nil)
    }

    @Test(arguments: SpeechRealtimeProvider.allCases.filter { $0.rawValue != "apple" })
    func staleResolverFailureIsNotPublished(provider: SpeechRealtimeProvider) async {
        let gate = SecurityGate()
        let credential = SpeechCredential.bearer(SpeechTokenResolver { _ -> String in
            await gate.wait()
            throw NSError(domain: "SECURITY_SENTINEL", code: 5)
        })
        let s = service(provider, credential: credential)
        let task = Task { await s.start() }
        while !(await gate.entered) { await Task.yield() }
        await s.stop()
        await gate.open()
        await task.value
        #expect(s.error() == nil)
        #expect(s.state() == .disconnected)
    }

    @Test func facadeNilConfigurationInvalidatesPendingStart() async {
        let gate = SecurityGate()
        let service = SpeechService(openAI: OpenAIConfiguration(credential: .bearer(SpeechTokenResolver { _ in
            await gate.wait()
            return "SECURITY_SENTINEL"
        }), realtimeEndpoint: URL(string: "wss://proxy.example.com/openai")))
        let start = Task { await service.startListening(provider: .openAI) }
        while !(await gate.entered) { await Task.yield() }
        service.openAI = nil
        await gate.open()
        await start.value
        #expect(service.openAIRealtimeService.connectionState == .disconnected)
        #expect(service.lastError == nil)
    }

    @Test func resetCancelsOwnedFileOperation() async throws {
        let gate = SecurityGate()
        let fixture = SecurityHTTPFixture { _ in Issue.record("Reset operation sent audio"); return .init() }
        let service = SpeechService(openAI: OpenAIConfiguration(credential: .bearer(SpeechTokenResolver { _ in
            await gate.wait()
            return "SECURITY_SENTINEL"
        }), fileEndpoint: fixture.url), urlSession: fixture.session(), elevenLabsRealtimeService: ElevenLabsService())
        let file = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let task = Task { try await service.transcribeAudioFile(provider: .openAI, file: file) }
        while !(await gate.entered) { await Task.yield() }
        await service.clearCredentials()
        await gate.open()
        _ = try? await task.value
        #expect(fixture.requests.isEmpty)
        #expect(service.openAI == nil)
        #expect(!service.openAIRealtimeService.hasCredential)
        #expect(service.realtimeRecordingData == nil)
    }
    @Test(arguments: SpeechRealtimeProvider.allCases.filter { $0.rawValue != "apple" })
    func parentCancellationClearsConnectingState(provider: SpeechRealtimeProvider) async {
        let gate = SecurityGate()
        let s = service(provider, credential: .bearer(SpeechTokenResolver { _ in
            await gate.wait()
            return "synthetic-sentinel"
        }))
        let task = Task { await s.start() }
        while !(await gate.entered) { await Task.yield() }
        task.cancel()
        await gate.open()
        await task.value
        #expect(s.state() == .disconnected)
        #expect(s.error() == nil)
    }

    @Test(arguments: SpeechRealtimeProvider.allCases.filter { $0.rawValue != "apple" })
    func directPolicyRejectsBeforePermission(provider: SpeechRealtimeProvider) async {
        let s = service(provider, credential: .apiKey("synthetic-sentinel"), policy: .disallowStaticKeys)
        await s.start()
        #expect(s.error() as? SpeechFailure == SpeechFailure(.staticKeysDisallowed))
    }

    final class CaptureProbe: @unchecked Sendable {}
    @Test func clearingCredentialsReleasesOwnedResolver() async {
        weak var released: CaptureProbe?
        let speech: SpeechService
        do {
            let probe = CaptureProbe()
            released = probe
            speech = SpeechService(openAI: OpenAIConfiguration(credential: .bearer(SpeechTokenResolver { [probe] _ in
                withExtendedLifetime(probe) { "synthetic-token" }
            }), realtimeEndpoint: URL(string: "wss://proxy.example/realtime")))
        }
        #expect(released != nil)
        await speech.clearCredentials()
        #expect(released == nil)
    }

}
