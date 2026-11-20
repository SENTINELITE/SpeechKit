import Foundation
import SwiftUI

/// A SwiftUI-observable service for realtime microphone transcription and audio file transcription.
@Observable
@MainActor
public final class SpeechService {
    /// The ElevenLabs configuration used for realtime and ElevenLabs file transcription.
    public var elevenLabs: ElevenLabsConfiguration? {
        didSet { applyRealtimeConfig() }
    }
    /// The Cohere configuration used for Cohere file transcription.
    public var cohere: CohereConfiguration? { didSet { invalidatePendingOperations() } }
    /// The Grok configuration used for Grok file transcription.
    public var grok: GrokConfiguration? {
        didSet { applyGrokRealtimeConfig() }
    }
    /// The Aqua configuration used for Aqua file transcription.
    public var aqua: AquaConfiguration? { didSet { invalidatePendingOperations() } }
    /// The OpenAI configuration used for OpenAI realtime and file transcription.
    public var openAI: OpenAIConfiguration? {
        didSet { applyOpenAIRealtimeConfig() }
    }
    /// The Meta configuration used for Meta realtime and file transcription.
    public var meta: MetaConfiguration? {
        didSet { applyMetaRealtimeConfig() }
    }
    /// The Gemini configuration used for Gemini realtime and file transcription.
    public var gemini: GeminiConfiguration? {
        didSet { applyGeminiRealtimeConfig() }
    }
    /// The Mistral configuration used for Mistral realtime and file transcription.
    public var mistral: MistralConfiguration? {
        didSet { applyMistralRealtimeConfig() }
    }
    /// The Fish Audio configuration used for Fish Audio realtime and file transcription.
    public var fishAudio: FishAudioConfiguration? {
        didSet { applyFishAudioRealtimeConfig() }
    }
    /// The Apple local Speech configuration used for realtime and file transcription.
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @available(watchOS, unavailable)
    public var apple: AppleSpeechConfiguration? {
        get { appleConfigurationStorage as? AppleSpeechConfiguration }
        set {
            invalidatePendingOperations()
            appleConfigurationStorage = newValue
            #if !os(watchOS)
            (appleRealtimeServiceStorage as? AppleSpeechService)?.invalidateConfiguration()
            #endif
        }
    }

