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

/// Configuration for Apple's local Speech framework transcription.
///
/// Apple transcription runs through `SpeechAnalyzer` and `SpeechTranscriber`,
/// so it does not require an API key. The APIs are only available on iOS 26,
/// macOS 26, and visionOS 26, and are unavailable on watchOS.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
public struct AppleSpeechConfiguration: Sendable, Equatable {
    /// The preferred locale for local transcription.
    ///
    /// SpeechKit resolves this to Apple's nearest supported locale before
    /// creating a transcriber.
    public var locale: Locale
    /// A Boolean value indicating whether SpeechKit may download missing local speech assets.
    ///
    /// When this is `false`, SpeechKit fails with
    /// ``SpeechError/appleSpeechAssetsUnavailable(localeIdentifier:)`` instead
    /// of starting an asset installation request.
    public var preparesAssetsAutomatically: Bool
    /// Terms that should bias Apple's local speech analyzer toward app-specific vocabulary.
    public var contextualStrings: [String]
    /// The model retention policy used by Apple local speech analysis.
    public var modelRetention: AppleSpeechModelRetention

    /// Creates an Apple local speech configuration.
    ///
    /// - Parameters:
    ///   - locale: The preferred transcription locale.
    ///   - preparesAssetsAutomatically: Whether SpeechKit may download missing
    ///     Apple speech assets for the resolved locale.
    ///   - contextualStrings: App-specific words or phrases to bias recognition.
    ///   - modelRetention: How long Apple should retain loaded speech models.
    public init(
        locale: Locale = .current,
        preparesAssetsAutomatically: Bool = true,
        contextualStrings: [String] = [],
        modelRetention: AppleSpeechModelRetention = .whileInUse
    ) {
        self.locale = locale
        self.preparesAssetsAutomatically = preparesAssetsAutomatically
        self.contextualStrings = contextualStrings
        self.modelRetention = modelRetention
    }
}

/// The model retention policy for Apple's local speech analyzer.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
public enum AppleSpeechModelRetention: Sendable, Equatable, CaseIterable {
    /// Keep speech models loaded only while analysis is active.
    case whileInUse
    /// Let the system keep speech models loaded briefly after analysis completes.
    case lingering
    /// Keep speech models loaded for the lifetime of the current process.
    case processLifetime
}

/// Options for one Apple local file transcription request.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
public struct AppleSpeechFileTranscriptionOptions: Sendable, Equatable {
    /// The preferred locale for this transcription request.
    public var locale: Locale?
    /// Overrides whether SpeechKit may download missing Apple speech assets.
    public var preparesAssetsAutomatically: Bool?

    /// Creates Apple local file transcription options.
    public init(
        locale: Locale? = nil,
        preparesAssetsAutomatically: Bool? = nil
    ) {
        self.locale = locale
        self.preparesAssetsAutomatically = preparesAssetsAutomatically
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
    /// Expected input language codes for OpenAI models that support multiple language hints.
    public var languages: [String]
    /// The default prompt used for file transcription.
    public var prompt: String?
    /// Literal terms that may appear in recordings or realtime audio.
    public var keywords: [String]
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
        fileTranscriptionModelID: OpenAIFileTranscriptionModelID = .gptTranscribe,
        realtimeSessionModelID: OpenAIRealtimeSessionModelID = .gptRealtime,
        realtimeTranscriptionModelID: OpenAIRealtimeTranscriptionModelID = .gptLiveTranscribe,
        language: String? = nil,
        languages: [String] = [],
        prompt: String? = nil,
        keywords: [String] = [],
        temperature: Double? = nil,
        diarizationChunkingStrategy: OpenAIDiarizationChunkingStrategy? = nil,
        knownSpeakers: [OpenAIKnownSpeaker] = [],
        realtimeDelay: OpenAIRealtimeDelay = .low,
        realtimeCommitInterval: TimeInterval = 1,
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.apiKey = apiKey
        self.fileTranscriptionModelID = fileTranscriptionModelID
        self.realtimeSessionModelID = realtimeSessionModelID
        self.realtimeTranscriptionModelID = realtimeTranscriptionModelID
        self.language = language
        self.languages = languages
        self.prompt = prompt
        self.keywords = keywords
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
    /// Apple local Speech framework file transcription.
    ///
    /// SpeechKit only includes this provider in ``allCases`` on iOS 26,
    /// macOS 26, and visionOS 26. Calling it directly on older OS versions
    /// throws ``SpeechError/appleSpeechUnavailable``.
    #if !os(watchOS)
    case apple
    #endif

    /// The file transcription providers that are callable on the current OS.
    public static var allCases: [SpeechFileTranscriptionProvider] {
        var providers: [SpeechFileTranscriptionProvider] = [.elevenLabs, .aqua, .cohere, .grok, .openAI]
        #if !os(watchOS)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            providers.append(.apple)
        }
        #endif
        return providers
    }
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
        languages: [String]? = nil,
        prompt: String? = nil,
        keywords: [String]? = nil,
        temperature: Double? = nil,
        includeLogprobs: Bool? = nil,
        timestampGranularities: [OpenAITimestampGranularity]? = nil,
        diarizationChunkingStrategy: OpenAIDiarizationChunkingStrategy? = nil,
        knownSpeakers: [OpenAIKnownSpeaker]? = nil,
        timeoutInterval: TimeInterval? = nil
    )
    /// Options for an Apple local file transcription request.
    ///
    /// These options are only meaningful when the request runs on iOS 26,
    /// macOS 26, or visionOS 26. On older OS versions, Apple local
    /// transcription throws ``SpeechError/appleSpeechUnavailable`` before
    /// reading these values.
    #if !os(watchOS)
    case apple(
        locale: Locale? = nil,
        preparesAssetsAutomatically: Bool? = nil
    )
    #endif

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
        #if !os(watchOS)
        case .apple:
            return .apple
        #endif
        }
    }
}
