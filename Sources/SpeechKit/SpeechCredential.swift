import Foundation

public enum SpeechCapability: String, Sendable, CaseIterable {
    case fileTranscription, realtime
}

public enum SpeechCredentialPolicy: Sendable {
    case allowStaticKeys, disallowStaticKeys, relayOnly
}

/// Nonsecret authorization context for one logical operation.
public struct SpeechTokenContext: Sendable, Equatable {
    public let provider: SpeechFileTranscriptionProvider
    public let capability: SpeechCapability
    public let model: String
    public let operationID: UUID
    public let attempt: Int
    public let authMode: SpeechCredential.Kind
    public let approvedDestinations: [URL]

    public init(provider: SpeechFileTranscriptionProvider, capability: SpeechCapability,
                model: String, operationID: UUID = UUID(), attempt: Int = 0,
                authMode: SpeechCredential.Kind = .vendorToken, approvedDestinations: [URL] = []) {
        self.provider = provider
        self.capability = capability
        self.model = model
        self.operationID = operationID
        self.attempt = attempt
        self.authMode = authMode
        self.approvedDestinations = approvedDestinations
    }
}

/// Token metadata is descriptive. The accepting server enforces expiry and reuse.
public struct SpeechAccessToken: Sendable, SpeechRedactedDiagnostics {
    private let value: String
    public let expiresAt: Date?
    public let isReusable: Bool

    public init(value: String, expiresAt: Date? = nil, isReusable: Bool = false) {
        self.value = value
        self.expiresAt = expiresAt
        self.isReusable = isReusable
    }

    fileprivate func validatedValue() throws -> String {
        try SpeechResolvedCredential.validateSecret(value)
        guard expiresAt.map({ $0 > Date() }) ?? true else { throw SpeechFailure(.invalidCredential) }
        return value
    }
}

public struct SpeechTokenResolver: Sendable, Equatable, Identifiable, SpeechRedactedDiagnostics {
    public let id: UUID
    private let resolveToken: @Sendable (SpeechTokenContext) async throws -> SpeechAccessToken

    public init(id: UUID = UUID(), _ resolve: @escaping @Sendable (SpeechTokenContext) async throws -> SpeechAccessToken) {
        self.id = id
        self.resolveToken = resolve
    }

    public init(id: UUID = UUID(), _ resolve: @escaping @Sendable (SpeechTokenContext) async throws -> String) {
        self.init(id: id) { context in SpeechAccessToken(value: try await resolve(context)) }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    fileprivate func token(for context: SpeechTokenContext) async throws -> String {
        do {
            try Task.checkCancellation()
            let token = try await resolveToken(context)
            try Task.checkCancellation()
            return try token.validatedValue()
        } catch is CancellationError { throw CancellationError() }
        catch let failure as SpeechFailure { throw failure }
        catch { throw SpeechFailure(.credentialResolution) }
    }
}

/// Opaque authorization. There is no public secret readback or resolver invocation.
public struct SpeechCredential: Sendable, Equatable {
    public enum Kind: String, Sendable { case apiKey, vendorToken, bearer, relay }
    private enum Storage: Sendable, Equatable {
        case apiKey(String)
        case resolver(Kind, SpeechTokenResolver)
    }
    private let storage: Storage
    private(set) var relayOrigin: URL? = nil
    private(set) var pinnedPublicKeyHashes: Set<String> = []
    private(set) var relayRequestPreparation: SpeechRelayRequestPreparation?
    private(set) var relayOptimizesUploads = true
    var optimizeUploads: Bool? { kind == .relay ? relayOptimizesUploads : nil }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage == rhs.storage && lhs.relayOrigin == rhs.relayOrigin && lhs.pinnedPublicKeyHashes == rhs.pinnedPublicKeyHashes && lhs.relayOptimizesUploads == rhs.relayOptimizesUploads
    }
    public var kind: Kind {
        switch storage {
        case .apiKey: .apiKey
        case .resolver(let kind, _): kind
        }
    }

