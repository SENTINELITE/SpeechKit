import Foundation

/// Mistral Voxtral realtime transcription model identifiers supported by SpeechKit.
public enum MistralRealtimeModelID: String, Sendable, CaseIterable {
    /// Voxtral Mini Transcribe Realtime 3.
    case voxtralMiniTranscribeRealtime2602 = "voxtral-mini-transcribe-realtime-2602"
    case voxtralMiniTranscribeRealtime3 = "voxtral-mini-transcribe-realtime-3"
}

/// End-of-turn detection settings for a Mistral realtime session.
///
/// Leave a value `nil` to keep Mistral's default for it.
public struct MistralTurnDetection: Sendable, Equatable {
    /// The score above which the user has started or resumed speaking. Mistral's default is `0.5`.
    public var startThreshold: Double?
    /// The score below which the user may have stopped speaking. Mistral's default is `0.5`.
    public var eagerEndThreshold: Double?
    /// The score below which the user has stopped speaking. Mistral's default is `0.33`.
    public var endThreshold: Double?
    /// The minimum pause before a turn can end, in milliseconds. Mistral's default is `500`.
    public var minSilenceMilliseconds: Int?
    /// The maximum pause before a turn ends anyway, in milliseconds. Mistral's default is `3000`.
    public var endTimeoutMilliseconds: Int?

    /// Creates turn detection settings.
    public init(
        startThreshold: Double? = nil,
        eagerEndThreshold: Double? = nil,
        endThreshold: Double? = nil,
        minSilenceMilliseconds: Int? = nil,
        endTimeoutMilliseconds: Int? = nil
    ) {
        self.startThreshold = startThreshold
        self.eagerEndThreshold = eagerEndThreshold
        self.endThreshold = endThreshold
        self.minSilenceMilliseconds = minSilenceMilliseconds
        self.endTimeoutMilliseconds = endTimeoutMilliseconds
    }
}

/// A short recording of a known speaker, used to name that speaker in a diarized realtime session.
public struct MistralSpeakerReference: Sendable, Equatable {
    /// The name Mistral reports as the speaker label for this voice.
    public var name: String
    /// A 3 to 15 second WAV, Opus, MP3, or FLAC clip of the speaker. WAV gives the best results.
    public var audio: Data

    /// Creates a speaker reference.
    public init(name: String, audio: Data) {
        self.name = name
        self.audio = audio
    }
}

/// Options for a Mistral realtime transcription session.
///
/// SpeechKit sends these values in the `session.update` message that
/// configures a Mistral realtime session before the first audio chunk. Mistral
/// locks the settings once audio starts, so changes apply to the next session.
public struct MistralRealtimeOptions: Sendable, Equatable {
    /// The Voxtral realtime model to use.
    public var modelID: MistralRealtimeModelID
    /// The microphone capture sample rate, in hertz.
    ///
    /// SpeechKit streams 16-bit signed little-endian mono PCM at this rate.
    public var sampleRate: Int
    /// How long the model waits for context before writing a word, in milliseconds.
    ///
    /// Shorter delays deliver text sooner and less accurately. Mistral accepts
    /// any value from 80 to 1200, or 2400, and recommends 480 as a starting
    /// point. Leave it `nil` to use Mistral's default.
    public var targetStreamingDelayMilliseconds: Int?
    /// A two-letter ISO 639-1 language code such as `"en"`, or `nil` to let Mistral detect the language.
    public var language: String?
    /// Names and terms that bias transcription toward the right spelling.
    public var contextBias: [String]
    /// A Boolean value that indicates whether Mistral should label each piece of text with its speaker.
    ///
    /// Mistral cannot combine diarization with turn detection. When this is
    /// `true`, SpeechKit leaves ``turnDetection`` out of the session and starts
    /// a new transcript entry each time the speaker changes.
    public var diarize: Bool
    /// Known speakers to name in a diarized session, up to 8 clips.
    ///
    /// Requires ``diarize``.
    public var speakerReferences: [MistralSpeakerReference]
    /// End-of-turn detection settings, or `nil` to turn detection off.
    ///
    /// SpeechKit commits a transcript entry for each detected turn. Without
    /// turn detection or diarization, the whole session stays one partial
    /// entry until it ends. Ignored when ``diarize`` is `true`.
    public var turnDetection: MistralTurnDetection?

