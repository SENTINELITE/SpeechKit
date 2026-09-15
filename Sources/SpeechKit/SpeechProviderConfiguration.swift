import Foundation

/// Configuration for ElevenLabs realtime and file transcription.
public struct ElevenLabsConfiguration: Sendable, Equatable {
    /// The credential used for realtime and file transcription requests.
    public var credential: SpeechCredential
    /// The ElevenLabs API key used for realtime and file transcription requests.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// The ElevenLabs model used by ``SpeechService/startListening()``.
    public var realtimeModelID: ElevenLabsModelID
    /// The ElevenLabs model used by file transcription APIs.
    public var fileTranscriptionModelID: ElevenLabsModelID
    /// An override for the ElevenLabs file transcription endpoint, or `nil` to use the vendor default.
    public var fileEndpoint: URL?
    /// An override for the ElevenLabs realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL?

    /// Creates an ElevenLabs configuration with a long-lived API key.
    public init(
        apiKey: String,
        realtimeModelID: ElevenLabsModelID = .scribeV2Realtime,
        fileTranscriptionModelID: ElevenLabsModelID = .scribeV1,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.init(
            credential: .apiKey(apiKey),
            realtimeModelID: realtimeModelID,
            fileTranscriptionModelID: fileTranscriptionModelID,
            fileEndpoint: fileEndpoint,
            realtimeEndpoint: realtimeEndpoint
        )
    }

    /// Creates an ElevenLabs configuration with any credential.
    public init(
        credential: SpeechCredential,
        realtimeModelID: ElevenLabsModelID = .scribeV2Realtime,
        fileTranscriptionModelID: ElevenLabsModelID = .scribeV1,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = credential
        self.realtimeModelID = realtimeModelID
        self.fileTranscriptionModelID = fileTranscriptionModelID
        self.fileEndpoint = fileEndpoint
        self.realtimeEndpoint = realtimeEndpoint
    }
}

/// Configuration for Cohere file transcription.
public struct CohereConfiguration: Sendable, Equatable {
    /// The credential used for file transcription requests.
    public var credential: SpeechCredential
    /// The Cohere API key used for file transcription requests.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// The Cohere transcription model used for file uploads.
    public var modelID: CohereModelID
    /// The language hint sent with Cohere transcription requests.
    public var language: CohereLanguage
    /// An optional model temperature for transcription output.
    public var temperature: Double?
    /// An override for the Cohere file transcription endpoint, or `nil` to use the vendor default.
    public var fileEndpoint: URL?

    /// Creates a Cohere configuration with a long-lived API key and a typed language value.
    public init(
        apiKey: String,
        modelID: CohereModelID = .transcribe032026,
        language: CohereLanguage = .english,
        temperature: Double? = nil,
        fileEndpoint: URL? = nil
    ) {
        self.init(
            credential: .apiKey(apiKey),
            modelID: modelID,
            language: language,
            temperature: temperature,
            fileEndpoint: fileEndpoint
        )
    }

    /// Creates a Cohere configuration with any credential and a typed language value.
    public init(
        credential: SpeechCredential,
        modelID: CohereModelID = .transcribe032026,
        language: CohereLanguage = .english,
        temperature: Double? = nil,
        fileEndpoint: URL? = nil
    ) {
        self.credential = credential
        self.modelID = modelID
        self.language = language
        self.temperature = temperature
        self.fileEndpoint = fileEndpoint
    }

    /// Creates a Cohere configuration from a raw language code.
    ///
    /// This initializer takes an API key. Assign ``credential`` after init to
    /// use a short-lived token instead.
    ///
    /// - Throws: ``SpeechError/providerFailure(provider:reason:)`` when `languageCode` is not supported.
    public init(
        apiKey: String,
        modelID: CohereModelID = .transcribe032026,
        languageCode: String,
        temperature: Double? = nil,
        fileEndpoint: URL? = nil
    ) throws {
        guard let language = CohereLanguage(rawValue: languageCode) else {
            throw SpeechError.providerFailure(provider: .cohere, reason: "Unsupported language: \(languageCode).")
        }
        self.init(
            apiKey: apiKey,
            modelID: modelID,
            language: language,
            temperature: temperature,
            fileEndpoint: fileEndpoint
        )
    }
}

