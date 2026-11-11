import Foundation

// MARK: - Model ID

/// ElevenLabs model identifiers supported by SpeechKit.
public enum ElevenLabsModelID: String, Sendable, CaseIterable {
    /// ElevenLabs Scribe v2 realtime transcription.
    case scribeV2Realtime = "scribe_v2_realtime"
    /// ElevenLabs Scribe v3 realtime transcription, with turn prediction and diarization.
    case scribeV3Live = "scribe_v3_live"
    /// ElevenLabs Scribe v1 file transcription.
    ///
    /// ElevenLabs scheduled this model for removal on July 9, 2026.
    @available(*, deprecated, message: "ElevenLabs scheduled scribe_v1 for removal on July 9, 2026. Use scribeV3.")
    case scribeV1 = "scribe_v1"
    /// ElevenLabs Scribe v2 file transcription.
    case scribeV2 = "scribe_v2"
    /// ElevenLabs Scribe v3 file transcription.
    case scribeV3 = "scribe_v3"
    /// ElevenLabs Scribe v2 file transcription tuned for medical audio.
    case scribeV2Medical = "scribe_v2_medical"
}

extension ElevenLabsModelID {
    // Synthesized conformance is unavailable once cases are deprecated. Raw values
    // keep the list free of deprecation warnings.
    public static let allCases: [Self] = [
        "scribe_v2_realtime",
        "scribe_v3_live",
        "scribe_v1",
        "scribe_v2",
        "scribe_v3",
        "scribe_v2_medical",
    ].compactMap(Self.init(rawValue:))

    /// A Boolean value that indicates whether the model transcribes uploaded files.
    var supportsFileTranscription: Bool {
        // Raw values keep the deprecated scribe_v1 case free of warnings.
        switch rawValue {
        case "scribe_v1", "scribe_v2", "scribe_v3", "scribe_v2_medical":
            return true
        default:
            return false
        }
    }

    /// A Boolean value that indicates whether the model transcribes realtime audio.
    var supportsRealtime: Bool {
        switch rawValue {
        case "scribe_v2_realtime", "scribe_v3_live":
            return true
        default:
            return false
        }
    }

    /// A Boolean value that indicates whether the model belongs to the Scribe v3 family.
    var isScribeV3: Bool {
        self == .scribeV3 || self == .scribeV3Live
    }
}

// MARK: - Outgoing Messages

struct InputAudioChunk: Encodable, Sendable {
    let message_type = "input_audio_chunk"
    let audio_base_64: String
    let commit: Bool
    let sample_rate: Int
    /// Transcript context, sent in the first chunk of a session only.
    let previous_text: String?
    /// The session's keyterm library, sent in the first chunk of a session only.
    let keyterm_library: [String]?

    init(audioData: Data, commit: Bool = false, sampleRate: Int = 16000, previousText: String? = nil, keytermLibrary: [String]? = nil) {
        self.audio_base_64 = audioData.base64EncodedString()
        self.commit = commit
        self.sample_rate = sampleRate
        self.previous_text = previousText
        self.keyterm_library = keytermLibrary
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
    case diarizedTranscript(DiarizedTranscript)
    case speakersMerged(SpeakersMerged)
    case committedTranscriptEntities(CommittedTranscriptEntities)
    case warning(ElevenLabsServerNotice)
    case serverError(ElevenLabsServerError)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
    }

