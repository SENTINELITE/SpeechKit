import Foundation
import Testing
@testable import SpeechKit

@Suite("Speech credentials 3.0")
struct SpeechCredentialTests {
    @Test func equality() {
        let id = UUID()
        let first = SpeechTokenResolver(id: id) { _ in "one" }
        let second = SpeechTokenResolver(id: id) { _ in "two" }
        #expect(first == second)
        #expect(SpeechCredential.apiKey("one") == .apiKey("one"))
        #expect(SpeechCredential.vendorToken(first) == .vendorToken(second))
        #expect(SpeechCredential.vendorToken(first) != .bearer(first))
    }

    @Test(arguments: ["", " ", "\n\t"])
    func emptyCredentials(value: String) async {
        let endpoint = URL(string: "https://proxy.example.com/transcribe")!
        for credential in [SpeechCredential.apiKey(value), .bearer(SpeechTokenResolver { _ in value })] {
            await #expect(throws: SpeechFailure(.invalidCredential)) {
                try await credential.resolved(for: .openAI, endpoint: endpoint)
            }
        }
    }

    @Test func nonblankCredentialsAreNotRewritten() async throws {
        let credential = SpeechCredential.apiKey(" synthetic-secret ")
        let value = try await credential.resolved(for: .openAI, endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions"))
        #expect(value.secret == " synthetic-secret ")
    }

    @Test func context() async throws {
        let endpoint = URL(string: "https://proxy.example.com/transcribe")!
        let operationID = UUID()
        let credential = SpeechCredential.bearer(SpeechTokenResolver { context in
            #expect(context.provider == .openAI)
            #expect(context.capability == .fileTranscription)
            #expect(context.model == "synthetic-model")
            #expect(context.operationID == operationID)
            #expect(context.attempt == 0)
            #expect(context.authMode == .bearer)
            #expect(context.approvedDestinations == [endpoint])
            return SpeechAccessToken(value: "sentinel-token", expiresAt: Date().addingTimeInterval(60), isReusable: false)
        })
        _ = try await credential.resolved(for: .openAI, model: "synthetic-model", endpoint: endpoint, operationID: operationID)
    }

    @Test func callbackFailureIsSafe() async {
        let credential = SpeechCredential.bearer(SpeechTokenResolver { _ -> String in
            throw NSError(domain: "SECRET_SENTINEL", code: 12, userInfo: [NSLocalizedDescriptionKey: "SECRET_SENTINEL"])
        })
        await #expect(throws: SpeechFailure(.credentialResolution)) {
            try await credential.resolved(for: .openAI, endpoint: URL(string: "https://proxy.example.com/transcribe"))
        }
    }

    @Test func expiredToken() async {
        let credential = SpeechCredential.bearer(SpeechTokenResolver { _ in
            SpeechAccessToken(value: "sentinel", expiresAt: Date().addingTimeInterval(-1), isReusable: true)
        })
        await #expect(throws: SpeechFailure(.invalidCredential)) {
            try await credential.resolved(for: .gemini, endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions"))
        }
    }

    @Test(arguments: SpeechFileTranscriptionProvider.allCases.filter { $0.rawValue != "apple" })
    func unsupportedVendorFileTokens(provider: SpeechFileTranscriptionProvider) async throws {
        let credential = SpeechCredential.vendorToken(SpeechTokenResolver { _ in
            #expect(provider == .elevenLabs)
            return "sentinel"
        })
        if provider == .elevenLabs {
            _ = try await credential.resolved(for: provider, endpoint: URL(string: "https://proxy.example.com/transcribe"))
        } else {
            await #expect(throws: SpeechFailure(.unsupportedAuthentication)) {
                try await credential.resolved(for: provider, endpoint: URL(string: "https://proxy.example.com/transcribe"))
            }
        }
    }

    @Test func statusAndReplacement() {
        var config = GeminiConfiguration()
        #expect(!config.hasCredential)
        config.setCredential(.apiKey("sentinel"))
        #expect(config.hasCredential)
        #expect(config.credentialKind == .apiKey)
        config.setCredential(.vendorToken(SpeechTokenResolver { _ in "sentinel" }), for: .realtime)
        #expect(config.credentialKind(for: .realtime) == .vendorToken)
        #expect(config.credentialKind(for: .fileTranscription) == .apiKey)
    }

    @Test func liveAuthPlacement() throws {
        let key = try GeminiLiveWebSocket.makeConnectRequest(credential: .apiKey("synthetic-key"), options: GeminiRealtimeOptions())
        #expect(key.url?.query == nil)
        #expect(key.value(forHTTPHeaderField: "x-goog-api-key") == "synthetic-key")
        let token = try GeminiLiveWebSocket.makeConnectRequest(credential: .token("synthetic-token"), options: GeminiRealtimeOptions())
        #expect(token.url?.path.hasSuffix("BidiGenerateContentConstrained") == true)
        #expect(token.value(forHTTPHeaderField: "Authorization") == "Token synthetic-token")
        let openAI = try OpenAIRealtimeWebSocket.makeConnectRequest(credential: .token("sentinel"), options: OpenAIRealtimeSessionOptions())
        #expect(openAI.url?.query == "intent=transcription")
        #expect(openAI.value(forHTTPHeaderField: "Authorization") == "Bearer sentinel")
        let mistral = try MistralRealtimeWebSocket.makeConnectRequest(credential: .token("rt_sentinel"), options: MistralRealtimeOptions(modelID: .voxtralMiniTranscribeRealtime2602))
        #expect(mistral.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(mistral.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "realtime, rt_sentinel")
        #expect(throws: SpeechFailure(.unsupportedAuthentication)) {
            try MistralRealtimeWebSocket.makeConnectRequest(credential: .token("rt_sentinel"), options: MistralRealtimeOptions())
        }
    }

    @Test func customSocketQueryItemsSurviveAuthAndIntentPlacement() throws {
        let endpoint = URL(string: "wss://proxy.example.com/live?region=synthetic")!
        let openAI = try OpenAIRealtimeWebSocket.makeConnectRequest(credential: .bearer("synthetic"), options: OpenAIRealtimeSessionOptions(), endpoint: endpoint)
        let items = URLComponents(url: openAI.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "region", value: "synthetic")))
        #expect(items.contains(URLQueryItem(name: "intent", value: "transcription")))
        #expect(!items.contains(where: { $0.name == "model" }))
        let grok = try GrokRealtimeWebSocket.makeConnectRequest(credential: .bearer("synthetic"), options: GrokRealtimeOptions(), endpoint: endpoint)
        #expect(URLComponents(url: grok.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "region", value: "synthetic")) == true)
        let meta = try MetaRealtimeWebSocket.makeConnectRequest(credential: .bearer("synthetic"), options: MetaRealtimeOptions(), endpoint: endpoint)
        #expect(meta.url == endpoint)
    }

    @Test func elevenLabsTokenPlacement() throws {
        var file = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        try SpeechResolvedCredential.token("synthetic-token").authorize(&file, provider: .elevenLabs, capability: .fileTranscription)
        #expect(file.url?.query == "token=synthetic-token")
        #expect(file.value(forHTTPHeaderField: "xi-api-key") == nil)
        let realtime = try ElevenLabsWebSocket.makeConnectRequest(credential: .token("synthetic-token"), modelID: .scribeV2Realtime)
        #expect(URLComponents(url: realtime.url!, resolvingAgainstBaseURL: false)?.queryItems?.last == URLQueryItem(name: "token", value: "synthetic-token"))
    }
}
