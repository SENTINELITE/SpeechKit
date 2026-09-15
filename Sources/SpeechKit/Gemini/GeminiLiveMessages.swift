import Foundation

/// Options for a Gemini Live realtime transcription session.
///
/// SpeechKit sends these values in the `setup` message that opens a Gemini
/// Live WebSocket session.
public struct GeminiRealtimeOptions: Sendable, Equatable {
    /// The Gemini Live model to use.
    ///
    /// ``SpeechService`` overrides this value with
    /// ``GeminiConfiguration/realtimeModelID`` when it starts a session, so this
    /// property only matters when you drive ``GeminiRealtimeService`` directly.
    public var modelID: GeminiRealtimeModelID
    /// BCP-47 language hints, or an empty array to let Gemini detect the language.
    public var languageCodes: [String]
    /// Literal terms that may appear in realtime audio.
    public var customVocabulary: [String]
    /// The transcription mode for the session.
    public var mode: GeminiTranscriptionMode
    /// A Boolean value that indicates whether Gemini detects speech activity.
    ///
    /// When this is `false`, SpeechKit brackets the capture session with
    /// manual activity events instead.
    public var automaticActivityDetection: Bool

    /// The microphone capture sample rate, in hertz.
    ///
    /// Gemini Live only accepts 16 kHz mono 16-bit little-endian PCM audio, so
    /// this value is fixed.
    public var sampleRate: Int { 16000 }

    /// Creates Gemini Live realtime session options.
    public init(
        modelID: GeminiRealtimeModelID = .transcribeLive35,
        languageCodes: [String] = [],
        customVocabulary: [String] = [],
        mode: GeminiTranscriptionMode = .verbatim,
        automaticActivityDetection: Bool = true
    ) {
        self.modelID = modelID
        self.languageCodes = languageCodes
        self.customVocabulary = customVocabulary
        self.mode = mode
        self.automaticActivityDetection = automaticActivityDetection
    }

    func validate() throws {
        if customVocabulary.count > 1000 {
            throw SpeechError.providerFailure(
                provider: .gemini,
                reason: "customVocabulary cannot contain more than 1000 terms."
            )
        }

        if let term = customVocabulary.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw SpeechError.providerFailure(provider: .gemini, reason: "customVocabulary cannot be empty: \"\(term)\".")
        }
    }

    func setupMessage() -> GeminiSetupMessage {
        GeminiSetupMessage(options: self)
    }
}

struct GeminiSetupMessage: Encodable, Sendable {
    struct Setup: Encodable, Sendable {
        let model: String
        let generationConfig: GenerationConfig
        let inputAudioTranscription: InputAudioTranscription
        let realtimeInputConfig: RealtimeInputConfig
    }

    struct GenerationConfig: Encodable, Sendable {
        let responseModalities: [String]
    }

    struct InputAudioTranscription: Encodable, Sendable {
        let languageCodes: [String]
        let customVocabulary: [String]
        let mode: String
    }

    struct RealtimeInputConfig: Encodable, Sendable {
        let automaticActivityDetection: AutomaticActivityDetection
    }

    struct AutomaticActivityDetection: Encodable, Sendable {
        let disabled: Bool
    }

    let setup: Setup

    init(options: GeminiRealtimeOptions) {
        self.setup = Setup(
            model: "models/\(options.modelID.rawValue)",
            generationConfig: GenerationConfig(responseModalities: ["TEXT"]),
            inputAudioTranscription: InputAudioTranscription(
                languageCodes: options.languageCodes,
                customVocabulary: options.customVocabulary,
                mode: options.mode.rawValue.uppercased()
            ),
            realtimeInputConfig: RealtimeInputConfig(
                automaticActivityDetection: AutomaticActivityDetection(
                    disabled: !options.automaticActivityDetection
                )
            )
        )
    }
}

struct GeminiRealtimeAudioMessage: Encodable, Sendable {
    struct RealtimeInput: Encodable, Sendable {
        let audio: Audio
    }

    struct Audio: Encodable, Sendable {
        let data: String
        let mimeType: String
    }

    let realtimeInput: RealtimeInput

    init(audioData: Data, sampleRate: Int = 16000) {
        self.realtimeInput = RealtimeInput(
            audio: Audio(
                data: audioData.base64EncodedString(),
                mimeType: "audio/pcm;rate=\(sampleRate)"
            )
        )
    }
}

struct GeminiActivityMessage: Encodable, Sendable {
    enum Kind: String, Sendable {
        case activityStart
        case activityEnd
    }

    let kind: Kind

    private enum CodingKeys: String, CodingKey {
        case realtimeInput
    }

    private enum RealtimeInputKeys: String, CodingKey {
        case activityStart
        case activityEnd
    }

