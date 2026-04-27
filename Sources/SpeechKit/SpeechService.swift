import Foundation
import SwiftUI

public struct ElevenLabsConfig: Sendable, Equatable {
    public var apiKey: String
    public var realtimeModelId: ElevenLabsModelID
    public var fileModelId: ElevenLabsModelID

    public init(
        apiKey: String,
        realtimeModelId: ElevenLabsModelID = .scribeV2Realtime,
        fileModelId: ElevenLabsModelID = .scribeV1
    ) {
        self.apiKey = apiKey
        self.realtimeModelId = realtimeModelId
        self.fileModelId = fileModelId
    }
}

public struct CohereConfig: Sendable, Equatable {
    public var apiKey: String
    public var fileModelId: CohereModelID
    public var language: String
    public var temperature: Double?

    public init(
        apiKey: String,
        fileModelId: CohereModelID = .transcribe032026,
        language: String = "en",
        temperature: Double? = nil
    ) {
        self.apiKey = apiKey
        self.fileModelId = fileModelId
        self.language = language
        self.temperature = temperature
    }
}

public struct GrokConfig: Sendable, Equatable {
    public var apiKey: String
    public var modelId: GrokModelID
    public var language: String?
    public var format: Bool
    public var multichannel: Bool
    public var diarize: Bool
    public var timestampGranularities: [GrokTimestampGranularity]
    public var timeoutInterval: TimeInterval

    public init(
        apiKey: String,
        modelId: GrokModelID = .stt,
        language: String? = nil,
        format: Bool = false,
        multichannel: Bool = false,
        diarize: Bool = false,
        timestampGranularities: [GrokTimestampGranularity] = [.word],
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.apiKey = apiKey
        self.modelId = modelId
        self.language = language
        self.format = format
        self.multichannel = multichannel
        self.diarize = diarize
        self.timestampGranularities = timestampGranularities
        self.timeoutInterval = timeoutInterval
    }
}

public enum SpeechFileProvider: String, Sendable, CaseIterable {
    case elevenLabs
    case cohere
    case grok
}

public enum SpeechFileTranscriptionOptions: Sendable, Equatable {
    case elevenLabs(modelId: ElevenLabsModelID? = nil)
    case cohere(modelId: CohereModelID? = nil, language: String? = nil, temperature: Double? = nil)
    case grok(
        modelId: GrokModelID? = nil,
        language: String? = nil,
        format: Bool? = nil,
        multichannel: Bool? = nil,
        channels: Int? = nil,
        diarize: Bool? = nil,
        timestampGranularities: [GrokTimestampGranularity]? = nil,
        audioFormat: GrokAudioFormat? = nil,
        sampleRate: Int? = nil,
        timeoutInterval: TimeInterval? = nil
    )

    var provider: SpeechFileProvider {
        switch self {
        case .elevenLabs:
            return .elevenLabs
        case .cohere:
            return .cohere
        case .grok:
            return .grok
        }
    }
}

public enum SpeechError: Error, LocalizedError, Sendable, Equatable {
    case providerNotConfigured(SpeechFileProvider)
    case unsupportedCapability(provider: SpeechFileProvider, capability: String)
    case invalidOptionsForProvider(expected: SpeechFileProvider, received: SpeechFileProvider)
    case invalidResponse(provider: SpeechFileProvider)
    case uploadFailed(provider: SpeechFileProvider, reason: String)
    case decodingFailed(provider: SpeechFileProvider, reason: String)
    case providerFailure(provider: SpeechFileProvider, reason: String)

    public var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let provider):
            return "\(provider.rawValue) is not configured."
        case .unsupportedCapability(let provider, let capability):
            return "\(provider.rawValue) does not support \(capability)."
        case .invalidOptionsForProvider(let expected, let received):
            return "Received \(received.rawValue) options for \(expected.rawValue)."
        case .invalidResponse(let provider):
            return "Received an invalid response from \(provider.rawValue)."
        case .uploadFailed(let provider, let reason):
            return "\(provider.rawValue) upload failed: \(reason)"
        case .decodingFailed(let provider, let reason):
            return "Failed to decode \(provider.rawValue) response: \(reason)"
        case .providerFailure(let provider, let reason):
            return "\(provider.rawValue) request failed: \(reason)"
        }
    }
}

@Observable
@MainActor
public final class SpeechService {
    public var elevenLabs: ElevenLabsConfig? {
        didSet { applyRealtimeConfig() }
    }
    public var cohere: CohereConfig?
    public var grok: GrokConfig?

    private let elevenLabsRealtimeService: ElevenLabsService
    private let urlSession: URLSession
    private var fallbackConnectionState: ElevenLabsService.ConnectionState?
    private var fallbackLastError: Error?

