import Foundation

/// Configuration for ElevenLabs realtime and file transcription.
public struct ElevenLabsConfiguration: Sendable, Equatable {
    /// The ElevenLabs API key used for realtime and file transcription requests.
    public var apiKey: String
    /// The ElevenLabs model used by ``SpeechService/startListening()``.
    public var realtimeModelID: ElevenLabsModelID
    /// The ElevenLabs model used by file transcription APIs.
    public var fileTranscriptionModelID: ElevenLabsModelID

    /// Creates an ElevenLabs configuration.
    public init(
        apiKey: String,
        realtimeModelID: ElevenLabsModelID = .scribeV2Realtime,
        fileTranscriptionModelID: ElevenLabsModelID = .scribeV1
    ) {
        self.apiKey = apiKey
        self.realtimeModelID = realtimeModelID
        self.fileTranscriptionModelID = fileTranscriptionModelID
    }
}

/// Configuration for Cohere file transcription.
public struct CohereConfiguration: Sendable, Equatable {
    /// The Cohere API key used for file transcription requests.
    public var apiKey: String
    /// The Cohere transcription model used for file uploads.
    public var modelID: CohereModelID
    /// The language hint sent with Cohere transcription requests.
    public var language: CohereLanguage
    /// An optional model temperature for transcription output.
    public var temperature: Double?

    /// Creates a Cohere configuration with a typed language value.
    public init(
        apiKey: String,
        modelID: CohereModelID = .transcribe032026,
        language: CohereLanguage = .english,
        temperature: Double? = nil
    ) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.language = language
        self.temperature = temperature
    }

    /// Creates a Cohere configuration from a raw language code.
    ///
    /// - Throws: ``SpeechError/providerFailure(provider:reason:)`` when `languageCode` is not supported.
    public init(
        apiKey: String,
        modelID: CohereModelID = .transcribe032026,
        languageCode: String,
        temperature: Double? = nil
    ) throws {
        guard let language = CohereLanguage(rawValue: languageCode) else {
            throw SpeechError.providerFailure(provider: .cohere, reason: "Unsupported language: \(languageCode).")
        }
        self.init(apiKey: apiKey, modelID: modelID, language: language, temperature: temperature)
    }
}

/// Configuration for Grok file transcription.
public struct GrokConfiguration: Sendable, Equatable {
    /// The xAI API key used for Grok transcription requests.
    public var apiKey: String
    /// The Grok speech-to-text model used for file uploads.
    public var modelID: GrokModelID
    /// An optional language hint.
    public var language: GrokLanguage?
    /// A Boolean value that indicates whether Grok should format the transcript.
    public var format: Bool
    /// A Boolean value that indicates whether Grok should process multichannel audio.
    public var multichannel: Bool
    /// A Boolean value that indicates whether Grok should identify speakers.
    public var diarize: Bool
    /// The timestamp granularities to request from Grok.
    public var timestampGranularities: [GrokTimestampGranularity]
    /// The default Grok realtime transcription options.
    public var realtimeOptions: GrokRealtimeOptions
    /// The network timeout for Grok upload requests.
    public var timeoutInterval: TimeInterval

    /// Creates a Grok configuration with a typed language value.
    public init(
        apiKey: String,
        modelID: GrokModelID = .stt,
        language: GrokLanguage? = nil,
        format: Bool = false,
        multichannel: Bool = false,
        diarize: Bool = false,
        timestampGranularities: [GrokTimestampGranularity] = [.word],
        realtimeOptions: GrokRealtimeOptions = GrokRealtimeOptions(),
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.language = language
        self.format = format
        self.multichannel = multichannel
        self.diarize = diarize
        self.timestampGranularities = timestampGranularities
        self.realtimeOptions = realtimeOptions
        self.timeoutInterval = timeoutInterval
    }

    /// Creates a Grok configuration from an optional raw language code.
    ///
    /// - Throws: ``SpeechError/providerFailure(provider:reason:)`` when `languageCode` is not supported.
    public init(
        apiKey: String,
        modelID: GrokModelID = .stt,
        languageCode: String?,
        format: Bool = false,
        multichannel: Bool = false,
        diarize: Bool = false,
        timestampGranularities: [GrokTimestampGranularity] = [.word],
        realtimeOptions: GrokRealtimeOptions = GrokRealtimeOptions(),
        timeoutInterval: TimeInterval = 10 * 60
    ) throws {
        let language = try languageCode.map { languageCode in
            guard let language = GrokLanguage(rawValue: languageCode) else {
                throw SpeechError.providerFailure(provider: .grok, reason: "Unsupported language: \(languageCode).")
            }
            return language
        }
        self.init(
            apiKey: apiKey,
            modelID: modelID,
            language: language,
            format: format,
            multichannel: multichannel,
            diarize: diarize,
            timestampGranularities: timestampGranularities,
            realtimeOptions: realtimeOptions,
            timeoutInterval: timeoutInterval
        )
    }
}

/// Configuration for Aqua file transcription.
public struct AquaConfiguration: Sendable, Equatable {
    /// The Aqua API key used for file transcription requests.
    public var apiKey: String
    /// The Aqua transcription model used for file uploads.
    public var modelID: AquaModelID
    /// An optional language hint.
    public var language: AquaLanguage?

