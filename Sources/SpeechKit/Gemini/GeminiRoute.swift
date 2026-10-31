import Foundation

/// A complete Gemini route. Mixed origins require an explicit policy and are forbidden for relay tickets.
public struct GeminiRoute: Sendable, Equatable, SpeechRedactedDiagnostics {
    public enum OriginPolicy: Sendable { case sameOrigin, explicitMixedOrigins }
    public let originPolicy: OriginPolicy
    public let interactions: URL
    public let files: URL
    public let realtime: URL

    public init(interactions: URL, files: URL, realtime: URL, originPolicy: OriginPolicy = .sameOrigin) throws {
        try Self.validate(interactions: interactions, files: files, originPolicy: originPolicy)
        try SpeechEndpointPolicy.validate(realtime, websocket: true)
        if originPolicy == .sameOrigin {
            let restPort = interactions.port ?? (interactions.scheme == "https" ? 443 : 80)
            let socketPort = realtime.port ?? (realtime.scheme == "wss" ? 443 : 80)
            guard interactions.host?.lowercased() == realtime.host?.lowercased(), restPort == socketPort else {
                throw SpeechFailure(.invalidEndpoint)
            }
        }
        self.originPolicy = originPolicy
        self.interactions = interactions
        self.files = files
        self.realtime = realtime
    }

    static func validate(interactions: URL?, files: URL?, originPolicy: OriginPolicy = .sameOrigin) throws {
        try SpeechEndpointPolicy.validate(interactions)
        try SpeechEndpointPolicy.validate(files)
        guard let interactions, let files,
              originPolicy == .explicitMixedOrigins || SpeechEndpointPolicy.sameOrigin(interactions, files),
              interactions.path.hasSuffix("/interactions"), files.path.hasSuffix("/files") else {
            throw SpeechFailure(.invalidEndpoint)
        }
    }

    static func identifier(_ value: String, prefix: String) throws -> String {
        let id = value.hasPrefix(prefix + "/") ? String(value.dropFirst(prefix.count + 1)) : value
        guard !id.isEmpty, id != ".", id != "..",
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw SpeechFailure(.invalidResponse)
        }
        return id
    }
}

extension GeminiConfiguration {
    public mutating func setRoute(_ route: GeminiRoute) {
        routeOriginPolicy = route.originPolicy
        fileEndpoint = route.interactions
        filesEndpoint = route.files
        realtimeEndpoint = route.realtime
    }
}
