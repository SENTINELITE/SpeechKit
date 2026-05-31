import Foundation

/// Errors returned by provider-neutral SpeechKit APIs.
public enum SpeechError: Error, LocalizedError, Sendable, Equatable {
    /// The requested provider has no configuration on the service.
    case providerNotConfigured(SpeechFileTranscriptionProvider)
    /// The requested realtime provider has no configuration on the service.
    case realtimeProviderNotConfigured(SpeechRealtimeProvider)
    /// The requested provider does not support the requested capability.
    case unsupportedCapability(provider: SpeechFileTranscriptionProvider, capability: String)
    /// The request used options for a different provider.
    case invalidOptionsForProvider(expected: SpeechFileTranscriptionProvider, received: SpeechFileTranscriptionProvider)
    /// The provider returned a response that SpeechKit could not interpret.
    case invalidResponse(provider: SpeechFileTranscriptionProvider)
    /// The provider rejected or failed a file upload.
    case uploadFailed(provider: SpeechFileTranscriptionProvider, reason: String)
    /// SpeechKit could not decode the provider response.
    case decodingFailed(provider: SpeechFileTranscriptionProvider, reason: String)
    /// The provider request failed for a reason that does not fit a narrower case.
    case providerFailure(provider: SpeechFileTranscriptionProvider, reason: String)

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let provider):
            return "\(provider.rawValue) is not configured."
        case .realtimeProviderNotConfigured(let provider):
            return "\(provider.rawValue) realtime transcription is not configured."
        case .unsupportedCapability(let provider, let capability):
            return "\(provider.rawValue) does not support \(capability)."
        case .invalidOptionsForProvider(let expected, let received):
            return "Received \(received.rawValue) options for \(expected.rawValue)."
        case .invalidResponse(let provider):
            return "Received an invalid response from \(provider.rawValue)."
        case .uploadFailed(let provider, let reason):
            return "\(provider.rawValue) upload failed: \(reason)"
        case .decodingFailed(let provider, let reason):
            return "Failed to decode \(provider.rawValue) response: \(reason)"
        case .providerFailure(let provider, let reason):
            return "\(provider.rawValue) request failed: \(reason)"
        }
    }
}
