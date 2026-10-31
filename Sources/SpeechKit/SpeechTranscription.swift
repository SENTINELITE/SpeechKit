import Foundation

/// A transcription-only capability. Keep the owning `SpeechService` at the composition root.
/// Reads participate in the service's observation, without exposing configuration or credentials.
@MainActor
public struct SpeechTranscription: SpeechRedactedDiagnostics {
    private let service: SpeechService

    init(service: SpeechService) { self.service = service }

    public var connectionState: SpeechRealtimeConnectionState { service.connectionState }
    public var transcriptText: String { service.transcriptText }
    public var partialTranscriptText: String { service.partialTranscriptText }
    public var transcriptEntries: [SpeechTranscriptEntry] { service.transcriptEntries }
    public var lastError: Error? { service.lastError }

    public func startListening() async { await service.startListening() }
    public func startListening(provider: SpeechRealtimeProvider) async { await service.startListening(provider: provider) }
    public func stopListening() async { await service.stopListening() }

    public func transcribeAudioFile(provider: SpeechFileTranscriptionProvider, file: URL,
                                    options: SpeechFileTranscriptionOptions? = nil) async throws -> String {
        try await service.transcribeAudioFile(provider: provider, file: file, options: options)
    }

    public func transcribeAudioFile(provider: SpeechFileTranscriptionProvider, securityScopedURL: URL,
                                    options: SpeechFileTranscriptionOptions? = nil) async throws -> String {
        try await service.transcribeAudioFile(provider: provider, securityScopedURL: securityScopedURL, options: options)
    }
}

extension SpeechService {
    /// Pass this capability to views that should not manage credentials or configuration.
    public var transcriber: SpeechTranscription { SpeechTranscription(service: self) }
}
