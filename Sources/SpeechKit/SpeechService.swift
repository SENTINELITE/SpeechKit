import Foundation
import SwiftUI

/// Configuration for ElevenLabs realtime and file transcription.
public struct ElevenLabsConfig: Sendable, Equatable {
    /// The ElevenLabs API key used for realtime and file transcription requests.
    public var apiKey: String
    /// The ElevenLabs model used by ``SpeechService/startListening()``.
    public var realtimeModelID: ElevenLabsModelID
    /// The ElevenLabs model used by file transcription APIs.
    public var fileModelID: ElevenLabsModelID

    /// Creates an ElevenLabs configuration.
    public init(
        apiKey: String,
        realtimeModelID: ElevenLabsModelID = .scribeV2Realtime,
        fileModelID: ElevenLabsModelID = .scribeV1
    ) {
        self.apiKey = apiKey
        self.realtimeModelID = realtimeModelID
        self.fileModelID = fileModelID
    }
}

/// Configuration for Cohere file transcription.
public struct CohereConfig: Sendable, Equatable {
    /// The Cohere API key used for file transcription requests.
    public var apiKey: String
    /// The Cohere transcription model used for file uploads.
    public var fileModelID: CohereModelID
    /// The language hint sent with Cohere transcription requests.
    public var language: CohereLanguage
    /// An optional model temperature for transcription output.
    public var temperature: Double?

    /// Creates a Cohere configuration with a typed language value.
    public init(
        apiKey: String,
        fileModelID: CohereModelID = .transcribe032026,
        language: CohereLanguage = .english,
        temperature: Double? = nil
    ) {
        self.apiKey = apiKey
        self.fileModelID = fileModelID
        self.language = language
        self.temperature = temperature
    }

    /// Creates a Cohere configuration from a raw language code.
    ///
    /// - Throws: ``SpeechError/providerFailure(provider:reason:)`` when `languageCode` is not supported.
    public init(
        apiKey: String,
        fileModelID: CohereModelID = .transcribe032026,
        languageCode: String,
        temperature: Double? = nil
    ) throws {
        guard let language = CohereLanguage(rawValue: languageCode) else {
            throw SpeechError.providerFailure(provider: .cohere, reason: "Unsupported language: \(languageCode).")
        }
        self.init(apiKey: apiKey, fileModelID: fileModelID, language: language, temperature: temperature)
    }
}

/// Configuration for Grok file transcription.
public struct GrokConfig: Sendable, Equatable {
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
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.language = language
        self.format = format
        self.multichannel = multichannel
        self.diarize = diarize
        self.timestampGranularities = timestampGranularities
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
            timeoutInterval: timeoutInterval
        )
    }
}

/// Configuration for Aqua file transcription.
public struct AquaConfig: Sendable, Equatable {
    /// The Aqua API key used for file transcription requests.
    public var apiKey: String
    /// The Aqua transcription model used for file uploads.
    public var fileModelID: AquaModelID
    /// An optional language hint.
    public var language: AquaLanguage?

    /// Creates an Aqua configuration with a typed language value.
    public init(
        apiKey: String,
        fileModelID: AquaModelID = .avalonV15,
        language: AquaLanguage? = nil
    ) {
        self.apiKey = apiKey
        self.fileModelID = fileModelID
        self.language = language
    }

    /// Creates an Aqua configuration from an optional raw language code.
    ///
    /// - Throws: ``SpeechError/providerFailure(provider:reason:)`` when `languageCode` is not supported.
    public init(
        apiKey: String,
        fileModelID: AquaModelID = .avalonV15,
        languageCode: String?
    ) throws {
        let language = try languageCode.map { languageCode in
            guard let language = AquaLanguage(rawValue: languageCode) else {
                throw SpeechError.providerFailure(provider: .aqua, reason: "Unsupported language: \(languageCode).")
            }
            return language
        }
        self.init(apiKey: apiKey, fileModelID: fileModelID, language: language)
    }
}

/// A provider that can transcribe uploaded audio files.
public enum SpeechFileProvider: String, Sendable, CaseIterable {
    /// ElevenLabs Scribe file transcription.
    case elevenLabs
    /// Aqua Avalon file transcription.
    case aqua
    /// Cohere Transcribe file transcription.
    case cohere
    /// Grok speech-to-text file transcription.
    case grok
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

    var provider: SpeechFileProvider {
        switch self {
        case .elevenLabs:
            return .elevenLabs
        case .aqua:
            return .aqua
        case .cohere:
            return .cohere
        case .grok:
            return .grok
        }
    }
}

