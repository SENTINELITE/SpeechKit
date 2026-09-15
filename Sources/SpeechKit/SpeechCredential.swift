import Foundation

/// A credential used to authorize provider requests.
///
/// Use ``SpeechCredential/apiKey(_:)`` when your app holds a long-lived vendor
/// API key, and ``SpeechCredential/token(_:)`` when your app fetches a
/// short-lived token from your own backend. SpeechKit resolves a token
/// provider once per file transcription request and once per realtime session,
/// so the app never has to keep a long-lived key in memory.
///
/// ```swift
/// let openAI = OpenAIConfiguration(
///     credential: .token(SpeechTokenProvider { try await backend.fetchOpenAIClientSecret() })
/// )
/// ```
public enum SpeechCredential: Sendable, Equatable {
    /// A long-lived provider API key.
    case apiKey(String)
    /// A short-lived token fetched on demand, for example from your own backend.
    case token(SpeechTokenProvider)
}

/// Fetches a short-lived provider token on demand.
///
/// SpeechKit calls ``SpeechTokenProvider/token()`` once per file transcription
/// request and once per realtime session, so the closure should return a token
/// that is valid for at least the lifetime of one request or session.
///
/// Two token providers are equal when they share the same ``SpeechTokenProvider/id``.
///
/// ```swift
/// let provider = SpeechTokenProvider { try await backend.fetchToken() }
/// ```
public struct SpeechTokenProvider: Sendable, Equatable, Identifiable {
    /// The stable identity used to compare two token providers.
    public let id: UUID

    private let fetch: @Sendable () async throws -> String

    /// Creates a token provider.
    ///
    /// - Parameters:
    ///   - id: The stable identity used for equality. Pass an existing
    ///     identifier to keep two providers equal across recreation.
    ///   - fetch: A closure that returns a short-lived provider token.
    public init(id: UUID = UUID(), _ fetch: @escaping @Sendable () async throws -> String) {
        self.id = id
        self.fetch = fetch
    }

    /// Fetches a token.
    ///
    /// SpeechKit calls this once per file request and once per realtime session.
    ///
    /// - Returns: A short-lived provider token.
    /// - Throws: Any error thrown by the fetch closure.
    public func token() async throws -> String {
        try await fetch()
    }

    /// Returns a Boolean value that indicates whether two token providers share an identifier.
    public static func == (lhs: SpeechTokenProvider, rhs: SpeechTokenProvider) -> Bool {
        lhs.id == rhs.id
    }
}

/// A credential that has been resolved to a concrete secret.
///
/// The case records how the secret was obtained, because several providers send
/// an API key and a short-lived token in different places.
enum SpeechResolvedCredential: Sendable, Equatable {
    /// A resolved long-lived API key.
    case apiKey(String)
    /// A resolved short-lived token.
    case token(String)

    /// The resolved secret value.
    var secret: String {
        switch self {
        case .apiKey(let secret), .token(let secret):
            return secret
        }
    }

    /// A Boolean value that indicates whether the resolved secret is empty.
    var isEmpty: Bool {
        secret.isEmpty
    }
}

extension SpeechCredential {
    /// A Boolean value that indicates whether the credential can authorize a request.
    ///
    /// An empty API key string is unconfigured. A token provider is always
    /// configured, because SpeechKit cannot know the token value until it
    /// resolves the credential.
    var isConfigured: Bool {
        switch self {
        case .apiKey(let key):
            return !key.isEmpty
        case .token:
            return true
        }
    }

    /// The long-lived API key, or an empty string for a token provider.
    var staticAPIKey: String {
        switch self {
        case .apiKey(let key):
            return key
        case .token:
            return ""
        }
    }

    /// Returns the API key, or fetches a short-lived token.
    func resolve() async throws -> String {
        try await resolved().secret
    }

    /// Returns the resolved secret paired with how it was obtained.
    func resolved() async throws -> SpeechResolvedCredential {
        switch self {
        case .apiKey(let key):
            return .apiKey(key)
        case .token(let provider):
            return .token(try await provider.token())
        }
    }

    /// Returns the resolved secret, reporting a failing token provider as a provider failure.
    func resolved(for provider: SpeechFileTranscriptionProvider) async throws -> SpeechResolvedCredential {
        switch self {
        case .apiKey(let key):
            return .apiKey(key)
        case .token(let tokenProvider):
            do {
                return .token(try await tokenProvider.token())
            } catch {
                throw SpeechError.providerFailure(provider: provider, reason: error.localizedDescription)
            }
        }
    }
}