    public var connectionState: ElevenLabsService.ConnectionState {
        fallbackConnectionState ?? elevenLabsRealtimeService.connectionState
    }

    public var partialTranscript: String {
        elevenLabsRealtimeService.partialTranscript
    }

    public var committedTranscripts: [ElevenLabsService.TranscriptEntry] {
        elevenLabsRealtimeService.committedTranscripts
    }

    public var lastError: Error? {
        fallbackLastError ?? elevenLabsRealtimeService.lastError
    }

    public var fullTranscript: String {
        elevenLabsRealtimeService.fullTranscript
    }

    public init(
        elevenLabs: ElevenLabsConfig? = nil,
        cohere: CohereConfig? = nil,
        grok: GrokConfig? = nil
    ) {
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.elevenLabsRealtimeService = ElevenLabsService()
        self.urlSession = .shared
        applyRealtimeConfig()
    }

    @available(*, deprecated, message: "Use init(elevenLabs:cohere:grok:) with provider-specific configuration.")
    public convenience init(
        apiKey: String,
        modelId: ElevenLabsModelID = .scribeV2Realtime
    ) {
        self.init(
            elevenLabs: ElevenLabsConfig(
                apiKey: apiKey,
                realtimeModelId: modelId,
                fileModelId: .scribeV1
            )
        )
    }

    init(
        elevenLabs: ElevenLabsConfig? = nil,
        cohere: CohereConfig? = nil,
        grok: GrokConfig? = nil,
        urlSession: URLSession,
        elevenLabsRealtimeService: ElevenLabsService
    ) {
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.urlSession = urlSession
        self.elevenLabsRealtimeService = elevenLabsRealtimeService
        applyRealtimeConfig()
    }

    public func startListening() async {
        guard let elevenLabs else {
            fallbackConnectionState = .error("ElevenLabs is not configured")
            fallbackLastError = SpeechError.providerNotConfigured(.elevenLabs)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        elevenLabsRealtimeService.apiKey = elevenLabs.apiKey
        elevenLabsRealtimeService.modelId = elevenLabs.realtimeModelId
        await elevenLabsRealtimeService.startListening()
    }

    public func stopListening() async {
        fallbackConnectionState = nil
        fallbackLastError = nil
        await elevenLabsRealtimeService.stopListening()
    }

    public func clearTranscripts() {
        fallbackConnectionState = nil
        fallbackLastError = nil
        elevenLabsRealtimeService.clearTranscripts()
    }

    public func transcribeAudioFile(
        provider: SpeechFileProvider,
        file: URL,
        options: SpeechFileTranscriptionOptions? = nil
    ) async throws -> String {
        switch provider {
        case .elevenLabs:
            guard let elevenLabs else {
                throw SpeechError.providerNotConfigured(.elevenLabs)
            }
            try validate(options: options, for: .elevenLabs)
            let resolvedModelId = resolvedElevenLabsModelId(from: options, config: elevenLabs)
            let client = ElevenLabsFileTranscriptionClient(apiKey: elevenLabs.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(file: file, modelId: resolvedModelId)
            } catch {
                throw wrap(error, for: .elevenLabs)
            }

        case .cohere:
            guard let cohere else {
                throw SpeechError.providerNotConfigured(.cohere)
            }
            try validate(options: options, for: .cohere)
            let resolvedOptions = resolvedCohereOptions(from: options, config: cohere)
            let client = CohereFileTranscriptionClient(apiKey: cohere.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(
                    file: file,
                    modelId: resolvedOptions.modelId,
                    language: resolvedOptions.language,
                    temperature: resolvedOptions.temperature
                )
            } catch {
                throw wrap(error, for: .cohere)
            }

        case .grok:
            guard let grok else {
                throw SpeechError.providerNotConfigured(.grok)
            }
            try validate(options: options, for: .grok)
            let resolvedOptions = resolvedGrokOptions(from: options, config: grok)
            let client = GrokFileTranscriptionClient(apiKey: grok.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(
                    file: file,
                    options: resolvedOptions
                )
            } catch {
                throw wrap(error, for: .grok)
            }
        }
    }

    public func transcribeAudioFile(
        provider: SpeechFileProvider,
        securityScopedURL: URL,
        options: SpeechFileTranscriptionOptions? = nil
    ) async throws -> String {
        let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw SpeechError.providerFailure(provider: provider, reason: "Failed to access security-scoped resource.")
        }
        defer { securityScopedURL.stopAccessingSecurityScopedResource() }
        return try await transcribeAudioFile(provider: provider, file: securityScopedURL, options: options)
    }