    /// Creates an Aqua configuration with a typed language value.
    public init(
        apiKey: String,
        modelID: AquaModelID = .avalonV15,
        language: AquaLanguage? = nil
    ) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.language = language
    }

    /// Creates an Aqua configuration from an optional raw language code.
    ///
    /// - Throws: ``SpeechError/providerFailure(provider:reason:)`` when `languageCode` is not supported.
    public init(
        apiKey: String,
        modelID: AquaModelID = .avalonV15,
        languageCode: String?
    ) throws {
        let language = try languageCode.map { languageCode in
            guard let language = AquaLanguage(rawValue: languageCode) else {
                throw SpeechError.providerFailure(provider: .aqua, reason: "Unsupported language: \(languageCode).")
            }
            return language
        }
        self.init(apiKey: apiKey, modelID: modelID, language: language)
    }
}

/// Configuration for OpenAI realtime and file transcription.
public struct OpenAIConfiguration: Sendable, Equatable {
    /// The OpenAI API key used for realtime and file transcription requests.
    public var apiKey: String
    /// The OpenAI file transcription model used for uploads.
    public var fileTranscriptionModelID: OpenAIFileTranscriptionModelID
    /// The OpenAI realtime session model used for WebSocket transcription sessions.
    public var realtimeSessionModelID: OpenAIRealtimeSessionModelID
    /// The OpenAI realtime transcription model used for microphone transcription.
    public var realtimeTranscriptionModelID: OpenAIRealtimeTranscriptionModelID
    /// An optional ISO-639-1 language hint used by default.
    public var language: String?
    /// The default prompt used for file transcription.
    public var prompt: String?
    /// The default file transcription temperature.
    public var temperature: Double?
    /// The default chunking strategy for OpenAI diarized file transcription.
    public var diarizationChunkingStrategy: OpenAIDiarizationChunkingStrategy?
    /// The default known speaker references for OpenAI diarized file transcription.
    public var knownSpeakers: [OpenAIKnownSpeaker]
    /// The default OpenAI realtime transcription delay.
    public var realtimeDelay: OpenAIRealtimeDelay
    /// The interval between OpenAI realtime audio buffer commits.
    public var realtimeCommitInterval: TimeInterval
    /// The network timeout for OpenAI file uploads.
    public var timeoutInterval: TimeInterval

    /// Creates an OpenAI configuration.
    public init(
        apiKey: String,
        fileTranscriptionModelID: OpenAIFileTranscriptionModelID = .gpt4oTranscribe,
        realtimeSessionModelID: OpenAIRealtimeSessionModelID = .gptRealtime,
        realtimeTranscriptionModelID: OpenAIRealtimeTranscriptionModelID = .gpt4oTranscribe,
        language: String? = nil,
        prompt: String? = nil,
        temperature: Double? = nil,
        diarizationChunkingStrategy: OpenAIDiarizationChunkingStrategy? = nil,
        knownSpeakers: [OpenAIKnownSpeaker] = [],
        realtimeDelay: OpenAIRealtimeDelay = .auto,
        realtimeCommitInterval: TimeInterval = 1,
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.apiKey = apiKey
        self.fileTranscriptionModelID = fileTranscriptionModelID
        self.realtimeSessionModelID = realtimeSessionModelID
        self.realtimeTranscriptionModelID = realtimeTranscriptionModelID
        self.language = language
        self.prompt = prompt
        self.temperature = temperature
        self.diarizationChunkingStrategy = diarizationChunkingStrategy
        self.knownSpeakers = knownSpeakers
        self.realtimeDelay = realtimeDelay
        self.realtimeCommitInterval = realtimeCommitInterval
        self.timeoutInterval = timeoutInterval
    }
}

/// A provider that can transcribe uploaded audio files.
public enum SpeechFileTranscriptionProvider: String, Sendable, CaseIterable {
    /// ElevenLabs Scribe file transcription.
    case elevenLabs
    /// Aqua Avalon file transcription.
    case aqua
    /// Cohere Transcribe file transcription.
    case cohere
    /// Grok speech-to-text file transcription.
    case grok
    /// OpenAI speech-to-text file transcription.
    case openAI
}

/// Provider-specific options for a single file transcription request.
public enum SpeechFileTranscriptionOptions: Sendable, Equatable {
    /// Options for an ElevenLabs file transcription request.
    case elevenLabs(modelID: ElevenLabsModelID? = nil)
    /// Options for an Aqua file transcription request.
    case aqua(modelID: AquaModelID? = nil, language: AquaLanguage? = nil)
    /// Options for a Cohere file transcription request.
    case cohere(modelID: CohereModelID? = nil, language: CohereLanguage? = nil, temperature: Double? = nil)
    /// Options for a Grok file transcription request.
    case grok(
        modelID: GrokModelID? = nil,
        language: GrokLanguage? = nil,
        format: Bool? = nil,
        multichannel: Bool? = nil,
        channels: Int? = nil,
        diarize: Bool? = nil,
        timestampGranularities: [GrokTimestampGranularity]? = nil,
        audioFormat: GrokAudioFormat? = nil,
        sampleRate: Int? = nil,
        timeoutInterval: TimeInterval? = nil
    )
    /// Options for an OpenAI file transcription request.
    case openAI(
        modelID: OpenAIFileTranscriptionModelID? = nil,
        language: String? = nil,
        prompt: String? = nil,
        temperature: Double? = nil,
        includeLogprobs: Bool? = nil,
        timestampGranularities: [OpenAITimestampGranularity]? = nil,
        diarizationChunkingStrategy: OpenAIDiarizationChunkingStrategy? = nil,
        knownSpeakers: [OpenAIKnownSpeaker]? = nil,
        timeoutInterval: TimeInterval? = nil
    )

    var provider: SpeechFileTranscriptionProvider {
        switch self {
        case .elevenLabs:
            return .elevenLabs
        case .aqua:
            return .aqua
        case .cohere:
            return .cohere
        case .grok:
            return .grok
        case .openAI:
            return .openAI
        }
    }
}
