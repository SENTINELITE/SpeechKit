import Foundation

// MARK: - Model ID

public enum ElevenLabsModelID: String, Sendable, CaseIterable {
    case scribeV2Realtime = "scribe_v2_realtime"
    case scribeV1 = "scribe_v1"
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
    let sessionId: String
    let config: SessionConfig
    
    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case config
    }
}

struct SessionConfig: Decodable, Sendable {
    let sampleRate: Int
    let audioFormat: String
    let languageCode: String?
    let modelId: String
    let vadCommitStrategy: Bool
    let vadSilenceThresholdSecs: Double
    let vadThreshold: Double
    let includeTimestamps: Bool
    
    private enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case audioFormat = "audio_format"
        case languageCode = "language_code"
        case modelId = "model_id"
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
    let words: [WordTimestamp]?
    
    private enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case words
    }
}

public struct WordTimestamp: Decodable, Sendable {
    public let text: String
    public let start: Double
    public let end: Double
    public let type: String
    public let logprob: Double?
    public let characters: [String]?
}

// MARK: - Errors

public enum ElevenLabsError: Error, LocalizedError, Sendable {
    case invalidURL
    case connectionFailed(String)
    case encodingFailed
    case decodingFailed(String)
    case disconnected
    case permissionDenied
    case audioEngineError(String)
    case apiKeyMissing
    case fileReadFailed
    case uploadFailed(String)
    case unsupportedModel(String)
    case securityScopeDenied
    
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
        case .unsupportedModel(let modelId):
            return "Unsupported model for upload: \(modelId)"
        case .securityScopeDenied:
            return "Failed to access security-scoped resource"
        }
    }
}