/// Configuration for Grok file transcription.
public struct GrokConfiguration: Sendable, Equatable {
    /// The credential used for Grok transcription requests.
    public var credential: SpeechCredential
    /// The xAI API key used for Grok transcription requests.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
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
    /// An override for the Grok file transcription endpoint, or `nil` to use the vendor default.
    public var fileEndpoint: URL?
    /// An override for the Grok realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL?

    /// Creates a Grok configuration with a long-lived API key and a typed language value.
    public init(
        apiKey: String,
        modelID: GrokModelID = .stt,
        language: GrokLanguage? = nil,
        format: Bool = false,
        multichannel: Bool = false,
        diarize: Bool = false,
        timestampGranularities: [GrokTimestampGranularity] = [.word],
        realtimeOptions: GrokRealtimeOptions = GrokRealtimeOptions(),
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.init(
            credential: .apiKey(apiKey),
            modelID: modelID,
            language: language,
            format: format,
            multichannel: multichannel,
            diarize: diarize,
            timestampGranularities: timestampGranularities,
            realtimeOptions: realtimeOptions,
            timeoutInterval: timeoutInterval,
            fileEndpoint: fileEndpoint,
            realtimeEndpoint: realtimeEndpoint
        )
    }

    /// Creates a Grok configuration with any credential and a typed language value.
    public init(
        credential: SpeechCredential,
        modelID: GrokModelID = .stt,
        language: GrokLanguage? = nil,
        format: Bool = false,
        multichannel: Bool = false,
        diarize: Bool = false,
        timestampGranularities: [GrokTimestampGranularity] = [.word],
        realtimeOptions: GrokRealtimeOptions = GrokRealtimeOptions(),
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = credential
        self.modelID = modelID
        self.language = language
        self.format = format
        self.multichannel = multichannel
        self.diarize = diarize
        self.timestampGranularities = timestampGranularities
        self.realtimeOptions = realtimeOptions
        self.timeoutInterval = timeoutInterval
        self.fileEndpoint = fileEndpoint
        self.realtimeEndpoint = realtimeEndpoint
    }

    /// Creates a Grok configuration from an optional raw language code.
    ///
    /// This initializer takes an API key. Assign ``credential`` after init to
    /// use a short-lived token instead.
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
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
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
            timeoutInterval: timeoutInterval,
            fileEndpoint: fileEndpoint,
            realtimeEndpoint: realtimeEndpoint
        )
    }
}

/// Configuration for Aqua file transcription.
public struct AquaConfiguration: Sendable, Equatable {
    /// The credential used for file transcription requests.
    public var credential: SpeechCredential
    /// The Aqua API key used for file transcription requests.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// The Aqua transcription model used for file uploads.
    public var modelID: AquaModelID
    /// An optional language hint.
    public var language: AquaLanguage?
    /// An override for the Aqua file transcription endpoint, or `nil` to use the vendor default.
    public var fileEndpoint: URL?

    /// Creates an Aqua configuration with a long-lived API key and a typed language value.
    public init(
        apiKey: String,
        modelID: AquaModelID = .avalonV15,
        language: AquaLanguage? = nil,
        fileEndpoint: URL? = nil
    ) {
        self.init(
            credential: .apiKey(apiKey),
            modelID: modelID,
            language: language,
            fileEndpoint: fileEndpoint
        )
    }

    /// Creates an Aqua configuration with any credential and a typed language value.
    public init(
        credential: SpeechCredential,
        modelID: AquaModelID = .avalonV15,
        language: AquaLanguage? = nil,
        fileEndpoint: URL? = nil
    ) {
        self.credential = credential
        self.modelID = modelID
        self.language = language
        self.fileEndpoint = fileEndpoint
    }

