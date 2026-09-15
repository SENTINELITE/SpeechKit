import Foundation

/// OpenAI Realtime transcription latency tuning.
public enum OpenAIRealtimeDelay: Sendable, Equatable {
    /// Let OpenAI choose the delay.
    case auto
    /// Use a fixed delay in milliseconds.
    case milliseconds(Int)
    /// Emit deltas with the least possible latency.
    case minimal
    /// Favor low-latency live captions.
    case low
    /// Balance latency and accuracy.
    case medium
    /// Favor accuracy over immediate partial text.
    case high
    /// Use the most transcription context before emitting text.
    case xhigh
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
    /// Expected input language codes for transcription models that support multiple hints.
    public var languages: [String]
    /// Free-form context about the recording or live audio.
    public var prompt: String?
    /// Literal terms that may appear in the audio.
    public var keywords: [String]
    /// The transcription delay behavior.
    public var delay: OpenAIRealtimeDelay
    /// The interval between audio buffer commits, in seconds.
    public var commitInterval: TimeInterval

    /// Creates OpenAI realtime session options.
    public init(
        sessionModelID: OpenAIRealtimeSessionModelID = .gptRealtime,
        transcriptionModelID: OpenAIRealtimeTranscriptionModelID = .gptLiveTranscribe,
        language: String? = nil,
        languages: [String] = [],
        prompt: String? = nil,
        keywords: [String] = [],
        delay: OpenAIRealtimeDelay = .low,
        commitInterval: TimeInterval = 1
    ) {
        self.sessionModelID = sessionModelID
        self.transcriptionModelID = transcriptionModelID
        self.language = language
        self.languages = languages
        self.prompt = prompt
        self.keywords = keywords
        self.delay = delay
        self.commitInterval = commitInterval
    }
}

extension OpenAIRealtimeSessionOptions {
    func validate() throws {
        if transcriptionModelID.usesLanguageList {
            if language != nil, !languages.isEmpty {
                throw OpenAIError.invalidOptions("Use either language or languages with \(transcriptionModelID.rawValue), not both.")
            }
        } else if !languages.isEmpty {
            throw OpenAIError.invalidOptions("languages is only supported with gpt-live-transcribe and gpt-transcribe.")
        }

        for language in languages where language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OpenAIError.invalidOptions("languages cannot contain empty values.")
        }
        for keyword in keywords {
            if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw OpenAIError.invalidOptions("keywords cannot contain empty values.")
            }
            if keyword.contains("<") || keyword.contains(">") || keyword.contains("\r") || keyword.contains("\n") {
                throw OpenAIError.invalidOptions("keywords cannot contain <, >, carriage returns, or line feeds.")
            }
        }

        switch delay {
        case .auto, .milliseconds:
            break
        case .minimal, .low, .medium, .high, .xhigh:
            guard transcriptionModelID.usesLanguageList else {
                throw OpenAIError.invalidOptions("Named delay tiers require gpt-live-transcribe or gpt-transcribe.")
            }
        }
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
        let turnDetection = Null()

        private enum CodingKeys: String, CodingKey {
            case format
            case transcription
            case turnDetection = "turn_detection"
        }
    }

    struct AudioFormat: Encodable, Sendable {
        let type = "audio/pcm"
        let rate = 24000
    }

    struct Transcription: Encodable, Sendable {
        let model: String
        let language: String?
        let languages: [String]?
        let prompt: String?
        let keywords: [String]?
        let delay: Delay?
    }

    enum Delay: Encodable, Sendable {
        case legacy(type: String, milliseconds: Int?)
        case named(String)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .legacy(let type, let milliseconds):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(type, forKey: .type)
                try container.encodeIfPresent(milliseconds, forKey: .milliseconds)
            case .named(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case milliseconds
        }
    }

    struct Null: Encodable, Sendable {
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    init(options: OpenAIRealtimeSessionOptions) {
        let delay: Delay?
        switch options.delay {
        case .auto:
            delay = .legacy(type: "auto", milliseconds: nil)
        case .milliseconds(let milliseconds):
            delay = .legacy(type: "fixed", milliseconds: milliseconds)
        case .minimal:
            delay = .named("minimal")
        case .low:
            delay = .named("low")
        case .medium:
            delay = .named("medium")
        case .high:
            delay = .named("high")
        case .xhigh:
            delay = .named("xhigh")
        }

        let languages = options.transcriptionModelID.usesLanguageList
            ? (options.languages.isEmpty ? options.language.map { [$0] } : options.languages)
            : nil
        let language = options.transcriptionModelID.usesLanguageList ? nil : options.language
        let supportsContext = options.transcriptionModelID.usesLanguageList

        self.session = Session(
            audio: Audio(
                input: Input(
                    format: AudioFormat(),
                    transcription: Transcription(
                        model: options.transcriptionModelID.rawValue,
                        language: language,
                        languages: languages,
                        prompt: supportsContext ? options.prompt : nil,
                        keywords: supportsContext && !options.keywords.isEmpty ? options.keywords : nil,
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
    let byteCount: Int

    init(audioData: Data) {
        self.audio = audioData.base64EncodedString()
        self.byteCount = audioData.count
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case audio
    }
}

struct OpenAIInputAudioBufferCommitMessage: Encodable, Sendable {
    let type = "input_audio_buffer.commit"
}

/// Tracks whether the Realtime input buffer contains OpenAI's minimum 100 ms of 24 kHz PCM audio.
struct OpenAIInputAudioCommitGate: Sendable {
    static let minimumAudioBytes = 24_000 * MemoryLayout<Int16>.size / 10

    private(set) var pendingAudioBytes = 0

    var isReady: Bool {
        pendingAudioBytes >= Self.minimumAudioBytes
    }

    mutating func append(_ byteCount: Int) {
        pendingAudioBytes += byteCount
    }

    mutating func markCommitted() {
        pendingAudioBytes = 0
    }

    mutating func reset() {
        pendingAudioBytes = 0
    }
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
    let languages: [OpenAITranscriptionLanguage]?

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case transcript
        case languages
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
    /// The supplied OpenAI options are incompatible with the selected model.
    case invalidOptions(String)

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
        case .invalidOptions(let message):
            return message
        }
    }
}