    /// The realtime message types that carry a session failure rather than transcript data.
    static let serverErrorTypes: Set<String> = [
        "error", "auth_error", "quota_exceeded", "commit_throttled", "rate_limited",
        "queue_overflow", "resource_exhausted", "session_time_limit_exceeded",
        "input_error", "invalid_request", "chunk_size_exceeded",
        "insufficient_audio_activity", "transcriber_error",
    ]

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
        case "diarized_transcript":
            self = .diarizedTranscript(try singleValueContainer.decode(DiarizedTranscript.self))
        case "speakers_merged":
            self = .speakersMerged(try singleValueContainer.decode(SpeakersMerged.self))
        case "committed_transcript_entities":
            self = .committedTranscriptEntities(try singleValueContainer.decode(CommittedTranscriptEntities.self))
        case "warning":
            self = .warning(try singleValueContainer.decode(ElevenLabsServerNotice.self))
        default:
            if Self.serverErrorTypes.contains(messageType) {
                self = .serverError(try singleValueContainer.decode(ElevenLabsServerError.self))
            } else {
                self = .unknown(messageType)
            }
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
    // Every field is optional: newer servers may rename fields, and a missing
    // one must not fail `session_started`.
    let sampleRate: Int?
    let audioFormat: String?
    let languageCode: String?
    let modelID: String?
    let commitStrategy: String?
    let vadCommitStrategy: Bool?
    let vadSilenceThresholdSecs: Double?
    let vadThreshold: Double?
    let includeTimestamps: Bool?

    private enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case audioFormat = "audio_format"
        case languageCode = "language_code"
        case modelID = "model_id"
        case commitStrategy = "commit_strategy"
        case vadCommitStrategy = "vad_commit_strategy"
        case vadSilenceThresholdSecs = "vad_silence_threshold_secs"
        case vadThreshold = "vad_threshold"
        case includeTimestamps = "include_timestamps"
    }
}

struct PartialTranscript: Decodable, Sendable {
    let text: String
    let segmentIndex: Int?
    let turnProbability: Double?
    /// Provisional diarized words, present only in a Scribe v3 Live session with `diarize` on.
    let words: [ElevenLabsWordTimestamp]?

    private enum CodingKeys: String, CodingKey {
        case text
        case segmentIndex = "segment_index"
        case turnProbability = "turn_probability"
        case words
    }
}

struct CommittedTranscript: Decodable, Sendable {
    let text: String
    let segmentIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case text
        case segmentIndex = "segment_index"
    }
}

struct CommittedTranscriptWithTimestamps: Decodable, Sendable {
    let text: String
    let languageCode: String?
    let words: [ElevenLabsWordTimestamp]?
    let segmentIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case words
        case segmentIndex = "segment_index"
    }
}

/// The resolved diarization for a committed segment.
///
/// Arrives after each `committed_transcript`, matched by `segment_index`. It is
/// always sent in a diarized session, even when every speaker stays `null`.
struct DiarizedTranscript: Decodable, Sendable {
    let segmentIndex: Int
    let text: String
    let words: [ElevenLabsWordTimestamp]

    private enum CodingKeys: String, CodingKey {
        case segmentIndex = "segment_index"
        case text
        case words
    }
}

/// An instruction to rewrite every earlier `from` label as `to`, in stored and partial words.
///
/// Merges chain, so SpeechKit applies them in the order received.
struct SpeakersMerged: Decodable, Sendable {
    let fromSpeakerID: String
    let toSpeakerID: String

    private enum CodingKeys: String, CodingKey {
        case fromSpeakerID = "from_speaker_id"
        case toSpeakerID = "to_speaker_id"
    }
}

/// Entity detections attached to a committed realtime transcript.
struct CommittedTranscriptEntities: Decodable, Sendable {
    let segmentIndex: Int?
    let entities: [ElevenLabsEntity]

    private enum CodingKeys: String, CodingKey {
        case segmentIndex = "segment_index"
        case entities
    }
}

/// A non-fatal server notice, logged rather than surfaced.
struct ElevenLabsServerNotice: Decodable, Sendable {
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .error)
    }
}

/// A session-ending server error.
///
/// The vendor's free-text `error` field stays inside this value for logging;
/// it never reaches ``lastError`` or ``ElevenLabsError`` descriptions.
struct ElevenLabsServerError: Decodable, Sendable {
    /// The machine-readable error type, such as `quota_exceeded`.
    let type: String
    /// The vendor's error text. Kept for logs only, never surfaced.
    let reason: String?

    private enum CodingKeys: String, CodingKey {
        case type = "message_type"
        case reason = "error"
    }
}