    /// Creates an Aqua configuration from an optional raw language code.
    ///
    /// This initializer takes an API key. Assign ``credential`` after init to
    /// use a short-lived token instead.
    ///
    /// - Throws: ``SpeechError/providerFailure(provider:reason:)`` when `languageCode` is not supported.
    public init(
        apiKey: String,
        modelID: AquaModelID = .avalonV15,
        languageCode: String?,
        fileEndpoint: URL? = nil
    ) throws {
        let language = try languageCode.map { languageCode in
            guard let language = AquaLanguage(rawValue: languageCode) else {
                throw SpeechError.providerFailure(provider: .aqua, reason: "Unsupported language: \(languageCode).")
            }
            return language
        }
        self.init(apiKey: apiKey, modelID: modelID, language: language, fileEndpoint: fileEndpoint)
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
    /// The credential used for realtime and file transcription requests.
    public var credential: SpeechCredential
    /// The OpenAI API key used for realtime and file transcription requests.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
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
    /// An override for the OpenAI file transcription endpoint, or `nil` to use the vendor default.
    public var fileEndpoint: URL?
    /// An override for the OpenAI Realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL?

    /// Creates an OpenAI configuration with a long-lived API key.
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
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.init(
            credential: .apiKey(apiKey),
            fileTranscriptionModelID: fileTranscriptionModelID,
            realtimeSessionModelID: realtimeSessionModelID,
            realtimeTranscriptionModelID: realtimeTranscriptionModelID,
            language: language,
            languages: languages,
            prompt: prompt,
            keywords: keywords,
            temperature: temperature,
            diarizationChunkingStrategy: diarizationChunkingStrategy,
            knownSpeakers: knownSpeakers,
            realtimeDelay: realtimeDelay,
            realtimeCommitInterval: realtimeCommitInterval,
            timeoutInterval: timeoutInterval,
            fileEndpoint: fileEndpoint,
            realtimeEndpoint: realtimeEndpoint
        )
    }

    /// Creates an OpenAI configuration with any credential.
    public init(
        credential: SpeechCredential,
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
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = credential
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
        self.fileEndpoint = fileEndpoint
        self.realtimeEndpoint = realtimeEndpoint
    }
}

/// Configuration for Meta realtime and file transcription.
public struct MetaConfiguration: Sendable, Equatable {
    /// The credential used for realtime and file transcription requests.
    public var credential: SpeechCredential
    /// The Meta API key used for realtime and file transcription requests.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// The Meta transcription model used for file uploads and realtime sessions.
    public var modelID: MetaModelID
    /// The transcription mode used for file uploads.
    public var mode: MetaTranscriptionMode
    /// Language names that bias Meta transcription.
    public var languageBias: [MetaLanguage]
    /// Literal terms that may appear in recordings or realtime audio.
    public var keywords: [String]
    /// The default Meta realtime transcription options.
    public var realtimeOptions: MetaRealtimeOptions
    /// The network timeout for Meta upload requests.
    public var timeoutInterval: TimeInterval
    /// An override for the Meta file transcription endpoint, or `nil` to use the vendor default.
    public var fileEndpoint: URL?
    /// An override for the Meta realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL?

    /// Creates a Meta configuration with a long-lived API key and typed language values.
    public init(
        apiKey: String,
        modelID: MetaModelID = .museVoiceTranscribe1,
        mode: MetaTranscriptionMode = .endpointing,
        languageBias: [MetaLanguage] = [],
        keywords: [String] = [],
        realtimeOptions: MetaRealtimeOptions = MetaRealtimeOptions(),
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.init(
            credential: .apiKey(apiKey),
            modelID: modelID,
            mode: mode,
            languageBias: languageBias,
            keywords: keywords,
            realtimeOptions: realtimeOptions,
            timeoutInterval: timeoutInterval,
            fileEndpoint: fileEndpoint,
            realtimeEndpoint: realtimeEndpoint
        )
    }

    /// Creates a Meta configuration with any credential and typed language values.
    public init(
        credential: SpeechCredential,
        modelID: MetaModelID = .museVoiceTranscribe1,
        mode: MetaTranscriptionMode = .endpointing,
        languageBias: [MetaLanguage] = [],
        keywords: [String] = [],
        realtimeOptions: MetaRealtimeOptions = MetaRealtimeOptions(),
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = credential
        self.modelID = modelID
        self.mode = mode
        self.languageBias = languageBias
        self.keywords = keywords
        self.realtimeOptions = realtimeOptions
        self.timeoutInterval = timeoutInterval
        self.fileEndpoint = fileEndpoint
        self.realtimeEndpoint = realtimeEndpoint
    }

