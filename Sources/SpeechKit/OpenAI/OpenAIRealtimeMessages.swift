import Foundation

/// OpenAI Realtime transcription latency tuning.
public enum OpenAIRealtimeDelay: Sendable, Equatable {
    /// Let OpenAI choose the delay.
    case auto
    /// Use a fixed delay in milliseconds.
    case milliseconds(Int)
}

/// Options for an OpenAI Realtime transcription session.
///
/// SpeechKit uses these values to create and update an OpenAI transcription session before streaming microphone audio.
public struct OpenAIRealtimeSessionOptions: Sendable, Equatable {
    /// The OpenAI Realtime model used to host the session.
    public var sessionModelID: OpenAIRealtimeSessionModelID
    /// The OpenAI realtime transcription model.
    public var transcriptionModelID: OpenAIRealtimeTranscriptionModelID
    /// An optional ISO-639-1 language hint.
    public var language: String?
    /// The transcription delay behavior.
    public var delay: OpenAIRealtimeDelay
    /// The interval between audio buffer commits, in seconds.
    public var commitInterval: TimeInterval

    /// Creates OpenAI realtime session options.
    public init(
        sessionModelID: OpenAIRealtimeSessionModelID = .gptRealtime,
        transcriptionModelID: OpenAIRealtimeTranscriptionModelID = .gpt4oTranscribe,
        language: String? = nil,
        delay: OpenAIRealtimeDelay = .auto,
        commitInterval: TimeInterval = 1
    ) {
        self.sessionModelID = sessionModelID
        self.transcriptionModelID = transcriptionModelID
        self.language = language
        self.delay = delay
        self.commitInterval = commitInterval
    }
}

struct OpenAIRealtimeSessionUpdateMessage: Encodable, Sendable {
    let type = "session.update"
    let session: Session

    struct Session: Encodable, Sendable {
        let type = "transcription"
        let audio: Audio
    }

    struct Audio: Encodable, Sendable {
        let input: Input
    }

    struct Input: Encodable, Sendable {
        let format: AudioFormat
        let transcription: Transcription
    }

    struct AudioFormat: Encodable, Sendable {
        let type = "audio/pcm"
        let rate = 24000
    }

    struct Transcription: Encodable, Sendable {
        let model: String
        let language: String?
        let delay: Delay?
    }

    struct Delay: Encodable, Sendable {
        let type: String
        let ms: Int?

        private enum CodingKeys: String, CodingKey {
            case type
            case ms = "milliseconds"
        }
    }

    init(options: OpenAIRealtimeSessionOptions) {
        let delay: Delay?
        switch options.delay {
        case .auto:
            delay = Delay(type: "auto", ms: nil)
        case .milliseconds(let milliseconds):
            delay = Delay(type: "fixed", ms: milliseconds)
        }

        self.session = Session(
            audio: Audio(
                input: Input(
                    format: AudioFormat(),
                    transcription: Transcription(
                        model: options.transcriptionModelID.rawValue,
                        language: options.language,
                        delay: delay
                    )
                )
            )
        )
    }
}

struct OpenAIInputAudioBufferAppendMessage: Encodable, Sendable {
    let type = "input_audio_buffer.append"
    let audio: String

    init(audioData: Data) {
        self.audio = audioData.base64EncodedString()
    }
}

struct OpenAIInputAudioBufferCommitMessage: Encodable, Sendable {
    let type = "input_audio_buffer.commit"
}

enum OpenAIRealtimeMessage: Decodable, Sendable {
    case sessionCreated(String?)
    case sessionUpdated(String?)
    case transcriptionDelta(TranscriptionDelta)
    case transcriptionCompleted(TranscriptionCompleted)
    case error(String)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case session
        case error
    }

    private enum SessionCodingKeys: String, CodingKey {
        case id
    }

    private enum ErrorCodingKeys: String, CodingKey {
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let singleValueContainer = try decoder.singleValueContainer()

        switch type {
        case "session.created":
            self = .sessionCreated(Self.decodeSessionID(from: container))
        case "session.updated":
            self = .sessionUpdated(Self.decodeSessionID(from: container))
        case "conversation.item.input_audio_transcription.delta":
            self = .transcriptionDelta(try singleValueContainer.decode(TranscriptionDelta.self))
        case "conversation.item.input_audio_transcription.completed":
            self = .transcriptionCompleted(try singleValueContainer.decode(TranscriptionCompleted.self))
        case "error":
            let message = Self.decodeErrorMessage(from: container) ?? "OpenAI realtime error."
            self = .error(message)
        default:
            self = .unknown(type)
        }
    }

    private static func decodeSessionID(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
        guard let session = try? container.nestedContainer(keyedBy: SessionCodingKeys.self, forKey: .session) else {
            return nil
        }
        return try? session.decode(String.self, forKey: .id)
    }

    private static func decodeErrorMessage(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
        guard let error = try? container.nestedContainer(keyedBy: ErrorCodingKeys.self, forKey: .error) else {
            return nil
        }
        return try? error.decode(String.self, forKey: .message)
    }
}

struct TranscriptionDelta: Decodable, Sendable {
    let itemID: String?
    let delta: String

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case delta
    }
}

struct TranscriptionCompleted: Decodable, Sendable {
    let itemID: String?
    let transcript: String

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case transcript
    }
}

/// Errors returned by OpenAI-specific realtime APIs.
public enum OpenAIError: Error, LocalizedError, Sendable, Equatable {
    /// SpeechKit could not construct a valid OpenAI URL.
    case invalidURL
    /// The realtime connection failed.
    case connectionFailed(String)
    /// SpeechKit could not encode an outgoing realtime message.
    case encodingFailed
    /// The realtime WebSocket disconnected.
    case disconnected
    /// The user denied microphone permission.
    case permissionDenied
    /// The OpenAI API key is empty.
    case apiKeyMissing

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OpenAI URL"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .encodingFailed:
            return "Failed to encode message"
        case .disconnected:
            return "WebSocket disconnected"
        case .permissionDenied:
            return "Microphone permission denied"
        case .apiKeyMissing:
            return "API key not configured"
        }
    }
}
