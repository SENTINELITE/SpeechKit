import Foundation
import Testing
@testable import SpeechKit

private struct CredentialTestFailure: Error, Equatable {
    let message: String
}

@Suite("Speech Credential")
struct SpeechCredentialTests {
    // MARK: - Equality

    @Test("API key credentials compare by value")
    func apiKeyCredentialsCompareByValue() {
        #expect(SpeechCredential.apiKey("abc") == SpeechCredential.apiKey("abc"))
        #expect(SpeechCredential.apiKey("abc") != SpeechCredential.apiKey("xyz"))
    }

    @Test("Token credentials compare by provider identifier")
    func tokenCredentialsCompareByProviderIdentifier() {
        let sharedID = UUID()
        let first = SpeechTokenProvider(id: sharedID) { "token" }
        let second = SpeechTokenProvider(id: sharedID) { "different-token" }
        let other = SpeechTokenProvider { "token" }

        #expect(first == second)
        #expect(first != other)
        #expect(SpeechCredential.token(first) == SpeechCredential.token(second))
        #expect(SpeechCredential.token(first) != SpeechCredential.token(other))
        #expect(SpeechCredential.token(first) != SpeechCredential.apiKey(""))
    }

    @Test("Credential configuration treats an empty key as unconfigured")
    func credentialConfigurationTreatsEmptyKeyAsUnconfigured() {
        #expect(SpeechCredential.apiKey("").isConfigured == false)
        #expect(SpeechCredential.apiKey("key").isConfigured)
        #expect(SpeechCredential.token(SpeechTokenProvider { "" }).isConfigured)
    }

    @Test("Credential resolution returns the key or fetches the token")
    func credentialResolutionReturnsKeyOrToken() async throws {
        #expect(try await SpeechCredential.apiKey("key").resolve() == "key")
        #expect(try await SpeechCredential.token(SpeechTokenProvider { "fetched" }).resolve() == "fetched")
        #expect(try await SpeechCredential.apiKey("key").resolved() == .apiKey("key"))
        #expect(try await SpeechCredential.token(SpeechTokenProvider { "fetched" }).resolved() == .token("fetched"))
    }

    // MARK: - apiKey compatibility

    @Test("apiKey stays readable and writable on configurations")
    func apiKeyStaysReadableAndWritableOnConfigurations() {
        var elevenLabs = ElevenLabsConfiguration(apiKey: "eleven")
        #expect(elevenLabs.apiKey == "eleven")
        #expect(elevenLabs.credential == .apiKey("eleven"))

        elevenLabs.credential = .token(SpeechTokenProvider { "token" })
        #expect(elevenLabs.apiKey == "")

        elevenLabs.apiKey = "replaced"
        #expect(elevenLabs.credential == .apiKey("replaced"))

        var gemini = GeminiConfiguration(credential: .token(SpeechTokenProvider { "token" }))
        #expect(gemini.apiKey == "")
        gemini.apiKey = "gemini-key"
        #expect(gemini.credential == .apiKey("gemini-key"))
    }

    @MainActor
    @Test("apiKey stays readable and writable on a realtime service")
    func apiKeyStaysReadableAndWritableOnRealtimeService() {
        let service = GrokRealtimeService(apiKey: "xai")
        #expect(service.apiKey == "xai")
        #expect(service.credential == .apiKey("xai"))

        service.credential = .token(SpeechTokenProvider { "token" })
        #expect(service.apiKey == "")

        service.apiKey = "replaced"
        #expect(service.credential == .apiKey("replaced"))
    }

    // MARK: - init(credential:)

    @Test("Every keyed configuration accepts a credential initializer")
    func everyKeyedConfigurationAcceptsCredentialInitializer() {
        let provider = SpeechTokenProvider { "token" }
        let credential = SpeechCredential.token(provider)

        #expect(ElevenLabsConfiguration(credential: credential).credential == credential)
        #expect(AquaConfiguration(credential: credential).credential == credential)
        #expect(CohereConfiguration(credential: credential).credential == credential)
        #expect(GrokConfiguration(credential: credential).credential == credential)
        #expect(OpenAIConfiguration(credential: credential).credential == credential)
        #expect(MetaConfiguration(credential: credential).credential == credential)
        #expect(GeminiConfiguration(credential: credential).credential == credential)
    }