/// Errors returned by provider-neutral SpeechKit APIs.
public enum SpeechError: Error, LocalizedError, Sendable, Equatable {
    /// The requested provider has no configuration on the service.
    case providerNotConfigured(SpeechFileProvider)
    /// The requested provider does not support the requested capability.
    case unsupportedCapability(provider: SpeechFileProvider, capability: String)
    /// The request used options for a different provider.
    case invalidOptionsForProvider(expected: SpeechFileProvider, received: SpeechFileProvider)
    /// The provider returned a response that SpeechKit could not interpret.
    case invalidResponse(provider: SpeechFileProvider)
    /// The provider rejected or failed a file upload.
    case uploadFailed(provider: SpeechFileProvider, reason: String)
    /// SpeechKit could not decode the provider response.
    case decodingFailed(provider: SpeechFileProvider, reason: String)
    /// The provider request failed for a reason that does not fit a narrower case.
    case providerFailure(provider: SpeechFileProvider, reason: String)

    /// A localized description of the error.
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

/// A SwiftUI-observable service for realtime microphone transcription and audio file transcription.
@Observable
@MainActor
public final class SpeechService {
    /// The ElevenLabs configuration used for realtime and ElevenLabs file transcription.
    public var elevenLabs: ElevenLabsConfig? {
        didSet { applyRealtimeConfig() }
    }
    /// The Cohere configuration used for Cohere file transcription.
    public var cohere: CohereConfig?
    /// The Grok configuration used for Grok file transcription.
    public var grok: GrokConfig?
    /// The Aqua configuration used for Aqua file transcription.
    public var aqua: AquaConfig?

    private let elevenLabsRealtimeService: ElevenLabsService
    private let urlSession: URLSession
    private var fallbackConnectionState: ElevenLabsService.ConnectionState?
    private var fallbackLastError: Error?

    /// The current realtime ElevenLabs connection state.
    public var connectionState: ElevenLabsService.ConnectionState {
        fallbackConnectionState ?? elevenLabsRealtimeService.connectionState
    }

    /// The latest partial realtime transcript text.
    public var partialTranscript: String {
        elevenLabsRealtimeService.partialTranscript
    }

    /// The committed realtime transcript entries.
    public var committedTranscripts: [ElevenLabsService.TranscriptEntry] {
        elevenLabsRealtimeService.committedTranscripts
    }

    /// The most recent realtime transcription error, if any.
    public var lastError: Error? {
        fallbackLastError ?? elevenLabsRealtimeService.lastError
    }

    /// The committed realtime transcript text joined with spaces.
    public var fullTranscript: String {
        elevenLabsRealtimeService.fullTranscript
    }

    /// Creates a speech service with any provider configurations your app needs.
    public init(
        elevenLabs: ElevenLabsConfig? = nil,
        cohere: CohereConfig? = nil,
        grok: GrokConfig? = nil,
        aqua: AquaConfig? = nil
    ) {
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.aqua = aqua
        self.elevenLabsRealtimeService = ElevenLabsService()
        self.urlSession = .shared
        applyRealtimeConfig()
    }

    init(
        elevenLabs: ElevenLabsConfig? = nil,
        cohere: CohereConfig? = nil,
        grok: GrokConfig? = nil,
        aqua: AquaConfig? = nil,
        urlSession: URLSession,
        elevenLabsRealtimeService: ElevenLabsService
    ) {
        self.elevenLabs = elevenLabs
        self.cohere = cohere
        self.grok = grok
        self.aqua = aqua
        self.urlSession = urlSession
        self.elevenLabsRealtimeService = elevenLabsRealtimeService
        applyRealtimeConfig()
    }

