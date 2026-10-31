import Foundation

/// A self-hosted SpeechKit relay. `.none` authentication is for development only.
public struct SpeechRelay: Sendable, SpeechRedactedDiagnostics {
    public enum Authentication: Sendable {
        case appAttest
        case bearer(SpeechTokenResolver)
        case appAttestAndBearer(SpeechTokenResolver)
        case none
    }
    public enum TokenStrategy: Sendable { case proxyAll, vendorTokensWhenAvailable }
    public enum UploadOptimization: Sendable, Equatable {
        case on
        case off
    }

    public let url: URL
    public let providers: Set<SpeechFileTranscriptionProvider>
    public let tokenStrategy: TokenStrategy
    /// Whether relay imports may be repackaged or converted locally. Defaults to `.on`.
    public let optimizedUploads: UploadOptimization
    public let pinnedPublicKeyHashes: Set<String>
    /// A stable, nonsecret account identifier used to namespace the local App Attest key.
    /// Use a different value for each signed-in account. `nil` retains the installation-wide identity.
    public let appAttestAccountID: String?
    let authentication: Authentication

    public init(url: URL, authentication: Authentication = .appAttest,
                providers: Set<SpeechFileTranscriptionProvider> = Set(SpeechFileTranscriptionProvider.allCases.filter { $0.rawValue != "apple" }),
                tokenStrategy: TokenStrategy = .proxyAll, pinnedPublicKeyHashes: Set<String> = [],
                appAttestAccountID: String? = nil, optimizedUploads: UploadOptimization = .on) {
        self.url = url
        self.authentication = authentication
        self.providers = providers
        self.tokenStrategy = tokenStrategy
        self.optimizedUploads = optimizedUploads
        self.pinnedPublicKeyHashes = pinnedPublicKeyHashes
        self.appAttestAccountID = appAttestAccountID
    }

    /// Forgets this relay/account's local key identifier after outstanding assertions finish.
    /// The next operation registers a new key. Does not revoke server keys or active sessions.
    /// Stop listening before resetting. Concurrent resets are serialized and safe to repeat.
    public func resetAppAttestKey() async throws {
        try validate()
        try await SpeechAppAttest.shared.resetKey(relay: self)
    }

    var requiresProof: Bool {
        switch authentication {
        case .appAttest, .appAttestAndBearer: true
        case .bearer, .none: false
        }
    }

    func validate() throws {
        try SpeechEndpointPolicy.validate(url)
        guard url.query == nil, url.path == "/" || url.path.isEmpty else { throw SpeechFailure(.invalidEndpoint) }
        for pin in pinnedPublicKeyHashes {
            let value = pin.hasPrefix("sha256/") ? String(pin.dropFirst(7)) : pin
            guard Data(base64Encoded: value)?.count == 32 else { throw SpeechFailure(.pinningFailed) }
        }
    }

    func endpoint(_ path: String, websocket: Bool = false) throws -> URL {
        try validate()
        guard path.hasPrefix("/"), !path.contains(".."), !path.contains("%"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SpeechFailure(.invalidEndpoint) }
        components.path = "/speechkit/v1" + path
        if websocket { components.scheme = url.scheme?.lowercased() == "https" ? "wss" : "ws" }
        guard let result = components.url else { throw SpeechFailure(.invalidEndpoint) }
        try SpeechEndpointPolicy.validate(result, websocket: websocket)
        return result
    }

    func route(provider: SpeechFileTranscriptionProvider, capability: SpeechCapability) throws -> URL {
        guard providers.contains(provider) else { throw SpeechFailure(.unsupportedAuthentication) }
        let path: String
        switch (provider, capability) {
        case (.elevenLabs, .fileTranscription): path = "/v1/speech-to-text"
        case (.elevenLabs, .realtime): path = "/v1/speech-to-text/realtime"
        case (.openAI, .fileTranscription), (.mistral, .fileTranscription), (.aqua, .fileTranscription): path = "/v1/audio/transcriptions"
        case (.openAI, .realtime): path = "/v1/realtime"
        case (.grok, _): path = "/v1/stt"
        case (.meta, .fileTranscription): path = "/v1/asr/transcribe"
        case (.meta, .realtime): path = "/v1/asr/realtime"
        case (.mistral, .realtime): path = "/v1/audio/transcriptions/realtime"
        case (.fishAudio, .fileTranscription): path = "/v1/asr"
        case (.fishAudio, .realtime): path = "/v1/asr/realtime"
        case (.cohere, .fileTranscription): path = "/v2/audio/transcriptions"
        case (.gemini, .fileTranscription): path = "/v1beta/interactions"
        case (.gemini, .realtime): path = "/live"
        default: throw SpeechFailure(.unsupportedAuthentication)
        }
        var result = try endpoint("/" + provider.rawValue.lowercased() + path, websocket: capability == .realtime)
        if provider == .openAI && capability == .realtime {
            var components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "intent", value: "transcription")]
            result = components.url!
        }
        return result
    }
}
