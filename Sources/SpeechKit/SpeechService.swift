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
    public var cohere: CohereConfiguration?
    /// The Grok configuration used for Grok file transcription.
    public var grok: GrokConfiguration? {
        didSet { applyGrokRealtimeConfig() }
    }
    /// The Aqua configuration used for Aqua file transcription.
    public var aqua: AquaConfiguration?
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
    /// The Apple local Speech configuration used for realtime and file transcription.
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @available(watchOS, unavailable)
    public var apple: AppleSpeechConfiguration? {
        get { appleConfigurationStorage as? AppleSpeechConfiguration }
        set { appleConfigurationStorage = newValue }
    }

    let elevenLabsRealtimeService: ElevenLabsService
    let openAIRealtimeService: OpenAIRealtimeService
    let grokRealtimeService: GrokRealtimeService
    let metaRealtimeService: MetaRealtimeService
    let geminiRealtimeService: GeminiRealtimeService
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
        gemini: GeminiConfiguration? = nil
    ) {
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.aqua = aqua
        self.openAI = openAI
        self.meta = meta
        self.gemini = gemini
        self.elevenLabsRealtimeService = ElevenLabsService()
        self.openAIRealtimeService = OpenAIRealtimeService()
        self.grokRealtimeService = GrokRealtimeService()
        self.metaRealtimeService = MetaRealtimeService()
        self.geminiRealtimeService = GeminiRealtimeService()
        self.urlSession = .shared
        applyRealtimeConfig()
        applyOpenAIRealtimeConfig()
        applyGrokRealtimeConfig()
        applyMetaRealtimeConfig()
        applyGeminiRealtimeConfig()
    }

    /// Creates a speech service with Apple local Speech configuration.
    ///
    /// Use this initializer only on OS versions that expose `SpeechAnalyzer`
    /// and `SpeechTranscriber`. The base ``SpeechService/init(elevenLabs:cohere:grok:aqua:openAI:meta:gemini:)``
    /// initializer remains available for the package's lower deployment targets.
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @available(watchOS, unavailable)
    public convenience init(
        elevenLabs: ElevenLabsConfiguration? = nil,
        cohere: CohereConfiguration? = nil,
        grok: GrokConfiguration? = nil,
        aqua: AquaConfiguration? = nil,
        openAI: OpenAIConfiguration? = nil,
        meta: MetaConfiguration? = nil,
        gemini: GeminiConfiguration? = nil,
        apple: AppleSpeechConfiguration? = nil
    ) {
        self.init(
            elevenLabs: elevenLabs,
            cohere: cohere,
            grok: grok,
            aqua: aqua,
            openAI: openAI,
            meta: meta,
            gemini: gemini
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
        urlSession: URLSession,
        elevenLabsRealtimeService: ElevenLabsService,
        openAIRealtimeService: OpenAIRealtimeService = OpenAIRealtimeService(),
        grokRealtimeService: GrokRealtimeService = GrokRealtimeService(),
        metaRealtimeService: MetaRealtimeService = MetaRealtimeService(),
        geminiRealtimeService: GeminiRealtimeService = GeminiRealtimeService()
    ) {
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.aqua = aqua
        self.openAI = openAI
        self.meta = meta
        self.gemini = gemini
        self.urlSession = urlSession
        self.elevenLabsRealtimeService = elevenLabsRealtimeService
        self.openAIRealtimeService = openAIRealtimeService
        self.grokRealtimeService = grokRealtimeService
        self.metaRealtimeService = metaRealtimeService
        self.geminiRealtimeService = geminiRealtimeService
        applyRealtimeConfig()
        applyOpenAIRealtimeConfig()
        applyGrokRealtimeConfig()
        applyMetaRealtimeConfig()
        applyGeminiRealtimeConfig()
    }

    private func applyRealtimeConfig() {
        elevenLabsRealtimeService.credential = elevenLabs?.credential ?? .apiKey("")
        elevenLabsRealtimeService.realtimeEndpoint = elevenLabs?.realtimeEndpoint
        elevenLabsRealtimeService.realtimeModelID = elevenLabs?.realtimeModelID ?? .scribeV2Realtime
    }

    private func applyOpenAIRealtimeConfig() {
        openAIRealtimeService.credential = openAI?.credential ?? .apiKey("")
        openAIRealtimeService.realtimeEndpoint = openAI?.realtimeEndpoint
        if let openAI {
            openAIRealtimeService.options = resolvedOpenAIRealtimeOptions(from: openAI)
        }
    }

    private func applyGrokRealtimeConfig() {
        grokRealtimeService.credential = grok?.credential ?? .apiKey("")
        grokRealtimeService.realtimeEndpoint = grok?.realtimeEndpoint
        if let grok {
            grokRealtimeService.options = grok.realtimeOptions
        }
    }

    private func applyMetaRealtimeConfig() {
        metaRealtimeService.credential = meta?.credential ?? .apiKey("")
        metaRealtimeService.realtimeEndpoint = meta?.realtimeEndpoint
        if let meta {
            metaRealtimeService.options = meta.realtimeOptions
        }
    }

    private func applyGeminiRealtimeConfig() {
        geminiRealtimeService.credential = gemini?.credential ?? .apiKey("")
        geminiRealtimeService.realtimeEndpoint = gemini?.realtimeEndpoint
        if let gemini {
            geminiRealtimeService.options = resolvedGeminiRealtimeOptions(from: gemini)
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
