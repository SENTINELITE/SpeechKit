import Foundation

/// Partial transcript delivery modes supported by Meta realtime transcription.
public enum MetaPartialMode: String, Sendable, CaseIterable {
    /// Each partial event carries the full text of the current turn.
    case cumulative = "CUMULATIVE"
    /// Each partial event carries only the text added since the previous event.
    case delta = "DELTA"
}

/// Options for a Meta realtime transcription session.
///
/// SpeechKit sends these values in the handshake frame that opens a Meta
/// realtime WebSocket session.
public struct MetaRealtimeOptions: Sendable, Equatable {
    /// The Meta transcription model to use.
    public var modelID: MetaModelID
    /// The transcription mode for the session.
    public var mode: MetaTranscriptionMode
    /// The encoding of the streamed microphone audio.
    ///
    /// Meta realtime sessions only accept raw PCM encodings.
    public var audioEncoding: MetaAudioEncoding
    /// The partial transcript delivery mode.
    public var partialMode: MetaPartialMode
    /// A Boolean value that indicates whether Meta should emit audio progress events.
    public var emitAudioProgress: Bool
    /// Language names that bias transcription.
    public var languageBias: [MetaLanguage]
    /// Literal terms that may appear in realtime audio.
    public var keywords: [String]
    /// An optional client-supplied session identifier.
    public var sessionID: String?

    /// The microphone capture sample rate implied by the audio encoding, in hertz.
    public var sampleRate: Int {
        audioEncoding.sampleRate ?? 24000
    }

    /// Creates Meta realtime session options.
    public init(
        modelID: MetaModelID = .museVoiceTranscribe1,
        mode: MetaTranscriptionMode = .endpointing,
        audioEncoding: MetaAudioEncoding = .pcm24kHz,
        partialMode: MetaPartialMode = .cumulative,
        emitAudioProgress: Bool = false,
        languageBias: [MetaLanguage] = [],
        keywords: [String] = [],
        sessionID: String? = nil
    ) {
        self.modelID = modelID
        self.mode = mode
        self.audioEncoding = audioEncoding
        self.partialMode = partialMode
        self.emitAudioProgress = emitAudioProgress
        self.languageBias = languageBias
        self.keywords = keywords
        self.sessionID = sessionID
    }

    func validate() throws {
        if audioEncoding == .wav {
            throw SpeechError.providerFailure(
                provider: .meta,
                reason: "Realtime transcription requires a raw PCM audio encoding."
            )
        }

        if let keyword = keywords.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw SpeechError.providerFailure(provider: .meta, reason: "keywords cannot be empty: \"\(keyword)\".")
        }

        if keywords.contains(where: { $0.contains(where: \.isNewline) }) {
            throw SpeechError.providerFailure(provider: .meta, reason: "keywords cannot contain newlines.")
        }
    }

    func handshakeMessage(secret: String) -> MetaHandshakeMessage {
        MetaHandshakeMessage(secret: secret, options: self)
    }
}

struct MetaHandshakeMessage: Encodable, Sendable {
    struct Authorization: Encodable, Sendable {
        let accessToken: String
    }

    let authorization: Authorization
    let audioEncoding: String
    let model: String
    let mode: String
    let partialMode: String
    let emitAudioProgress: Bool
    let languageBias: [String]
    let keywords: [String]

    init(secret: String, options: MetaRealtimeOptions) {
        self.authorization = Authorization(accessToken: "Bearer \(secret)")
        self.audioEncoding = options.audioEncoding.rawValue
        self.model = options.modelID.rawValue
        self.mode = options.mode.rawValue
        self.partialMode = options.partialMode.rawValue
        self.emitAudioProgress = options.emitAudioProgress
        self.languageBias = options.languageBias.map(\.rawValue)
        self.keywords = options.keywords
    }
}

struct MetaEndStreamMessage: Encodable, Sendable {
    let type = "endStream"
}

enum MetaRealtimeMessage: Decodable, Sendable {
    case sessionCreated(String?)
    case speechStart(turnID: Int?, audioProcessedMs: Int?)
    case transcript(MetaTranscript)
    case speaker(label: String?, audioProcessedMs: Int?)
    case speechEnd(turnID: Int?, audioProcessedMs: Int?)
    case speechComplete(turnID: Int?, transcript: String, audioProcessedMs: Int?)
    case audioProgress(audioProcessedMs: Int?)
    case error(String)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "sessionId"
        case turnID = "turnId"
        case audioProcessedMs
        case transcript
        case label
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = try container.decodeIfPresent(String.self, forKey: .type) else {
            self = .sessionCreated(try container.decodeIfPresent(String.self, forKey: .sessionID))
            return
        }

        let turnID = try container.decodeIfPresent(Int.self, forKey: .turnID)
        let audioProcessedMs = try container.decodeIfPresent(Int.self, forKey: .audioProcessedMs)

        switch type {
        case "speechStart":
            self = .speechStart(turnID: turnID, audioProcessedMs: audioProcessedMs)
        case "transcript":
            let singleValueContainer = try decoder.singleValueContainer()
            self = .transcript(try singleValueContainer.decode(MetaTranscript.self))
        case "speaker":
            self = .speaker(
                label: try container.decodeIfPresent(String.self, forKey: .label),
                audioProcessedMs: audioProcessedMs
            )
        case "speechEnd":
            self = .speechEnd(turnID: turnID, audioProcessedMs: audioProcessedMs)
        case "speechComplete":
            self = .speechComplete(
                turnID: turnID,
                transcript: try container.decodeIfPresent(String.self, forKey: .transcript) ?? "",
                audioProcessedMs: audioProcessedMs
            )
        case "audioProgress":
            self = .audioProgress(audioProcessedMs: audioProcessedMs)
        case "error":
            self = .error(try container.decodeIfPresent(String.self, forKey: .message) ?? "Meta realtime error.")
        default:
            self = .unknown(type)
        }
    }
}

struct MetaTranscript: Decodable, Sendable, Equatable {
    let transcript: String
    let final: Bool?
    let turnID: Int?
    let audioProcessedMs: Int?

    private enum CodingKeys: String, CodingKey {
        case transcript
        case final
        case turnID = "turnId"
        case audioProcessedMs
    }
}

/// Errors returned by Meta-specific realtime APIs.
public enum MetaRealtimeError: Error, LocalizedError, Sendable, Equatable {
    /// SpeechKit could not construct a valid Meta realtime URL.
    case invalidURL
    /// The realtime connection failed.
    case connectionFailed(String)
    /// SpeechKit could not encode an outgoing realtime message.
    case encodingFailed
    /// The realtime WebSocket disconnected.
    case disconnected
    /// The Meta API key is empty.
    case apiKeyMissing
    /// Meta did not acknowledge the handshake frame in time.
    case handshakeTimedOut

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Meta realtime URL"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .encodingFailed:
            return "Failed to encode message"
        case .disconnected:
            return "WebSocket disconnected"
        case .apiKeyMissing:
            return "API key not configured"
        case .handshakeTimedOut:
            return "Meta did not acknowledge the realtime handshake"
        }
    }
}