    /// Creates a Meta configuration from raw language names.
    ///
    /// Meta biases transcription with language names such as `"English"` or
    /// `"Mandarin Chinese"` instead of BCP-47 codes.
    ///
    /// This initializer takes an API key. Assign ``credential`` after init to
    /// use a short-lived token instead.
    ///
    /// - Throws: ``SpeechError/providerFailure(provider:reason:)`` when a name in `languageNames` is not supported.
    public init(
        apiKey: String,
        modelID: MetaModelID = .museVoiceTranscribe1,
        mode: MetaTranscriptionMode = .endpointing,
        languageNames: [String],
        keywords: [String] = [],
        realtimeOptions: MetaRealtimeOptions = MetaRealtimeOptions(),
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) throws {
        let languageBias = try languageNames.map { languageName in
            guard let language = MetaLanguage(rawValue: languageName) else {
                throw SpeechError.providerFailure(provider: .meta, reason: "Unsupported language: \(languageName).")
            }
            return language
        }
        self.init(
            apiKey: apiKey,
            modelID: modelID,
            mode: mode,
            languageBias: languageBias,
            keywords: keywords,
            realtimeOptions: realtimeOptions,
            timeoutInterval: timeoutInterval,
            fileEndpoint: fileEndpoint,
            realtimeEndpoint: realtimeEndpoint
        )
    }
}

/// Configuration for Gemini realtime and file transcription.
public struct GeminiConfiguration: Sendable, Equatable {
    /// The credential used for realtime and file transcription requests.
    ///
    /// Google ephemeral tokens only authorize Gemini Live sessions. A
    /// ``SpeechCredential/token(_:)`` credential used for Gemini REST
    /// transcription must be an OAuth access token or a credential accepted by
    /// your own proxy, because SpeechKit sends it as `Authorization: Bearer`.
    public var credential: SpeechCredential
    /// The Google AI API key used for realtime and file transcription requests.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// The Gemini transcription model used for file uploads.
    public var fileTranscriptionModelID: GeminiFileTranscriptionModelID
    /// The Gemini Live model used for realtime transcription.
    ///
    /// This is the single source of truth for the realtime model. ``SpeechService``
    /// applies it on top of ``realtimeOptions``, overriding
    /// ``GeminiRealtimeOptions/modelID``.
    public var realtimeModelID: GeminiRealtimeModelID
    /// BCP-47 language hints, or an empty array to let Gemini detect the language.
    public var languageCodes: [String]
    /// Literal terms that may appear in recordings or realtime audio.
    ///
    /// Gemini rejects a custom vocabulary combined with diarization or word timestamps.
    public var customVocabulary: [String]
    /// The transcription mode used for file uploads and realtime sessions.
    public var mode: GeminiTranscriptionMode
    /// A Boolean value that indicates whether Gemini should identify speakers.
    public var diarize: Bool
    /// The timestamp granularities to request from Gemini.
    public var timestampGranularities: [GeminiTimestampGranularity]
    /// The upload strategy used for Gemini file transcription requests.
    public var uploadStrategy: GeminiFileUploadStrategy
    /// The processing mode used for Gemini file transcription requests.
    public var processingMode: GeminiProcessingMode
    /// The default Gemini realtime transcription options.
    ///
    /// ``SpeechService`` replaces ``GeminiRealtimeOptions/modelID`` on these
    /// options with ``realtimeModelID`` before starting a session.
    public var realtimeOptions: GeminiRealtimeOptions
    /// The network timeout for Gemini file uploads.
    public var timeoutInterval: TimeInterval
    /// An override for the Gemini interactions endpoint used by file transcription, or `nil` to use the vendor default.
    public var fileEndpoint: URL?
    /// An override for the Gemini Files API upload endpoint, or `nil` to use the vendor default.
    public var filesEndpoint: URL?
    /// An override for the Gemini Live WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL?