    let elevenLabsRealtimeService: ElevenLabsService
    let openAIRealtimeService: OpenAIRealtimeService
    let grokRealtimeService: GrokRealtimeService
    let metaRealtimeService: MetaRealtimeService
    let geminiRealtimeService: GeminiRealtimeService
    let mistralRealtimeService: MistralRealtimeService
    let fishAudioRealtimeService: FishAudioRealtimeService
    /// Recording retention shared by all realtime providers.
    public var recordingRetention: SpeechRecordingRetention = .retainUntilDiscarded {
        didSet {
            elevenLabsRealtimeService.recordingRetention = recordingRetention
            openAIRealtimeService.recordingRetention = recordingRetention
            grokRealtimeService.recordingRetention = recordingRetention
            metaRealtimeService.recordingRetention = recordingRetention
            geminiRealtimeService.recordingRetention = recordingRetention
            mistralRealtimeService.recordingRetention = recordingRetention
            fishAudioRealtimeService.recordingRetention = recordingRetention
            #if !os(watchOS)
            if #available(iOS 26, macOS 26, visionOS 26, *), let service = appleRealtimeServiceStorage as? AppleSpeechService {
                service.recordingRetention = recordingRetention
            }
            #endif
        }
    }
    public internal(set) var relay: SpeechRelay?
    public private(set) var credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    var relaySession: SpeechRelaySession?
    var realtimeStartGeneration = UUID()
    var realtimeStartTask: Task<Void, Never>?
    var pendingRealtimeProvider: SpeechRealtimeProvider?
    var fileOperationCancellations: [UUID: @Sendable () -> Void] = [:]
    var fileGeneration = UUID()
    let urlSession: URLSession
    var appleConfigurationStorage: Any?
    var appleRealtimeServiceStorage: Any?
    /// Values attached by extension packages through ``SpeechServiceExtensionKey``.
    ///
    /// This is a stored property so that writes through the
    /// ``SpeechService/subscript(extension:)`` subscript publish an observation
    /// change.
    var extensionStorage: [String: Any] = [:]
    /// The provider currently used for realtime transcription state.
    public internal(set) var activeRealtimeProvider: SpeechRealtimeProvider = .elevenLabs
    var fallbackConnectionState: SpeechRealtimeConnectionState?
    var fallbackLastError: Error?

    /// Creates a speech service with any provider configurations your app needs.
    public init(
        elevenLabs: ElevenLabsConfiguration? = nil,
        cohere: CohereConfiguration? = nil,
        grok: GrokConfiguration? = nil,
        aqua: AquaConfiguration? = nil,
        openAI: OpenAIConfiguration? = nil,
        meta: MetaConfiguration? = nil,
        gemini: GeminiConfiguration? = nil,
        mistral: MistralConfiguration? = nil,
        fishAudio: FishAudioConfiguration? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credentialPolicy = credentialPolicy
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.aqua = aqua
        self.openAI = openAI
        self.meta = meta
        self.gemini = gemini
        self.mistral = mistral
        self.fishAudio = fishAudio
        self.elevenLabsRealtimeService = ElevenLabsService()
        self.openAIRealtimeService = OpenAIRealtimeService()
        self.grokRealtimeService = GrokRealtimeService()
        self.metaRealtimeService = MetaRealtimeService()
        self.geminiRealtimeService = GeminiRealtimeService()
        self.mistralRealtimeService = MistralRealtimeService()
        self.fishAudioRealtimeService = FishAudioRealtimeService()
        self.urlSession = SpeechTransport.session()
        applyRealtimeConfig()
        applyOpenAIRealtimeConfig()
        applyGrokRealtimeConfig()
        applyMetaRealtimeConfig()
        applyGeminiRealtimeConfig()
        applyMistralRealtimeConfig()
        applyFishAudioRealtimeConfig()
    }

    /// Creates a speech service with Apple local Speech configuration.
    ///
    /// Use this initializer only on OS versions that expose `SpeechAnalyzer`
    /// and `SpeechTranscriber`. The base ``SpeechService/init(elevenLabs:cohere:grok:aqua:openAI:meta:gemini:mistral:fishAudio:credentialPolicy:)``
    /// initializer remains available for the package's lower deployment targets.
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @available(watchOS, unavailable)
    @_disfavoredOverload
    public convenience init(
        elevenLabs: ElevenLabsConfiguration? = nil,
        cohere: CohereConfiguration? = nil,
        grok: GrokConfiguration? = nil,
        aqua: AquaConfiguration? = nil,
        openAI: OpenAIConfiguration? = nil,
        meta: MetaConfiguration? = nil,
        gemini: GeminiConfiguration? = nil,
        mistral: MistralConfiguration? = nil,
        fishAudio: FishAudioConfiguration? = nil,
        apple: AppleSpeechConfiguration? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.init(
            elevenLabs: elevenLabs,
            cohere: cohere,
            grok: grok,
            aqua: aqua,
            openAI: openAI,
            meta: meta,
            gemini: gemini,
            mistral: mistral,
            fishAudio: fishAudio,
            credentialPolicy: credentialPolicy
        )
        self.apple = apple
    }

    init(
        elevenLabs: ElevenLabsConfiguration? = nil,
        cohere: CohereConfiguration? = nil,
        grok: GrokConfiguration? = nil,
        aqua: AquaConfiguration? = nil,
        openAI: OpenAIConfiguration? = nil,
        meta: MetaConfiguration? = nil,
        gemini: GeminiConfiguration? = nil,
        mistral: MistralConfiguration? = nil,
        fishAudio: FishAudioConfiguration? = nil,
        urlSession: URLSession,
        elevenLabsRealtimeService: ElevenLabsService,
        openAIRealtimeService: OpenAIRealtimeService = OpenAIRealtimeService(),
        grokRealtimeService: GrokRealtimeService = GrokRealtimeService(),
        metaRealtimeService: MetaRealtimeService = MetaRealtimeService(),
        geminiRealtimeService: GeminiRealtimeService = GeminiRealtimeService(),
        mistralRealtimeService: MistralRealtimeService = MistralRealtimeService(),
        fishAudioRealtimeService: FishAudioRealtimeService = FishAudioRealtimeService()
    ) {
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.aqua = aqua
        self.openAI = openAI
        self.meta = meta
        self.gemini = gemini
        self.mistral = mistral
        self.fishAudio = fishAudio
        self.urlSession = SpeechTransport.session(copying: urlSession)
        self.elevenLabsRealtimeService = elevenLabsRealtimeService
        self.openAIRealtimeService = openAIRealtimeService
        self.grokRealtimeService = grokRealtimeService
        self.metaRealtimeService = metaRealtimeService
        self.geminiRealtimeService = geminiRealtimeService
        self.mistralRealtimeService = mistralRealtimeService
        self.fishAudioRealtimeService = fishAudioRealtimeService
        applyRealtimeConfig()
        applyOpenAIRealtimeConfig()
        applyGrokRealtimeConfig()
        applyMetaRealtimeConfig()
        applyGeminiRealtimeConfig()
        applyMistralRealtimeConfig()
        applyFishAudioRealtimeConfig()
    }

    private func applyRealtimeConfig() {
        invalidatePendingOperations()
        elevenLabsRealtimeService.credentialPolicy = credentialPolicy
        elevenLabsRealtimeService.setCredential(elevenLabs?.credential(for: .realtime) ?? .apiKey(""))
        elevenLabsRealtimeService.realtimeEndpoint = elevenLabs?.realtimeEndpoint
        elevenLabsRealtimeService.realtimeModelID = elevenLabs?.realtimeModelID ?? .scribeV3Live
        elevenLabsRealtimeService.options = elevenLabs?.realtimeOptions ?? ElevenLabsRealtimeOptions()
    }

    private func applyOpenAIRealtimeConfig() {
        invalidatePendingOperations()
        openAIRealtimeService.credentialPolicy = credentialPolicy
        openAIRealtimeService.setCredential(openAI?.credential(for: .realtime) ?? .apiKey(""))
        openAIRealtimeService.realtimeEndpoint = openAI?.realtimeEndpoint
        if let openAI {
            openAIRealtimeService.options = resolvedOpenAIRealtimeOptions(from: openAI)
        }
    }

    private func applyGrokRealtimeConfig() {
        invalidatePendingOperations()
        grokRealtimeService.credentialPolicy = credentialPolicy
        grokRealtimeService.setCredential(grok?.credential(for: .realtime) ?? .apiKey(""))
        grokRealtimeService.realtimeEndpoint = grok?.realtimeEndpoint
        if let grok {
            grokRealtimeService.options = grok.realtimeOptions
        }
    }

    private func applyMetaRealtimeConfig() {
        invalidatePendingOperations()
        metaRealtimeService.credentialPolicy = credentialPolicy
        metaRealtimeService.setCredential(meta?.credential(for: .realtime) ?? .apiKey(""))
        metaRealtimeService.realtimeEndpoint = meta?.realtimeEndpoint
        if let meta {
            metaRealtimeService.options = meta.realtimeOptions
        }
    }

    private func applyGeminiRealtimeConfig() {
        invalidatePendingOperations()
        geminiRealtimeService.credentialPolicy = credentialPolicy
        geminiRealtimeService.setCredential(gemini?.credential(for: .realtime) ?? .apiKey(""))
        geminiRealtimeService.realtimeEndpoint = gemini?.realtimeEndpoint
        if let gemini {
            geminiRealtimeService.options = resolvedGeminiRealtimeOptions(from: gemini)
        }
    }

    private func applyMistralRealtimeConfig() {
        invalidatePendingOperations()
        mistralRealtimeService.credentialPolicy = credentialPolicy
        mistralRealtimeService.setCredential(mistral?.credential(for: .realtime) ?? .apiKey(""))
        mistralRealtimeService.realtimeEndpoint = mistral?.realtimeEndpoint
        if let mistral {
            mistralRealtimeService.options = mistral.realtimeOptions
        }
    }

    private func applyFishAudioRealtimeConfig() {
        invalidatePendingOperations()
        fishAudioRealtimeService.credentialPolicy = credentialPolicy
        fishAudioRealtimeService.setCredential(fishAudio?.credential(for: .realtime) ?? .apiKey(""))
        fishAudioRealtimeService.realtimeEndpoint = fishAudio?.realtimeEndpoint
        if let fishAudio {
            fishAudioRealtimeService.options = fishAudio.realtimeOptions
        }
    }

    func resolvedOpenAIRealtimeOptions(from config: OpenAIConfiguration) -> OpenAIRealtimeSessionOptions {
        OpenAIRealtimeSessionOptions(
            sessionModelID: config.realtimeSessionModelID,
            transcriptionModelID: config.realtimeTranscriptionModelID,
            language: config.language,
            languages: config.languages,
            prompt: config.prompt,
            keywords: config.keywords,
            delay: config.realtimeDelay,
            commitInterval: config.realtimeCommitInterval
        )
    }

    /// Returns the Gemini realtime options a configuration implies.
    ///
    /// ``GeminiConfiguration/realtimeModelID`` is the single source of truth for
    /// the Gemini Live model, so it overrides
    /// ``GeminiRealtimeOptions/modelID`` on the configured options.
    func resolvedGeminiRealtimeOptions(from config: GeminiConfiguration) -> GeminiRealtimeOptions {
        var options = config.realtimeOptions
        options.modelID = config.realtimeModelID
        return options
    }
}
