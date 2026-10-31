import Foundation
import Security

/// Safe failures contain categories and numeric status, never server or callback text.
public struct SpeechFailure: Error, LocalizedError, Sendable, Equatable {
    public enum Category: String, Sendable {
        case invalidEndpoint, redirectRefused, invalidCredential, unsupportedAuthentication
        case credentialResolution, transport, cancelled, invalidResponse, server
        case staticKeysDisallowed, attestationUnsupported, attestationFailed, pinningFailed
        case unsupportedMediaType, audioTooLarge, audioTooLong, audioNormalizationFailed
    }

    public let category: Category
    public let statusCode: Int?

    public init(_ category: Category, statusCode: Int? = nil) {
        self.category = category
        self.statusCode = statusCode
    }

    public var errorDescription: String? {
        switch category {
        case .invalidEndpoint: "The endpoint is not permitted."
        case .redirectRefused: "The server redirected the request. Redirects are disabled."
        case .invalidCredential: "The credential is empty or expired."
        case .unsupportedAuthentication: "This authentication mode is not supported for this route."
        case .credentialResolution: "The credential resolver failed."
        case .transport: "The connection failed."
        case .cancelled: "The operation was cancelled."
        case .invalidResponse: "The server returned an invalid response."
        case .server: "The server rejected the request."
        case .staticKeysDisallowed: "Static API keys are disabled by credential policy."
        case .attestationUnsupported: "App Attest is not supported on this device. Choose an explicit alternative authentication mode."
        case .attestationFailed: "App Attest authentication failed."
        case .pinningFailed: "The relay public key did not match a configured pin."
        case .unsupportedMediaType: "The relay requires PCM WAV, FLAC, Ogg Opus/Vorbis, or MP3 audio supported by the provider. Enable automatic import normalization or supply a supported file."
        case .audioTooLarge: "The audio exceeds the provider's upload size limit. Shorten the recording or split it before uploading."
        case .audioTooLong: "The audio exceeds the provider's duration limit. Shorten the recording or split it before uploading."
        case .audioNormalizationFailed: "The audio could not be decoded into a supported relay format. Export the recording as PCM WAV and try again."
        }
    }
}

enum SpeechErrorBoundary {
    static func safe(_ error: Error) -> Error {
        if error is SpeechError || error is ElevenLabsError || error is OpenAIError || error is GrokRealtimeError ||
           error is MetaRealtimeError || error is GeminiRealtimeError || error is MistralRealtimeError ||
           error is FishAudioRealtimeError || error is SpeechAudioCaptureError { return error }
        if let failure = error as? SpeechFailure { return failure }
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return SpeechFailure(.cancelled)
        }
        return SpeechFailure(.transport)
    }
}

enum SpeechEndpointPolicy {
    static func validate(_ url: URL?, websocket: Bool = false) throws {
        guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.fragment == nil else { throw SpeechFailure(.invalidEndpoint) }
        let scheme = parts.scheme?.lowercased()
        let secure = websocket ? "wss" : "https"
        let development = websocket ? "ws" : "http"
        guard scheme == secure || (scheme == development && isLoopback(host)) else {
            throw SpeechFailure(.invalidEndpoint)
        }
        let authNames: Set<String> = ["key", "api_key", "apikey", "access_token", "token", "authorization"]
        guard !(parts.queryItems ?? []).contains(where: { authNames.contains($0.name.lowercased()) }) else {
            throw SpeechFailure(.invalidEndpoint)
        }
    }

    static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
    }

    static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        func origin(_ url: URL) -> String {
            let scheme = url.scheme?.lowercased() ?? ""
            let port = url.port ?? (["https", "wss"].contains(scheme) ? 443 : 80)
            return "\(scheme)://\(url.host?.lowercased() ?? ""):\(port)"
        }
        return origin(first) == origin(second)
    }
}

/// All redirects are refused, including same-origin redirects. Audio is never replayed.
final class SpeechTransportDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let pins: Set<String>
    init(pins: Set<String> = []) { self.pins = pins }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        evaluate(challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        evaluate(challenge, completionHandler: completionHandler)
    }

    private func evaluate(_ challenge: URLAuthenticationChallenge,
                          completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.rejectProtectionSpace, nil)
            return
        }
        guard !pins.isEmpty else { completionHandler(.performDefaultHandling, nil); return }
        guard let trust = challenge.protectionSpace.serverTrust, SecTrustEvaluateWithError(trust, nil),
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = certificates.first,
              SpeechPublicKeyPinning.matches(certificateDER: SecCertificateCopyData(leaf) as Data, pins: pins) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum SpeechTransport {
    static func session(copying source: URLSession? = nil, pinnedPublicKeyHashes: Set<String> = []) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = source?.configuration.protocolClasses
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        return URLSession(configuration: configuration, delegate: SpeechTransportDelegate(pins: pinnedPublicKeyHashes), delegateQueue: nil)
    }

    static func data(for request: URLRequest, session: URLSession,
                     prepare: SpeechRelayRequestPreparation? = nil) async throws -> (Data, URLResponse) {
        // Generated query tokens have already passed validation before authorization.
        guard let url = request.url else { throw SpeechFailure(.invalidEndpoint) }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.queryItems = nil
        try SpeechEndpointPolicy.validate(parts?.url)
        try Task.checkCancellation()
        for attempt in 0...1 {
            let prepared = try await prepare?(request) ?? SpeechPreparedRequest(request: request)
            let result: (Data, URLResponse)
            do {
                try Task.checkCancellation()
                result = try await session.data(for: prepared.request)
            } catch {
                await prepared.finish()
                if error is CancellationError { throw CancellationError() }
                throw SpeechErrorBoundary.safe(error)
            }
            await prepared.finish()
            if let response = result.1 as? HTTPURLResponse {
                if response.statusCode == 415, prepare != nil,
                   (try? JSONDecoder().decode(RelayError.self, from: result.0).error.code) == "unsupported_media_type" {
                    throw SpeechFailure(.unsupportedMediaType, statusCode: 415)
                }
                if (300...399).contains(response.statusCode) {
                    throw SpeechFailure(.redirectRefused, statusCode: response.statusCode)
                }
                if response.statusCode == 401, attempt == 0, let renew = prepared.renewRejectedTicket {
                    try await renew()
                    continue
                }
            }
            return result
        }
        throw SpeechFailure(.transport)
    }

    private struct RelayError: Decodable {
        struct Detail: Decodable { let code: String }
        let error: Detail
    }
}