    private struct Empty: Encodable, Sendable {}

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var realtimeInput = container.nestedContainer(keyedBy: RealtimeInputKeys.self, forKey: .realtimeInput)
        switch kind {
        case .activityStart:
            try realtimeInput.encode(Empty(), forKey: .activityStart)
        case .activityEnd:
            try realtimeInput.encode(Empty(), forKey: .activityEnd)
        }
    }
}

struct GeminiAudioStreamEndMessage: Encodable, Sendable {
    struct RealtimeInput: Encodable, Sendable {
        let audioStreamEnd: Bool
    }

    let realtimeInput = RealtimeInput(audioStreamEnd: true)
}

enum GeminiLiveMessage: Decodable, Sendable {
    case setupComplete
    case interimTranscription(String)
    case finalTranscription(String)
    case turnComplete
    case goAway(timeLeft: String?)
    case sessionResumptionUpdate(handle: String?, resumable: Bool)
    case usageMetadata
    case error(String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case setupComplete
        case serverContent
        case goAway
        case sessionResumptionUpdate
        case usageMetadata
        case error
    }

    private enum ServerContentKeys: String, CodingKey {
        case interimInputTranscription
        case inputTranscription
        case turnComplete
    }

    private enum TranscriptionKeys: String, CodingKey {
        case text
    }

    private enum GoAwayKeys: String, CodingKey {
        case timeLeft
    }

    private enum SessionResumptionKeys: String, CodingKey {
        case newHandle
        case resumable
    }

    private enum ErrorKeys: String, CodingKey {
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let errorContainer = try? container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error) {
            let message = (try? errorContainer.decodeIfPresent(String.self, forKey: .message)) ?? nil
            self = .error(message ?? "Gemini realtime error.")
            return
        }

        if container.contains(.setupComplete) {
            self = .setupComplete
            return
        }

        if let serverContent = try? container.nestedContainer(keyedBy: ServerContentKeys.self, forKey: .serverContent) {
            if let interim = try? serverContent.nestedContainer(keyedBy: TranscriptionKeys.self, forKey: .interimInputTranscription) {
                let text = (try? interim.decodeIfPresent(String.self, forKey: .text)) ?? nil
                self = .interimTranscription(text ?? "")
                return
            }
            if let final = try? serverContent.nestedContainer(keyedBy: TranscriptionKeys.self, forKey: .inputTranscription) {
                let text = (try? final.decodeIfPresent(String.self, forKey: .text)) ?? nil
                self = .finalTranscription(text ?? "")
                return
            }
            let turnComplete = (try? serverContent.decodeIfPresent(Bool.self, forKey: .turnComplete)) ?? nil
            if turnComplete == true {
                self = .turnComplete
                return
            }
        }

        if container.contains(.goAway) {
            var timeLeft: String?
            if let goAway = try? container.nestedContainer(keyedBy: GoAwayKeys.self, forKey: .goAway) {
                timeLeft = (try? goAway.decodeIfPresent(String.self, forKey: .timeLeft)) ?? nil
            }
            self = .goAway(timeLeft: timeLeft)
            return
        }

        if container.contains(.sessionResumptionUpdate) {
            var handle: String?
            var resumable = false
            if let update = try? container.nestedContainer(keyedBy: SessionResumptionKeys.self, forKey: .sessionResumptionUpdate) {
                handle = (try? update.decodeIfPresent(String.self, forKey: .newHandle)) ?? nil
                resumable = ((try? update.decodeIfPresent(Bool.self, forKey: .resumable)) ?? nil) ?? false
            }
            self = .sessionResumptionUpdate(handle: handle, resumable: resumable)
            return
        }

        if container.contains(.usageMetadata) {
            self = .usageMetadata
            return
        }

        self = .unknown
    }
}

/// Errors returned by Gemini-specific realtime APIs.
public enum GeminiRealtimeError: Error, LocalizedError, Sendable, Equatable {
    /// SpeechKit could not construct a valid Gemini Live URL.
    case invalidURL
    /// The realtime connection failed.
    case connectionFailed(String)
    /// SpeechKit could not encode an outgoing realtime message.
    case encodingFailed
    /// The realtime WebSocket disconnected.
    case disconnected
    /// The Gemini API key is empty.
    case apiKeyMissing
    /// Gemini announced that it is ending the session.
    case sessionEnding(String)

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Gemini realtime URL"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .encodingFailed:
            return "Failed to encode message"
        case .disconnected:
            return "WebSocket disconnected"
        case .apiKeyMissing:
            return "API key not configured"
        case .sessionEnding(let reason):
            return "Gemini is ending the session: \(reason)"
        }
    }
}