    public func transcribeGrokAudioFile(
        file: URL,
        options: GrokFileTranscriptionOptions? = nil
    ) async throws -> GrokFileTranscriptionResponse {
        guard let grok else {
            throw SpeechError.providerNotConfigured(.grok)
        }

        let client = GrokFileTranscriptionClient(apiKey: grok.apiKey, urlSession: urlSession)
        let resolvedOptions = options ?? GrokFileTranscriptionOptions(
            modelId: grok.modelId,
            language: grok.language,
            format: grok.format,
            multichannel: grok.multichannel,
            diarize: grok.diarize,
            timestampGranularities: grok.timestampGranularities,
            timeoutInterval: grok.timeoutInterval
        )

        do {
            return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
        } catch {
            throw wrap(error, for: .grok)
        }
    }

    public func transcribeGrokAudioFile(
        securityScopedURL: URL,
        options: GrokFileTranscriptionOptions? = nil
    ) async throws -> GrokFileTranscriptionResponse {
        let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw SpeechError.providerFailure(provider: .grok, reason: "Failed to access security-scoped resource.")
        }
        defer { securityScopedURL.stopAccessingSecurityScopedResource() }
        return try await transcribeGrokAudioFile(file: securityScopedURL, options: options)
    }

    private func applyRealtimeConfig() {
        elevenLabsRealtimeService.apiKey = elevenLabs?.apiKey ?? ""
        elevenLabsRealtimeService.modelId = elevenLabs?.realtimeModelId ?? .scribeV2Realtime
    }

    private func validate(options: SpeechFileTranscriptionOptions?, for provider: SpeechFileProvider) throws {
        guard let options else { return }
        guard options.provider == provider else {
            throw SpeechError.invalidOptionsForProvider(expected: provider, received: options.provider)
        }
    }

    private func resolvedElevenLabsModelId(
        from options: SpeechFileTranscriptionOptions?,
        config: ElevenLabsConfig
    ) -> ElevenLabsModelID {
        guard case .elevenLabs(let modelId) = options else {
            return config.fileModelId
        }
        return modelId ?? config.fileModelId
    }

    private func resolvedCohereOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: CohereConfig
    ) -> (modelId: CohereModelID, language: String, temperature: Double?) {
        guard case .cohere(let modelId, let language, let temperature) = options else {
            return (config.fileModelId, config.language, config.temperature)
        }

        return (
            modelId ?? config.fileModelId,
            language ?? config.language,
            temperature ?? config.temperature
        )
    }

    private func resolvedGrokOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: GrokConfig
    ) -> GrokFileTranscriptionOptions {
        guard case .grok(
            let modelId,
            let language,
            let format,
            let multichannel,
            let channels,
            let diarize,
            let timestampGranularities,
            let audioFormat,
            let sampleRate,
            let timeoutInterval
        ) = options else {
            return GrokFileTranscriptionOptions(
                modelId: config.modelId,
                language: config.language,
                format: config.format,
                multichannel: config.multichannel,
                channels: nil,
                diarize: config.diarize,
                timestampGranularities: config.timestampGranularities,
                audioFormat: nil,
                sampleRate: nil,
                timeoutInterval: config.timeoutInterval
            )
        }

        return GrokFileTranscriptionOptions(
            modelId: modelId ?? config.modelId,
            language: language ?? config.language,
            format: format ?? config.format,
            multichannel: multichannel ?? config.multichannel,
            channels: channels,
            diarize: diarize ?? config.diarize,
            timestampGranularities: timestampGranularities ?? config.timestampGranularities,
            audioFormat: audioFormat,
            sampleRate: sampleRate,
            timeoutInterval: timeoutInterval ?? config.timeoutInterval
        )
    }

    private func wrap(_ error: Error, for provider: SpeechFileProvider) -> SpeechError {
        if let speechError = error as? SpeechError {
            return speechError
        }

        if let urlError = error as? URLError {
            if urlError.code == .timedOut {
                return .providerFailure(provider: provider, reason: "The request timed out. Try a shorter audio file or increase the provider timeout.")
            }
            return .providerFailure(provider: provider, reason: urlError.localizedDescription)
        }

        if let elevenLabsError = error as? ElevenLabsError {
            switch elevenLabsError {
            case .decodingFailed(let reason):
                return .decodingFailed(provider: provider, reason: reason)
            case .uploadFailed(let reason), .connectionFailed(let reason):
                return .uploadFailed(provider: provider, reason: reason)
            default:
                return .providerFailure(provider: provider, reason: elevenLabsError.localizedDescription)
            }
        }

        return .providerFailure(provider: provider, reason: error.localizedDescription)
    }
}