    /// Creates Mistral realtime session options.
    public init(
        modelID: MistralRealtimeModelID = .voxtralMiniTranscribeRealtime3,
        sampleRate: Int = 16000,
        targetStreamingDelayMilliseconds: Int? = nil,
        language: String? = nil,
        contextBias: [String] = [],
        diarize: Bool = false,
        speakerReferences: [MistralSpeakerReference] = [],
        turnDetection: MistralTurnDetection? = MistralTurnDetection()
    ) {
        self.modelID = modelID
        self.sampleRate = sampleRate
        self.targetStreamingDelayMilliseconds = targetStreamingDelayMilliseconds
        self.language = language
        self.contextBias = contextBias
        self.diarize = diarize
        self.speakerReferences = speakerReferences
        self.turnDetection = turnDetection
    }

    /// The turn detection settings SpeechKit sends, which are dropped when diarization is on.
    var effectiveTurnDetection: MistralTurnDetection? {
        diarize ? nil : turnDetection
    }

    func validate() throws {
        if !(8000...48000).contains(sampleRate) {
            throw SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)
        }

        if let delay = targetStreamingDelayMilliseconds, !((80...1200).contains(delay) || delay == 2400) {
            throw SpeechError.providerFailure(
                provider: .mistral,
                reason: .requestFailed)
        }

        try MistralValidation.validateLanguage(language)
        try MistralValidation.validateContextBias(contextBias)

        if !speakerReferences.isEmpty, !diarize {
            throw SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)
        }
        if speakerReferences.count > 8 {
            throw SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)
        }
        if speakerReferences.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)
        }
        if Set(speakerReferences.map(\.name)).count != speakerReferences.count {
            throw SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)
        }
        if speakerReferences.contains(where: { $0.audio.isEmpty }) {
            throw SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)
        }
    }

    func sessionUpdateMessage() -> MistralSessionUpdateMessage {
        MistralSessionUpdateMessage(options: self)
    }
}

struct MistralSessionUpdateMessage: Encodable, Sendable {
    struct Session: Encodable, Sendable {
        let audioFormat: AudioFormat
        let targetStreamingDelayMs: Int?
        let language: String?
        let contextBias: [String]
        let diarize: Bool
        let speakerReferences: [String: String]
        let turnDetection: TurnDetection?

        private enum CodingKeys: String, CodingKey {
            case audioFormat = "audio_format"
            case targetStreamingDelayMs = "target_streaming_delay_ms"
            case language
            case contextBias = "context_bias"
            case diarize
            case speakerReferences = "speaker_references"
            case turnDetection = "turn_detection"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(audioFormat, forKey: .audioFormat)
            try container.encodeIfPresent(targetStreamingDelayMs, forKey: .targetStreamingDelayMs)
            try container.encodeIfPresent(language, forKey: .language)
            if !contextBias.isEmpty {
                try container.encode(contextBias, forKey: .contextBias)
            }
            try container.encode(diarize, forKey: .diarize)
            if !speakerReferences.isEmpty {
                try container.encode(speakerReferences, forKey: .speakerReferences)
            }
            try container.encodeIfPresent(turnDetection, forKey: .turnDetection)
        }
    }

    struct AudioFormat: Encodable, Sendable {
        let encoding = "pcm_s16le"
        let sampleRate: Int

        private enum CodingKeys: String, CodingKey {
            case encoding
            case sampleRate = "sample_rate"
        }
    }

    struct TurnDetection: Encodable, Sendable {
        let startThreshold: Double?
        let eagerEndThreshold: Double?
        let endThreshold: Double?
        let minSilenceMs: Int?
        let endTimeoutMs: Int?

        private enum CodingKeys: String, CodingKey {
            case startThreshold = "start_threshold"
            case eagerEndThreshold = "eager_end_threshold"
            case endThreshold = "end_threshold"
            case minSilenceMs = "min_silence_ms"
            case endTimeoutMs = "end_timeout_ms"
        }
    }

    let type = "session.update"
    let session: Session