    @MainActor
    @Test("Every realtime service accepts a credential initializer")
    func everyRealtimeServiceAcceptsCredentialInitializer() {
        let credential = SpeechCredential.token(SpeechTokenProvider { "token" })

        #expect(ElevenLabsService(credential: credential).credential == credential)
        #expect(OpenAIRealtimeService(credential: credential).credential == credential)
        #expect(GrokRealtimeService(credential: credential).credential == credential)
        #expect(MetaRealtimeService(credential: credential).credential == credential)
        #expect(GeminiRealtimeService(credential: credential).credential == credential)
    }

    @MainActor
    @Test("SpeechService forwards configuration credentials to realtime services")
    func speechServiceForwardsConfigurationCredentials() {
        let credential = SpeechCredential.token(SpeechTokenProvider { "token" })
        let endpoint = URL(string: "wss://proxy.example.com/gemini")
        let service = SpeechService(
            gemini: GeminiConfiguration(credential: credential, realtimeEndpoint: endpoint)
        )

        #expect(service.geminiRealtimeService.credential == credential)
        #expect(service.geminiRealtimeService.realtimeEndpoint == endpoint)
    }

    // MARK: - Token transport

    @Test("ElevenLabs realtime sends a token as a query parameter")
    func elevenLabsRealtimeSendsTokenAsQueryParameter() throws {
        let request = try ElevenLabsWebSocket.makeConnectRequest(
            credential: .token("eleven-token"),
            modelID: .scribeV2Realtime
        )
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItems?.contains(URLQueryItem(name: "token", value: "eleven-token")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "model_id", value: "scribe_v2_realtime")) == true)
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == nil)
    }

    @Test("ElevenLabs realtime sends an API key as a header")
    func elevenLabsRealtimeSendsAPIKeyAsHeader() throws {
        let request = try ElevenLabsWebSocket.makeConnectRequest(
            credential: .apiKey("eleven-key"),
            modelID: .scribeV2Realtime
        )
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "eleven-key")
        #expect(components.queryItems?.contains(where: { $0.name == "token" }) == false)
    }

    @Test("ElevenLabs file transcription sends a resolved token in the API key header")
    func elevenLabsFileTranscriptionSendsResolvedTokenInHeader() async throws {
        let client = ElevenLabsFileTranscriptionClient(
            credential: .token(SpeechTokenProvider { "eleven-token" })
        )
        let fileURL = credentialTemporaryAudioFileURL(named: "credential-eleven.wav")

        let request = try await client.makeRequest(file: fileURL, modelID: .scribeV2)

        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "eleven-token")
    }

    @Test("OpenAI file transcription sends a resolved token as a bearer token")
    func openAIFileTranscriptionSendsResolvedTokenAsBearer() async throws {
        let client = OpenAIFileTranscriptionClient(
            credential: .token(SpeechTokenProvider { "openai-secret" })
        )
        let fileURL = credentialTemporaryAudioFileURL(named: "credential-openai.wav")

        let request = try await client.makeAuthorizedRequest(file: fileURL)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-secret")
    }

    @Test("OpenAI realtime sends a resolved token as a bearer token")
    func openAIRealtimeSendsResolvedTokenAsBearer() throws {
        let request = try OpenAIRealtimeWebSocket.makeConnectRequest(
            credential: .token("openai-secret"),
            options: OpenAIRealtimeSessionOptions()
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-secret")
    }

    @Test("Gemini REST sends an API key in a header and a token as a bearer token")
    func geminiRESTSendsAPIKeyHeaderAndTokenBearer() async throws {
        let fileURL = credentialTemporaryAudioFileURL(named: "credential-gemini.wav")

        let keyedClient = GeminiFileTranscriptionClient(apiKey: "gemini-key")
        let keyedRequest = try await keyedClient.makeRequest(file: fileURL)
        #expect(keyedRequest.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")
        #expect(keyedRequest.value(forHTTPHeaderField: "Authorization") == nil)

        let tokenClient = GeminiFileTranscriptionClient(
            credential: .token(SpeechTokenProvider { "gemini-access-token" })
        )
        let tokenRequest = try await tokenClient.makeRequest(file: fileURL)
        #expect(tokenRequest.value(forHTTPHeaderField: "Authorization") == "Bearer gemini-access-token")
        #expect(tokenRequest.value(forHTTPHeaderField: "x-goog-api-key") == nil)
    }

    @Test("Gemini Live sends a token in a header and keeps it out of the URL")
    func geminiLiveSendsTokenInHeader() throws {
        let request = try GeminiLiveWebSocket.makeConnectRequest(
            credential: .token("gemini-ephemeral"),
            options: GeminiRealtimeOptions()
        )
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token gemini-ephemeral")
        #expect(components.queryItems?.contains(where: { $0.name == "key" }) != true)
        #expect(request.url?.absoluteString.contains("gemini-ephemeral") == false)
    }

    @Test("Gemini Live sends an API key in the key query parameter")
    func geminiLiveSendsAPIKeyInQueryParameter() throws {
        let request = try GeminiLiveWebSocket.makeConnectRequest(
            credential: .apiKey("gemini-key"),
            options: GeminiRealtimeOptions()
        )
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItems?.contains(URLQueryItem(name: "key", value: "gemini-key")) == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Meta handshake carries the resolved secret as a bearer access token")
    func metaHandshakeCarriesResolvedSecret() throws {
        let data = try JSONEncoder().encode(MetaRealtimeOptions().handshakeMessage(secret: "meta-token"))
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"accessToken\":\"Bearer meta-token\""))
    }

    @Test("Meta file transcription sends a resolved token as a bearer token")
    func metaFileTranscriptionSendsResolvedTokenAsBearer() async throws {
        let client = MetaFileTranscriptionClient(
            credential: .token(SpeechTokenProvider { "meta-token" })
        )
        let fileURL = credentialTemporaryAudioFileURL(named: "credential-meta.wav")

        let request = try await client.makeRequest(file: fileURL)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer meta-token")
    }

    // MARK: - Failing token providers

    @Test("A failing token provider surfaces as a provider failure for file transcription")
    func failingTokenProviderSurfacesAsProviderFailureForFiles() async throws {
        let credential = SpeechCredential.token(
            SpeechTokenProvider { throw CredentialTestFailure(message: "backend down") }
        )
        let client = GrokFileTranscriptionClient(credential: credential)
        let fileURL = credentialTemporaryAudioFileURL(named: "credential-grok-failure.wav")

        do {
            _ = try await client.makeAuthorizedRequest(file: fileURL)
            Issue.record("Expected the failing token provider to throw.")
        } catch let error as SpeechError {
            guard case .providerFailure(let provider, _) = error else {
                Issue.record("Expected a providerFailure, got \(error).")
                return
            }
            #expect(provider == .grok)
        }
    }

    @MainActor
    @Test("A failing token provider surfaces as a realtime error state")
    func failingTokenProviderSurfacesAsRealtimeErrorState() async {
        let service = GrokRealtimeService(
            credential: .token(SpeechTokenProvider { throw CredentialTestFailure(message: "backend down") })
        )

        await service.startListening()

        #expect(service.connectionState.isError)
        #expect(service.lastError as? CredentialTestFailure == CredentialTestFailure(message: "backend down"))
    }

    // MARK: - Endpoint overrides

    @Test("Grok file transcription honors an endpoint override")
    func grokFileTranscriptionHonorsEndpointOverride() throws {
        let endpoint = try #require(URL(string: "https://proxy.example.com/grok/stt"))
        let client = GrokFileTranscriptionClient(apiKey: "xai-key", endpoint: endpoint)
        let fileURL = credentialTemporaryAudioFileURL(named: "credential-grok.wav")

        let request = try client.makeRequest(file: fileURL)

        #expect(request.url == endpoint)
    }

    @Test("Grok realtime honors an endpoint override and keeps appended query items")
    func grokRealtimeHonorsEndpointOverrideAndKeepsQueryItems() throws {
        let endpoint = try #require(URL(string: "wss://proxy.example.com/grok/stt?tenant=acme"))
        let request = try GrokRealtimeWebSocket.makeConnectRequest(
            credential: .apiKey("xai-key"),
            options: GrokRealtimeOptions(sampleRate: 24000),
            endpoint: endpoint
        )
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)

        #expect(components.host == "proxy.example.com")
        #expect(components.path == "/grok/stt")
        #expect(queryItems.contains(URLQueryItem(name: "tenant", value: "acme")))
        #expect(queryItems.contains(URLQueryItem(name: "sample_rate", value: "24000")))
        #expect(queryItems.contains(URLQueryItem(name: "encoding", value: "pcm")))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xai-key")
    }

    @Test("Gemini interactions honor an endpoint override for requests and polling")
    func geminiInteractionsHonorEndpointOverride() async throws {
        let endpoint = try #require(URL(string: "https://proxy.example.com/gemini/v1beta/interactions"))
        let client = GeminiFileTranscriptionClient(apiKey: "gemini-key", endpoint: endpoint)
        let fileURL = credentialTemporaryAudioFileURL(named: "credential-gemini-endpoint.wav")

        let request = try await client.makeRequest(file: fileURL)
        #expect(request.url == endpoint)

        let pollRequest = try client.makePollRequest(interactionID: "abc123")
        #expect(
            pollRequest.url?.absoluteString == "https://proxy.example.com/gemini/v1beta/interactions/abc123"
        )
    }

    @Test("Gemini files honor an endpoint override for uploads and state polling")
    func geminiFilesHonorEndpointOverride() throws {
        let endpoint = try #require(URL(string: "https://proxy.example.com/upload/v1beta/files"))
        let client = GeminiFilesClient(apiKey: "gemini-key", endpoint: endpoint)
        let fileURL = credentialTemporaryAudioFileURL(named: "credential-gemini-files.wav")

        let startRequest = try client.makeStartRequest(
            file: fileURL,
            mimeType: "audio/wav",
            byteCount: 44,
            timeoutInterval: 60
        )
        #expect(startRequest.url == endpoint)

        let stateRequest = try client.makeStateRequest(fileName: "files/abc123", timeoutInterval: 60)
        #expect(stateRequest.url?.absoluteString == "https://proxy.example.com/v1beta/files/abc123")
    }

    @Test("Gemini files keep the default state URL without an override")
    func geminiFilesKeepDefaultStateURL() throws {
        let client = GeminiFilesClient(apiKey: "gemini-key")

        let stateRequest = try client.makeStateRequest(fileName: "files/abc123", timeoutInterval: 60)

        #expect(
            stateRequest.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/files/abc123"
        )
    }

    @Test("Meta realtime honors an endpoint override and keeps the session query item")
    func metaRealtimeHonorsEndpointOverride() throws {
        let endpoint = try #require(URL(string: "wss://proxy.example.com/meta/realtime"))
        let request = try MetaRealtimeWebSocket.makeConnectRequest(
            credential: .apiKey("meta-key"),
            options: MetaRealtimeOptions(sessionID: "session-1"),
            endpoint: endpoint
        )
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "proxy.example.com")
        #expect(components.path == "/meta/realtime")
        #expect(components.queryItems?.contains(URLQueryItem(name: "sessionId", value: "session-1")) == true)
    }

    @Test("OpenAI realtime honors an endpoint override and keeps the model query item")
    func openAIRealtimeHonorsEndpointOverride() throws {
        let endpoint = try #require(URL(string: "wss://proxy.example.com/openai/realtime"))
        let request = try OpenAIRealtimeWebSocket.makeConnectRequest(
            credential: .apiKey("openai-key"),
            options: OpenAIRealtimeSessionOptions(),
            endpoint: endpoint
        )
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.path == "/openai/realtime")
        #expect(components.queryItems?.contains(where: { $0.name == "model" }) == true)
    }
}

