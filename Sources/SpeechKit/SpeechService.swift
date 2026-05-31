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

    let elevenLabsRealtimeService: ElevenLabsService
    let openAIRealtimeService: OpenAIRealtimeService
    let grokRealtimeService: GrokRealtimeService
    let urlSession: URLSession
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
        openAI: OpenAIConfiguration? = nil
    ) {
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.aqua = aqua
        self.openAI = openAI
        self.elevenLabsRealtimeService = ElevenLabsService()
        self.openAIRealtimeService = OpenAIRealtimeService()
        self.grokRealtimeService = GrokRealtimeService()
        self.urlSession = .shared
        applyRealtimeConfig()
        applyOpenAIRealtimeConfig()
        applyGrokRealtimeConfig()
    }

    init(
        elevenLabs: ElevenLabsConfiguration? = nil,
        cohere: CohereConfiguration? = nil,
        grok: GrokConfiguration? = nil,
        aqua: AquaConfiguration? = nil,
        openAI: OpenAIConfiguration? = nil,
        urlSession: URLSession,
        elevenLabsRealtimeService: ElevenLabsService,
        openAIRealtimeService: OpenAIRealtimeService = OpenAIRealtimeService(),
        grokRealtimeService: GrokRealtimeService = GrokRealtimeService()
    ) {
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.aqua = aqua
        self.openAI = openAI
        self.urlSession = urlSession
        self.elevenLabsRealtimeService = elevenLabsRealtimeService
        self.openAIRealtimeService = openAIRealtimeService
        self.grokRealtimeService = grokRealtimeService
        applyRealtimeConfig()
        applyOpenAIRealtimeConfig()
        applyGrokRealtimeConfig()
    }

    private func applyRealtimeConfig() {
        elevenLabsRealtimeService.apiKey = elevenLabs?.apiKey ?? ""
        elevenLabsRealtimeService.realtimeModelID = elevenLabs?.realtimeModelID ?? .scribeV2Realtime
    }

    private func applyOpenAIRealtimeConfig() {
        openAIRealtimeService.apiKey = openAI?.apiKey ?? ""
        if let openAI {
            openAIRealtimeService.options = resolvedOpenAIRealtimeOptions(from: openAI)
        }
    }

    private func applyGrokRealtimeConfig() {
        grokRealtimeService.apiKey = grok?.apiKey ?? ""
        if let grok {
            grokRealtimeService.options = grok.realtimeOptions
        }
    }

    func resolvedOpenAIRealtimeOptions(from config: OpenAIConfiguration) -> OpenAIRealtimeSessionOptions {
        OpenAIRealtimeSessionOptions(
            sessionModelID: config.realtimeSessionModelID,
            transcriptionModelID: config.realtimeTranscriptionModelID,
            language: config.language,
            delay: config.realtimeDelay,
            commitInterval: config.realtimeCommitInterval
        )
    }
}