    /// Starts realtime microphone transcription with the configured ElevenLabs provider.
    public func startListening() async {
        guard let elevenLabs else {
            fallbackConnectionState = .error("ElevenLabs is not configured")
            fallbackLastError = SpeechError.providerNotConfigured(.elevenLabs)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        elevenLabsRealtimeService.apiKey = elevenLabs.apiKey
        elevenLabsRealtimeService.modelID = elevenLabs.realtimeModelID
        await elevenLabsRealtimeService.startListening()
    }

    /// Stops realtime microphone transcription and disconnects from ElevenLabs.
    public func stopListening() async {
        fallbackConnectionState = nil
        fallbackLastError = nil
        await elevenLabsRealtimeService.stopListening()
    }

    /// Clears committed and partial realtime transcript text.
    public func clearTranscripts() {
        fallbackConnectionState = nil
        fallbackLastError = nil
        elevenLabsRealtimeService.clearTranscripts()
    }

    /// Transcribes an audio file with a configured provider.
    ///
    /// - Throws: ``SpeechError`` when the provider is missing, options do not match the provider, upload validation fails, or the provider request fails.
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
            let resolvedModelID = resolvedElevenLabsModelID(from: options, config: elevenLabs)
            let client = ElevenLabsFileTranscriptionClient(apiKey: elevenLabs.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(file: file, modelID: resolvedModelID)
            } catch {
                throw wrap(error, for: .elevenLabs)
            }

        case .aqua:
            guard let aqua else {
                throw SpeechError.providerNotConfigured(.aqua)
            }
            try validate(options: options, for: .aqua)
            let resolvedOptions = resolvedAquaOptions(from: options, config: aqua)
            let client = AquaFileTranscriptionClient(apiKey: aqua.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
            } catch {
                throw wrap(error, for: .aqua)
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
                    modelID: resolvedOptions.modelID,
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

    /// Transcribes a security-scoped audio file URL with a configured provider.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, the provider is missing, options do not match the provider, upload validation fails, or the provider request fails.
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

    /// Transcribes an audio file with Aqua and returns Aqua's detailed response.
    ///
    /// - Throws: ``SpeechError`` when Aqua is missing, upload validation fails, or the provider request fails.
    public func transcribeAquaAudioFile(
        file: URL,
        options: AquaFileTranscriptionOptions? = nil
    ) async throws -> AquaFileTranscriptionResponse {
        guard let aqua else {
            throw SpeechError.providerNotConfigured(.aqua)
        }

        let client = AquaFileTranscriptionClient(apiKey: aqua.apiKey, urlSession: urlSession)
        let resolvedOptions = options ?? AquaFileTranscriptionOptions(
            modelID: aqua.fileModelID,
            language: aqua.language
        )

        do {
            return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
        } catch {
            throw wrap(error, for: .aqua)
        }
    }

    /// Transcribes a security-scoped audio file URL with Aqua and returns Aqua's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Aqua is missing, upload validation fails, or the provider request fails.
    public func transcribeAquaAudioFile(
        securityScopedURL: URL,
        options: AquaFileTranscriptionOptions? = nil
    ) async throws -> AquaFileTranscriptionResponse {
        let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw SpeechError.providerFailure(provider: .aqua, reason: "Failed to access security-scoped resource.")
        }
        defer { securityScopedURL.stopAccessingSecurityScopedResource() }
        return try await transcribeAquaAudioFile(file: securityScopedURL, options: options)
    }

    /// Transcribes an audio file with Grok and returns Grok's detailed response.
    ///
    /// - Throws: ``SpeechError`` when Grok is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeGrokAudioFile(
        file: URL,
        options: GrokFileTranscriptionOptions? = nil
    ) async throws -> GrokFileTranscriptionResponse {
        guard let grok else {
            throw SpeechError.providerNotConfigured(.grok)
        }

        let client = GrokFileTranscriptionClient(apiKey: grok.apiKey, urlSession: urlSession)
        let resolvedOptions = options ?? GrokFileTranscriptionOptions(
            modelID: grok.modelID,
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

    /// Transcribes a security-scoped audio file URL with Grok and returns Grok's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Grok is missing, upload validation fails, option validation fails, or the provider request fails.
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
        elevenLabsRealtimeService.modelID = elevenLabs?.realtimeModelID ?? .scribeV2Realtime
    }

    private func validate(options: SpeechFileTranscriptionOptions?, for provider: SpeechFileProvider) throws {
        guard let options else { return }
        guard options.provider == provider else {
            throw SpeechError.invalidOptionsForProvider(expected: provider, received: options.provider)
        }
    }

    private func resolvedElevenLabsModelID(
        from options: SpeechFileTranscriptionOptions?,
        config: ElevenLabsConfig
    ) -> ElevenLabsModelID {
        guard case .elevenLabs(let modelID) = options else {
            return config.fileModelID
        }
        return modelID ?? config.fileModelID
    }

    private func resolvedAquaOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: AquaConfig
    ) -> AquaFileTranscriptionOptions {
        guard case .aqua(let modelID, let language) = options else {
            return AquaFileTranscriptionOptions(modelID: config.fileModelID, language: config.language)
        }

        return AquaFileTranscriptionOptions(
            modelID: modelID ?? config.fileModelID,
            language: language ?? config.language
        )
    }

    private func resolvedCohereOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: CohereConfig
    ) -> (modelID: CohereModelID, language: CohereLanguage, temperature: Double?) {
        guard case .cohere(let modelID, let language, let temperature) = options else {
            return (config.fileModelID, config.language, config.temperature)
        }

        return (
            modelID ?? config.fileModelID,
            language ?? config.language,
            temperature ?? config.temperature
        )
    }

    private func resolvedGrokOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: GrokConfig
    ) -> GrokFileTranscriptionOptions {
        guard case .grok(
            let modelID,
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
                modelID: config.modelID,
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
            modelID: modelID ?? config.modelID,
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