    public static func apiKey(_ value: String) -> Self { Self(storage: .apiKey(value)) }
    public static func vendorToken(_ resolver: SpeechTokenResolver) -> Self { Self(storage: .resolver(.vendorToken, resolver)) }
    public static func bearer(_ resolver: SpeechTokenResolver) -> Self { Self(storage: .resolver(.bearer, resolver)) }
    static func relay(_ resolver: SpeechTokenResolver) -> Self { Self(storage: .resolver(.relay, resolver)) }

    func withRelayTransport(origin: URL, pinnedPublicKeyHashes: Set<String>, optimizeUploads: Bool = true, prepare: SpeechRelayRequestPreparation? = nil) -> Self {
        var value = self
        value.relayRequestPreparation = prepare
        value.relayOrigin = origin
        value.pinnedPublicKeyHashes = pinnedPublicKeyHashes
        value.relayOptimizesUploads = optimizeUploads
        return value
    }

    var isConfigured: Bool {
        switch storage {
        case .apiKey(let key): !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .resolver: true
        }
    }
    var staticAPIKey: String {
        if case .apiKey(let key) = storage { return key }
        return ""
    }

    func validate(provider: SpeechFileTranscriptionProvider, capability: SpeechCapability,
                  endpoint: URL?, policy: SpeechCredentialPolicy = .allowStaticKeys) throws {
        try SpeechEndpointPolicy.validate(endpoint, websocket: capability == .realtime)
        if policy != .allowStaticKeys && kind == .apiKey { throw SpeechFailure(.staticKeysDisallowed) }
        if policy == .relayOnly && kind != .relay { throw SpeechFailure(.unsupportedAuthentication) }
        if kind == .relay, let origin = relayOrigin {
            guard let endpoint, endpoint.host?.lowercased() == origin.host?.lowercased(),
                  (endpoint.port ?? (["https", "wss"].contains(endpoint.scheme?.lowercased() ?? "") ? 443 : 80)) ==
                    (origin.port ?? (origin.scheme?.lowercased() == "https" ? 443 : 80)),
                  endpoint.scheme?.lowercased() == (capability == .realtime ? (origin.scheme?.lowercased() == "https" ? "wss" : "ws") : origin.scheme?.lowercased()),
                  endpoint.path.hasPrefix("/speechkit/v1/") else { throw SpeechFailure(.invalidEndpoint) }
        }
        if kind == .vendorToken {
            guard provider == .elevenLabs || (capability == .realtime && [.openAI, .gemini, .mistral].contains(provider)) else {
                throw SpeechFailure(.unsupportedAuthentication)
            }
        }
        if kind == .bearer, let host = endpoint?.host?.lowercased(), Self.vendorHosts.contains(host),
           !(provider == .gemini && capability == .fileTranscription) {
            throw SpeechFailure(.unsupportedAuthentication)
        }
    }

    func resolved(for provider: SpeechFileTranscriptionProvider, capability: SpeechCapability = .fileTranscription,
                  model: String = "", endpoint: URL?, destinations: [URL] = [],
                  operationID: UUID = UUID(), attempt: Int = 0,
                  policy: SpeechCredentialPolicy = .allowStaticKeys) async throws -> SpeechResolvedCredential {
        try validate(provider: provider, capability: capability, endpoint: endpoint, policy: policy)
        for destination in destinations {
            try validate(provider: provider, capability: capability, endpoint: destination, policy: policy)
        }
        if kind == .vendorToken && provider == .mistral && model != "voxtral-mini-transcribe-realtime-2602" {
            throw SpeechFailure(.unsupportedAuthentication)
        }
        let context = SpeechTokenContext(provider: provider, capability: capability, model: model,
                                         operationID: operationID, attempt: attempt, authMode: kind,
                                         approvedDestinations: destinations.isEmpty ? [endpoint].compactMap { $0 } : destinations)
        let value: String
        switch storage {
        case .apiKey(let key): value = key
        case .resolver(_, let resolver): value = try await resolver.token(for: context)
        }
        try Task.checkCancellation()
        try SpeechResolvedCredential.validateSecret(value)
        var resolved = SpeechResolvedCredential(kind: kind, secret: value, pinnedPublicKeyHashes: pinnedPublicKeyHashes)
        resolved.relayRequestPreparation = relayRequestPreparation
        if kind == .relay && attempt == 0 {
            resolved.renewRelayTicket = {
                try await self.resolved(for: provider, capability: capability, model: model, endpoint: endpoint,
                                        destinations: destinations, operationID: operationID, attempt: 1, policy: policy)
            }
        }
        return resolved
    }

