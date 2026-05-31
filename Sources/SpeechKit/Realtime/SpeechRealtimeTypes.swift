import Foundation

/// A provider that can transcribe realtime microphone audio.
public enum SpeechRealtimeProvider: String, Sendable, CaseIterable {
    /// ElevenLabs realtime transcription.
    case elevenLabs
    /// OpenAI realtime transcription.
    case openAI
    /// xAI Grok realtime transcription.
    case grok
}

/// The realtime connection lifecycle state.
public enum SpeechRealtimeConnectionState: Equatable, Sendable {
    /// The service is disconnected.
    case disconnected
    /// The service is opening a realtime connection.
    case connecting
    /// The service is connected to a realtime session but not yet sending audio.
    case connected(sessionID: String)
    /// The service is connected and streaming microphone audio.
    case listening
    /// The service is closing a realtime connection.
    case stopping
    /// The service is stopped because of an error.
    case error(String)

    /// A Boolean value that indicates whether the service has an active realtime session.
    public var isActive: Bool {
        switch self {
        case .connected, .listening:
            return true
        default:
            return false
        }
    }

    /// A Boolean value that indicates whether the service is starting, started, or stopping.
    var isLifecycleActive: Bool {
        switch self {
        case .connecting, .connected, .listening, .stopping:
            return true
        case .disconnected, .error:
            return false
        }
    }

    /// A Boolean value that indicates whether the service is streaming microphone audio.
    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

/// A normalized realtime transcript word.
public struct SpeechTranscriptWord: Identifiable, Equatable, Sendable {
    /// The stable identity of the word.
    public let id: UUID
    /// The word or token text.
    public let text: String
    /// The start time, in seconds.
    public let start: Double?
    /// The end time, in seconds.
    public let end: Double?
    /// The optional speaker label or index.
    public let speaker: String?
    /// The optional confidence or log probability value.
    public let confidence: Double?

    /// Creates a normalized realtime transcript word.
    public init(
        id: UUID = UUID(),
        text: String,
        start: Double? = nil,
        end: Double? = nil,
        speaker: String? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
        self.confidence = confidence
    }
}

/// A normalized realtime transcript entry.
public struct SpeechTranscriptEntry: Identifiable, Equatable, Sendable {
    /// The stable identity of the entry.
    public let id: UUID
    /// The provider that produced the entry.
    public let provider: SpeechRealtimeProvider
    /// A provider-specific source identifier, when available.
    public let sourceID: String?
    /// The transcript text.
    public let text: String
    /// The time when SpeechKit created the entry.
    public let timestamp: Date
    /// The entry start time, in seconds, when provided by the provider.
    public let start: Double?
    /// The entry duration, in seconds, when provided by the provider.
    public let duration: Double?
    /// A Boolean value indicating whether this entry is final for its current chunk.
    public let isFinal: Bool
    /// A Boolean value indicating whether this entry ends an utterance or speech segment.
    public let isUtteranceFinal: Bool
    /// The provider channel index, when available.
    public let channelIndex: Int?
    /// The speaker label or index, when available.
    public let speaker: String?
    /// Optional word-level timing data.
    public let words: [SpeechTranscriptWord]

    /// Creates a normalized realtime transcript entry.
    public init(
        id: UUID = UUID(),
        provider: SpeechRealtimeProvider,
        sourceID: String? = nil,
        text: String,
        timestamp: Date = Date(),
        start: Double? = nil,
        duration: Double? = nil,
        isFinal: Bool = true,
        isUtteranceFinal: Bool = true,
        channelIndex: Int? = nil,
        speaker: String? = nil,
        words: [SpeechTranscriptWord] = []
    ) {
        self.id = id
        self.provider = provider
        self.sourceID = sourceID
        self.text = text
        self.timestamp = timestamp
        self.start = start
        self.duration = duration
        self.isFinal = isFinal
        self.isUtteranceFinal = isUtteranceFinal
        self.channelIndex = channelIndex
        self.speaker = speaker
        self.words = words
    }
}

/// Errors returned by shared microphone capture.
public enum SpeechAudioCaptureError: Error, LocalizedError, Sendable, Equatable {
    /// The user denied microphone permission.
    case permissionDenied
    /// The audio engine failed.
    case audioEngineError(String)

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .audioEngineError(let reason):
            return "Audio engine error: \(reason)"
        }
    }
}
