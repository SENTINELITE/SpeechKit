import Foundation

// MARK: - Model ID

/// ElevenLabs model identifiers supported by SpeechKit.
public enum ElevenLabsModelID: String, Sendable, CaseIterable {
    /// ElevenLabs Scribe v2 realtime transcription.
    case scribeV2Realtime = "scribe_v2_realtime"
    /// ElevenLabs Scribe v1 file transcription.
    case scribeV1 = "scribe_v1"
    /// ElevenLabs Scribe v2 file transcription.
    case scribeV2 = "scribe_v2"
}

// MARK: - Outgoing Messages

struct InputAudioChunk: Encodable, Sendable {
    let message_type = "input_audio_chunk"
    let audio_base_64: String
    let commit: Bool
    let sample_rate: Int
    
    init(audioData: Data, commit: Bool = false, sampleRate: Int = 16000) {
        self.audio_base_64 = audioData.base64EncodedString()
        self.commit = commit
        self.sample_rate = sampleRate
    }
}

struct EndOfStreamMessage: Encodable, Sendable {
    let message_type = "end_of_stream"
}

// MARK: - Incoming Messages

enum ElevenLabsMessage: Decodable, Sendable {
    case sessionStarted(SessionStarted)
    case partialTranscript(PartialTranscript)
    case committedTranscript(CommittedTranscript)
    case committedTranscriptWithTimestamps(CommittedTranscriptWithTimestamps)
    case unknown(String)
    
    private enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let messageType = try container.decode(String.self, forKey: .messageType)
        
        let singleValueContainer = try decoder.singleValueContainer()
        
        switch messageType {
        case "session_started":
            self = .sessionStarted(try singleValueContainer.decode(SessionStarted.self))
        case "partial_transcript":
            self = .partialTranscript(try singleValueContainer.decode(PartialTranscript.self))
        case "committed_transcript":
            self = .committedTranscript(try singleValueContainer.decode(CommittedTranscript.self))
        case "committed_transcript_with_timestamps":
            self = .committedTranscriptWithTimestamps(try singleValueContainer.decode(CommittedTranscriptWithTimestamps.self))
        default:
            self = .unknown(messageType)
        }
    }
}

struct SessionStarted: Decodable, Sendable {
    let sessionID: String
    let config: SessionConfig
    
    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case config
    }
}

struct SessionConfig: Decodable, Sendable {
    let sampleRate: Int
    let audioFormat: String
    let languageCode: String?
    let modelID: String
    let vadCommitStrategy: Bool
    let vadSilenceThresholdSecs: Double
    let vadThreshold: Double
    let includeTimestamps: Bool
    
    private enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case audioFormat = "audio_format"
        case languageCode = "language_code"
        case modelID = "model_id"
        case vadCommitStrategy = "vad_commit_strategy"
        case vadSilenceThresholdSecs = "vad_silence_threshold_secs"
        case vadThreshold = "vad_threshold"
        case includeTimestamps = "include_timestamps"
    }
}

struct PartialTranscript: Decodable, Sendable {
    let text: String
}

struct CommittedTranscript: Decodable, Sendable {
    let text: String
}

struct CommittedTranscriptWithTimestamps: Decodable, Sendable {
    let text: String
    let languageCode: String?
    let words: [ElevenLabsWordTimestamp]?
    
    private enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case words
    }
}

/// A word-level timestamp returned by ElevenLabs transcription.
public struct ElevenLabsWordTimestamp: Decodable, Sendable {
    /// The word or token text.
    public let text: String
    /// The start time, in seconds.
    public let start: Double
    /// The end time, in seconds.
    public let end: Double
    /// The timestamp token type reported by ElevenLabs.
    public let type: String
    /// The optional token log probability.
    public let logprob: Double?
    /// Optional character-level data reported by ElevenLabs.
    public let characters: [String]?
}

extension SpeechTranscriptWord {
    init(_ word: ElevenLabsWordTimestamp) {
        self.init(
            text: word.text,
            start: word.start,
            end: word.end,
            confidence: word.logprob
        )
    }
}

// MARK: - Errors

/// Errors returned by ElevenLabs-specific realtime and upload APIs.
public enum ElevenLabsError: Error, LocalizedError, Sendable {
    /// SpeechKit could not construct a valid ElevenLabs URL.
    case invalidURL
    /// The realtime connection failed.
    case connectionFailed(String)
    /// SpeechKit could not encode an outgoing realtime message.
    case encodingFailed
    /// SpeechKit could not decode an incoming realtime or file response.
    case decodingFailed(String)
    /// The realtime WebSocket disconnected.
    case disconnected
    /// The user denied microphone permission.
    case permissionDenied
    /// The audio engine failed.
    case audioEngineError(String)
    /// The ElevenLabs API key is empty.
    case apiKeyMissing
    /// SpeechKit could not read the audio file.
    case fileReadFailed
    /// ElevenLabs rejected or failed a file upload.
    case uploadFailed(String)
    /// The selected model is not supported for the requested operation.
    case unsupportedModel(String)
    /// SpeechKit could not access a security-scoped file URL.
    case securityScopeDenied
    /// The file exceeds ElevenLabs upload limits.
    case fileTooLarge(Int64)
    /// The audio duration exceeds ElevenLabs upload limits.
    case audioTooLong(TimeInterval)
    /// SpeechKit could not read audio metadata.
    case metadataReadFailed
    
    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .encodingFailed:
            return "Failed to encode message"
        case .decodingFailed(let reason):
            return "Failed to decode message: \(reason)"
        case .disconnected:
            return "WebSocket disconnected"
        case .permissionDenied:
            return "Microphone permission denied"
        case .audioEngineError(let reason):
            return "Audio engine error: \(reason)"
        case .apiKeyMissing:
            return "API key not configured"
        case .fileReadFailed:
            return "Failed to read audio file"
        case .uploadFailed(let reason):
            return "File upload failed: \(reason)"
        case .unsupportedModel(let modelID):
            return "Unsupported model for upload: \(modelID)"
        case .securityScopeDenied:
            return "Failed to access security-scoped resource"
        case .fileTooLarge:
            return "Audio file exceeds 3 GB limit"
        case .audioTooLong:
            return "Audio duration exceeds 10 hours limit"
        case .metadataReadFailed:
            return "Failed to read audio metadata"
        }
    }
}