    /// Creates a Gemini configuration with a long-lived API key.
    public init(
        apiKey: String,
        fileTranscriptionModelID: GeminiFileTranscriptionModelID = .transcribe35,
        realtimeModelID: GeminiRealtimeModelID = .transcribeLive35,
        languageCodes: [String] = [],
        customVocabulary: [String] = [],
        mode: GeminiTranscriptionMode = .verbatim,
        diarize: Bool = false,
        timestampGranularities: [GeminiTimestampGranularity] = [],
        uploadStrategy: GeminiFileUploadStrategy = .automatic,
        processingMode: GeminiProcessingMode = .synchronous,
        realtimeOptions: GeminiRealtimeOptions = GeminiRealtimeOptions(),
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        filesEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.init(
            credential: .apiKey(apiKey),
            fileTranscriptionModelID: fileTranscriptionModelID,
            realtimeModelID: realtimeModelID,
            languageCodes: languageCodes,
            customVocabulary: customVocabulary,
            mode: mode,
            diarize: diarize,
            timestampGranularities: timestampGranularities,
            uploadStrategy: uploadStrategy,
            processingMode: processingMode,
            realtimeOptions: realtimeOptions,
            timeoutInterval: timeoutInterval,
            fileEndpoint: fileEndpoint,
            filesEndpoint: filesEndpoint,
            realtimeEndpoint: realtimeEndpoint
        )
    }

    /// Creates a Gemini configuration with any credential.
    public init(
        credential: SpeechCredential,
        fileTranscriptionModelID: GeminiFileTranscriptionModelID = .transcribe35,
        realtimeModelID: GeminiRealtimeModelID = .transcribeLive35,
        languageCodes: [String] = [],
        customVocabulary: [String] = [],
        mode: GeminiTranscriptionMode = .verbatim,
        diarize: Bool = false,
        timestampGranularities: [GeminiTimestampGranularity] = [],
        uploadStrategy: GeminiFileUploadStrategy = .automatic,
        processingMode: GeminiProcessingMode = .synchronous,
        realtimeOptions: GeminiRealtimeOptions = GeminiRealtimeOptions(),
        timeoutInterval: TimeInterval = 10 * 60,
        fileEndpoint: URL? = nil,
        filesEndpoint: URL? = nil,
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = credential
        self.fileTranscriptionModelID = fileTranscriptionModelID
        self.realtimeModelID = realtimeModelID
        self.languageCodes = languageCodes
        self.customVocabulary = customVocabulary
        self.mode = mode
        self.diarize = diarize
        self.timestampGranularities = timestampGranularities
        self.uploadStrategy = uploadStrategy
        self.processingMode = processingMode
        self.realtimeOptions = realtimeOptions
        self.timeoutInterval = timeoutInterval
        self.fileEndpoint = fileEndpoint
        self.filesEndpoint = filesEndpoint
        self.realtimeEndpoint = realtimeEndpoint
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
    /// Meta Muse Voice Transcribe file transcription.
    case meta
    /// Gemini 3.5 Transcribe file transcription.
    case gemini
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
        var providers: [SpeechFileTranscriptionProvider] = [.elevenLabs, .aqua, .cohere, .grok, .openAI, .meta, .gemini]
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
    /// Options for a Meta file transcription request.
    case meta(
        modelID: MetaModelID? = nil,
        mode: MetaTranscriptionMode? = nil,
        languageBias: [MetaLanguage]? = nil,
        keywords: [String]? = nil,
        sessionID: String? = nil,
        timeoutInterval: TimeInterval? = nil
    )
    /// Options for a Gemini file transcription request.
    case gemini(
        modelID: GeminiFileTranscriptionModelID? = nil,
        languageCodes: [String]? = nil,
        customVocabulary: [String]? = nil,
        mode: GeminiTranscriptionMode? = nil,
        diarize: Bool? = nil,
        timestampGranularities: [GeminiTimestampGranularity]? = nil,
        uploadStrategy: GeminiFileUploadStrategy? = nil,
        processingMode: GeminiProcessingMode? = nil,
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
        case .meta:
            return .meta
        case .gemini:
            return .gemini
        #if !os(watchOS)
        case .apple:
            return .apple
        #endif
        }
    }
}