    init(options: MistralRealtimeOptions) {
        let turnDetection = options.effectiveTurnDetection.map {
            TurnDetection(
                startThreshold: $0.startThreshold,
                eagerEndThreshold: $0.eagerEndThreshold,
                endThreshold: $0.endThreshold,
                minSilenceMs: $0.minSilenceMilliseconds,
                endTimeoutMs: $0.endTimeoutMilliseconds
            )
        }
        let speakerReferences = Dictionary(
            options.speakerReferences.map { ($0.name, $0.audio.base64EncodedString()) },
            uniquingKeysWith: { first, _ in first }
        )
        self.session = Session(
            audioFormat: AudioFormat(sampleRate: options.sampleRate),
            targetStreamingDelayMs: options.targetStreamingDelayMilliseconds,
            language: options.language,
            contextBias: options.contextBias,
            diarize: options.diarize,
            speakerReferences: options.diarize ? speakerReferences : [:],
            turnDetection: turnDetection
        )
    }
}

struct MistralInputAudioAppendMessage: Encodable, Sendable {
    let type = "input_audio.append"
    let audio: String

    init(audioData: Data) {
        self.audio = audioData.base64EncodedString()
    }
}

struct MistralInputAudioEndMessage: Encodable, Sendable {
    let type = "input_audio.end"
}

enum MistralRealtimeMessage: Decodable, Sendable, Equatable {
    case sessionCreated(requestID: String?)
    case sessionUpdated
    case textDelta(String)
    case segment(text: String, speakerID: String?)
    case turnStart(timeSeconds: Double?)
    case turnEagerEnd(timeSeconds: Double?)
    case turnResume(timeSeconds: Double?)
    case turnEnd(timeSeconds: Double?, endReason: String?)
    case done(text: String)
    case error(String)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case session
        case text
        case speakerID = "speaker_id"
        case timeSeconds = "time_s"
        case endReason = "end_reason"
        case error
    }

    private enum SessionCodingKeys: String, CodingKey {
        case requestID = "request_id"
    }

    private enum ErrorCodingKeys: String, CodingKey {
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "session.created":
            let session = try? container.nestedContainer(keyedBy: SessionCodingKeys.self, forKey: .session)
            self = .sessionCreated(requestID: try session?.decodeIfPresent(String.self, forKey: .requestID))
        case "session.updated":
            self = .sessionUpdated
        case "transcription.text.delta":
            self = .textDelta(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "transcription.segment":
            self = .segment(
                text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
                speakerID: try container.decodeIfPresent(String.self, forKey: .speakerID)
            )
        case "turn.start":
            self = .turnStart(timeSeconds: try container.decodeIfPresent(Double.self, forKey: .timeSeconds))
        case "turn.eager_end":
            self = .turnEagerEnd(timeSeconds: try container.decodeIfPresent(Double.self, forKey: .timeSeconds))
        case "turn.resume":
            self = .turnResume(timeSeconds: try container.decodeIfPresent(Double.self, forKey: .timeSeconds))
        case "turn.end":
            self = .turnEnd(
                timeSeconds: try container.decodeIfPresent(Double.self, forKey: .timeSeconds),
                endReason: try container.decodeIfPresent(String.self, forKey: .endReason)
            )
        case "transcription.done":
            self = .done(text: try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "error":
            let error = try? container.nestedContainer(keyedBy: ErrorCodingKeys.self, forKey: .error)
            let message = try error?.decodeIfPresent(String.self, forKey: .message)
            self = .error(message ?? "Mistral realtime error.")
        default:
            self = .unknown(type)
        }
    }
}

/// Errors returned by Mistral-specific realtime APIs.
public enum MistralRealtimeError: Error, LocalizedError, Sendable, Equatable {
    /// SpeechKit could not construct a valid Mistral realtime URL.
    case invalidURL
    /// The realtime connection failed.
    case connectionFailed(SpeechFailureReason)
    /// SpeechKit could not encode an outgoing realtime message.
    case encodingFailed
    /// The realtime WebSocket disconnected.
    case disconnected
    /// The Mistral API key is empty.
    case apiKeyMissing
    /// Mistral did not confirm the session configuration in time.
    case handshakeTimedOut

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Mistral realtime URL"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .encodingFailed:
            return "Failed to encode message"
        case .disconnected:
            return "WebSocket disconnected"
        case .apiKeyMissing:
            return "API key not configured"
        case .handshakeTimedOut:
            return "Mistral did not confirm the realtime session configuration"
        }
    }
}