    static let vendorHosts: Set<String> = ["api.elevenlabs.io", "api.openai.com", "generativelanguage.googleapis.com",
                                          "api.x.ai", "api.meta.ai", "api.mistral.ai", "api.fish.audio",
                                          "api.cohere.com", "api.aquavoice.com"]
}

struct SpeechResolvedCredential: Sendable, Equatable {
    let kind: SpeechCredential.Kind
    let secret: String
    var pinnedPublicKeyHashes: Set<String> = []
    var relayRequestPreparation: SpeechRelayRequestPreparation?
    var renewRelayTicket: (@Sendable () async throws -> SpeechResolvedCredential)? = nil
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.secret == rhs.secret && lhs.pinnedPublicKeyHashes == rhs.pinnedPublicKeyHashes
    }
    var isEmpty: Bool { secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    static func apiKey(_ value: String) -> Self { Self(kind: .apiKey, secret: value) }
    static func token(_ value: String) -> Self { Self(kind: .vendorToken, secret: value) }
    static func bearer(_ value: String) -> Self { Self(kind: .bearer, secret: value) }
    static func relay(_ value: String) -> Self { Self(kind: .relay, secret: value) }

    func replacingRelayTicket(_ value: String) throws -> Self {
        guard kind == .relay else { throw SpeechFailure(.unsupportedAuthentication) }
        try Self.validateSecret(value)
        return Self(kind: kind, secret: value, pinnedPublicKeyHashes: pinnedPublicKeyHashes,
                    relayRequestPreparation: relayRequestPreparation, renewRelayTicket: renewRelayTicket)
    }

    static func validateSecret(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.contains(where: { $0.isNewline || $0 == "\0" }) else { throw SpeechFailure(.invalidCredential) }
    }

    func authorize(_ request: inout URLRequest, provider: SpeechFileTranscriptionProvider,
                   capability: SpeechCapability) throws {
        try Self.validateSecret(secret)
        // Builders are also callable with already-resolved credentials in tests.
        if kind == .vendorToken {
            guard provider == .elevenLabs || (capability == .realtime && [.openAI, .gemini, .mistral].contains(provider)) else {
                throw SpeechFailure(.unsupportedAuthentication)
            }
        }
        if kind == .vendorToken && provider == .elevenLabs {
            guard let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw SpeechFailure(.invalidEndpoint)
            }
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "token", value: secret)]
            request.url = components.url
        } else if kind == .apiKey && provider == .elevenLabs {
            request.setValue(secret, forHTTPHeaderField: "xi-api-key")
        } else if kind == .apiKey && provider == .gemini {
            request.setValue(secret, forHTTPHeaderField: "x-goog-api-key")
        } else if kind == .vendorToken && provider == .gemini {
            request.setValue("Token \(secret)", forHTTPHeaderField: "Authorization")
        } else if kind == .vendorToken && provider == .mistral {
            guard secret.utf8.allSatisfy({ $0 > 32 && $0 < 127 && !"()<>@,;:\\\"/[]?={}".utf8.contains($0) }) else {
                throw SpeechFailure(.invalidCredential)
            }
            request.setValue("realtime, \(secret)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        } else if provider != .meta || capability != .realtime || kind == .relay || kind == .bearer {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
    }
}