/// A word-level timestamp returned by ElevenLabs transcription.
public struct ElevenLabsWordTimestamp: Decodable, Sendable, Equatable {
    /// The word or token text.
    public let text: String
    /// The start time, in seconds. Audio events and unaligned partial words can omit it.
    public let start: Double?
    /// The end time, in seconds. Audio events and unaligned partial words can omit it.
    public let end: Double?
    /// The timestamp token type reported by ElevenLabs: `word`, `spacing` or `audio_event`.
    public let type: String
    /// The optional token log probability.
    public let logprob: Double?
    /// The speaker label, such as `speaker_0`, when the request used diarization.
    public let speakerID: String?
    /// Optional character-level data reported by ElevenLabs.
    public let characters: [String]?

    /// Creates a word timestamp.
    public init(
        text: String,
        start: Double? = nil,
        end: Double? = nil,
        type: String = "word",
        logprob: Double? = nil,
        speakerID: String? = nil,
        characters: [String]? = nil
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.type = type
        self.logprob = logprob
        self.speakerID = speakerID
        self.characters = characters
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case start
        case end
        case type
        case logprob
        case speakerID = "speaker_id"
        case characters
    }
}

/// A detected entity span returned by ElevenLabs transcription.
public struct ElevenLabsEntity: Decodable, Sendable, Equatable {
    /// The detected text.
    public let text: String
    /// The entity type, such as `name` or a category such as `pii`.
    public let entityType: String
    /// The first character index of the span in the transcript text.
    public let startChar: Int
    /// The character index just past the span in the transcript text.
    public let endChar: Int

    /// Creates an entity.
    public init(text: String, entityType: String, startChar: Int, endChar: Int) {
        self.text = text
        self.entityType = entityType
        self.startChar = startChar
        self.endChar = endChar
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case entityType = "entity_type"
        case startChar = "start_char"
        case endChar = "end_char"
    }
}

extension SpeechTranscriptWord {
    init(_ word: ElevenLabsWordTimestamp) {
        self.init(
            text: word.text,
            start: word.start,
            end: word.end,
            speaker: word.speakerID,
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
    case connectionFailed(SpeechFailureReason)
    /// SpeechKit could not encode an outgoing realtime message.
    case encodingFailed
    /// SpeechKit could not decode an incoming realtime or file response.
    case decodingFailed(SpeechFailureReason)
    /// The realtime WebSocket disconnected.
    case disconnected
    /// The user denied microphone permission.
    case permissionDenied
    /// The audio engine failed.
    case audioEngineError(SpeechFailureReason)
    /// The ElevenLabs API key is empty.
    case apiKeyMissing
    /// SpeechKit could not read the audio file.
    case fileReadFailed
    /// ElevenLabs rejected or failed a file upload.
    case uploadFailed(SpeechFailureReason)
    /// The selected model is not supported for the requested operation.
    case unsupportedModel(SpeechFailureReason)
    /// SpeechKit could not access a security-scoped file URL.
    case securityScopeDenied
    /// The file exceeds ElevenLabs upload limits.
    case fileTooLarge(Int64)
    /// The audio duration exceeds ElevenLabs upload limits.
    case audioTooLong(TimeInterval)
    /// SpeechKit could not read audio metadata.
    ///
    /// Upload validation no longer throws this case: a file whose duration
    /// AVFoundation cannot read skips the duration check instead.
    case metadataReadFailed
    /// ElevenLabs reported a session-ending realtime error.
    ///
    /// `type` is the bounded machine-readable error type, such as
    /// `quota_exceeded` or `invalid_request`. The vendor's free-text error
    /// message is never included.
    case serverError(type: String)

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
            return "Audio file exceeds 5 GB limit"
        case .audioTooLong:
            return "Audio duration exceeds 15 hours limit"
        case .metadataReadFailed:
            return "Failed to read audio metadata"
        case .serverError(let type):
            return "ElevenLabs realtime session failed (\(type))"
        }
    }
}