private extension SpeechRealtimeConnectionState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// A freshly created temporary directory, unique to this call.
private func uniqueTemporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Writes a stub audio file into a fresh per-call temporary directory.
///
/// Tests run in parallel and assert on the multipart `filename`, so the
/// directory is unique while the last path component stays `fileName`.
private func credentialTemporaryAudioFileURL(named fileName: String) -> URL {
    let url = uniqueTemporaryDirectory().appendingPathComponent(fileName)
    try? credentialMinimalWAVData().write(to: url)
    return url
}

/// A valid 16 kHz, 16-bit, mono PCM WAV holding 0.1 seconds of silence.
///
/// AVFoundation must be able to read a real duration from this file, so the
/// RIFF and `data` chunk sizes have to match the 3,200 bytes of samples.
private func credentialMinimalWAVData() -> Data {
    var data = Data([
        0x52, 0x49, 0x46, 0x46, // "RIFF"
        0xA4, 0x0C, 0x00, 0x00, // chunk size: 36 + 3200
        0x57, 0x41, 0x56, 0x45, // "WAVE"
        0x66, 0x6D, 0x74, 0x20, // "fmt "
        0x10, 0x00, 0x00, 0x00, // fmt chunk size: 16
        0x01, 0x00,             // PCM
        0x01, 0x00,             // 1 channel
        0x80, 0x3E, 0x00, 0x00, // 16000 Hz
        0x00, 0x7D, 0x00, 0x00, // 32000 bytes per second
        0x02, 0x00,             // block align: 2
        0x10, 0x00,             // 16 bits per sample
        0x64, 0x61, 0x74, 0x61, // "data"
        0x80, 0x0C, 0x00, 0x00  // data chunk size: 3200
    ])
    data.append(Data(repeating: 0, count: 3_200))
    return data
}
