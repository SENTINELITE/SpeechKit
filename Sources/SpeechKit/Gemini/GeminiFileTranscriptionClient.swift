import Foundation

/// Gemini file transcription model identifiers supported by SpeechKit.
public enum GeminiFileTranscriptionModelID: String, Sendable, CaseIterable {
    /// Gemini 3.5 Transcribe.
    case transcribe35 = "gemini-3.5-transcribe"
}

/// Gemini Live transcription model identifiers supported by SpeechKit.
public enum GeminiRealtimeModelID: String, Sendable, CaseIterable {
    /// Gemini 3.5 Transcribe Live.
    case transcribeLive35 = "gemini-3.5-transcribe-live"
}

/// Transcription modes supported by Gemini.
public enum GeminiTranscriptionMode: String, Sendable, CaseIterable {
    /// Transcribe every spoken word, including fillers.
    ///
    /// Only this mode supports speaker diarization and word timestamps.
    case verbatim
    /// Remove fillers and apply readable formatting.
    case smart
}

/// Timestamp granularities supported by Gemini transcription.
public enum GeminiTimestampGranularity: String, Sendable, CaseIterable {
    /// Word-level timestamps.
    case word
}

/// The way SpeechKit sends audio to Gemini for file transcription.
public enum GeminiFileUploadStrategy: Sendable, Equatable {
    /// Send the audio inline when it is below the inline threshold, otherwise upload it with the Files API.
    case automatic
    /// Always send base64-encoded audio inline with the transcription request.
    case inline
    /// Always upload the audio with the Files API and reference the resulting file URI.
    case filesAPI
}

/// The way Gemini processes a file transcription request.
public enum GeminiProcessingMode: Sendable, Equatable {
    /// Wait for the transcription response on the original request.
    case synchronous
    /// Start a background interaction and poll it at the given interval, in seconds.
    ///
    /// Use this for long recordings, because a synchronous request for an hour
    /// of audio can outlast the request timeout.
    case background(pollInterval: TimeInterval)
}

/// Options for a Gemini file transcription request.
public struct GeminiFileTranscriptionOptions: Sendable, Equatable {
    /// The Gemini transcription model to use.
    public var modelID: GeminiFileTranscriptionModelID
    /// BCP-47 language hints, or an empty array to let Gemini detect the language.
    public var languageCodes: [String]
    /// Literal terms that may appear in the recording.
    ///
    /// Gemini rejects a custom vocabulary combined with diarization or word timestamps.
    public var customVocabulary: [String]
    /// The transcription mode for the request.
    public var mode: GeminiTranscriptionMode
    /// A Boolean value that indicates whether Gemini should identify speakers.
    public var diarize: Bool
    /// The timestamp granularities to request.
    public var timestampGranularities: [GeminiTimestampGranularity]
    /// The way SpeechKit sends the audio to Gemini.
    public var uploadStrategy: GeminiFileUploadStrategy
    /// The file size, in bytes, above which ``GeminiFileUploadStrategy/automatic`` switches to the Files API.
    public var inlineUploadThresholdBytes: Int64
    /// The way Gemini processes the request.
    public var processingMode: GeminiProcessingMode
    /// The network timeout for the request.
    public var timeoutInterval: TimeInterval

    /// Creates Gemini file transcription options.
    public init(
        modelID: GeminiFileTranscriptionModelID = .transcribe35,
        languageCodes: [String] = [],
        customVocabulary: [String] = [],
        mode: GeminiTranscriptionMode = .verbatim,
        diarize: Bool = false,
        timestampGranularities: [GeminiTimestampGranularity] = [],
        uploadStrategy: GeminiFileUploadStrategy = .automatic,
        inlineUploadThresholdBytes: Int64 = 20 * 1024 * 1024,
        processingMode: GeminiProcessingMode = .synchronous,
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.modelID = modelID
        self.languageCodes = languageCodes
        self.customVocabulary = customVocabulary
        self.mode = mode
        self.diarize = diarize
        self.timestampGranularities = timestampGranularities
        self.uploadStrategy = uploadStrategy
        self.inlineUploadThresholdBytes = inlineUploadThresholdBytes
        self.processingMode = processingMode
        self.timeoutInterval = timeoutInterval
    }
}

/// A word-level Gemini transcript annotation.
public struct GeminiWordInfo: Decodable, Sendable, Equatable {
    /// The word or token text.
    public let text: String
    /// The speaker label, when the request used diarization.
    public let speaker: String?
    /// The start time, in seconds.
    public let start: Double?
    /// The end time, in seconds.
    public let end: Double?
    /// The start index of the word in the transcript text.
    public let startIndex: Int?
    /// The end index of the word in the transcript text.
    public let endIndex: Int?

    /// Creates a word-level Gemini transcript annotation.
    public init(
        text: String,
        speaker: String? = nil,
        start: Double? = nil,
        end: Double? = nil,
        startIndex: Int? = nil,
        endIndex: Int? = nil
    ) {
        self.text = text
        self.speaker = speaker
        self.start = start
        self.end = end
        self.startIndex = startIndex
        self.endIndex = endIndex
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case speaker
        case startOffset = "start_offset"
        case endOffset = "end_offset"
        case startIndex = "start_index"
        case endIndex = "end_index"
    }

    /// Creates a word-level annotation from a Gemini response.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
        self.start = Self.seconds(fromOffset: try container.decodeIfPresent(String.self, forKey: .startOffset))
        self.end = Self.seconds(fromOffset: try container.decodeIfPresent(String.self, forKey: .endOffset))
        self.startIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex)
        self.endIndex = try container.decodeIfPresent(Int.self, forKey: .endIndex)
    }

    /// Converts a Gemini duration string such as `"0.100s"` into seconds.
    static func seconds(fromOffset offset: String?) -> Double? {
        guard let offset else { return nil }
        let trimmed = offset.hasSuffix("s") ? String(offset.dropLast()) : offset
        return Double(trimmed)
    }
}

/// A detailed Gemini file transcription response.
public struct GeminiFileTranscriptionResponse: Decodable, Sendable, Equatable {
    /// The interaction identifier assigned by Gemini.
    public let id: String
    /// The interaction status, such as `"completed"` or `"failed"`.
    public let status: String
    /// The transcribed text.
    public let text: String
    /// Word-level annotations, when the request asked for word timestamps or diarization.
    public let words: [GeminiWordInfo]
    /// The languages Gemini detected, when the response reports them.
    public let detectedLanguages: [String]?

    /// Creates a detailed Gemini file transcription response.
    public init(
        id: String,
        status: String,
        text: String,
        words: [GeminiWordInfo] = [],
        detectedLanguages: [String]? = nil
    ) {
        self.id = id
        self.status = status
        self.text = text
        self.words = words
        self.detectedLanguages = detectedLanguages
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case outputText = "output_text"
        case steps
        case detectedLanguages = "detected_languages"
    }

    /// Creates a detailed response from a Gemini interaction payload.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        self.detectedLanguages = try container.decodeIfPresent([String].self, forKey: .detectedLanguages)

        let steps = try container.decodeIfPresent([GeminiInteractionStep].self, forKey: .steps) ?? []
        let contents = steps.flatMap { $0.content ?? [] }
        let outputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        let stepText = contents.compactMap(\.text).joined(separator: " ")
        self.text = outputText ?? stepText
        self.words = contents
            .flatMap { $0.annotations ?? [] }
            .compactMap(\.wordInfo)
    }
}

struct GeminiInteractionStep: Decodable, Sendable {
    let content: [GeminiInteractionContent]?
}

struct GeminiInteractionContent: Decodable, Sendable {
    let text: String?
    let annotations: [GeminiInteractionAnnotation]?
}

struct GeminiInteractionAnnotation: Decodable, Sendable {
    let type: String?
    let wordInfo: GeminiWordInfo?

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        self.type = type
        self.wordInfo = type == "word_info" ? try GeminiWordInfo(from: decoder) : nil
    }
}

struct GeminiErrorResponse: Decodable, Sendable {
    struct Failure: Decodable, Sendable {
        let code: String?
        let message: String?
    }

    let error: Failure?
}

struct GeminiFileTranscriptionClient {
    static let defaultInteractionsURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")

    private let credential: SpeechCredential
    private let urlSession: URLSession
    private let filesClient: GeminiFilesClient
    private let interactionsURL: URL?
    private static let pendingStatuses: Set<String> = ["queued", "in_progress"]
    private let maxInlineRequestBytes: Int64 = 100 * 1024 * 1024
    private let maxUploadDuration: TimeInterval = 3600
    private let maxAnnotatedUploadDuration: TimeInterval = 1800
    private let allowedExtensions: Set<String> = [
        "wav", "mp3", "mpeg", "mpga", "aiff", "aif", "aac", "ogg", "opus", "flac", "m4a", "webm"
    ]

    init(
        apiKey: String,
        endpoint: URL? = nil,
        filesEndpoint: URL? = nil,
        urlSession: URLSession = .shared
    ) {
        self.init(
            credential: .apiKey(apiKey),
            endpoint: endpoint,
            filesEndpoint: filesEndpoint,
            urlSession: urlSession
        )
    }

    init(
        credential: SpeechCredential,
        endpoint: URL? = nil,
        filesEndpoint: URL? = nil,
        urlSession: URLSession = .shared
    ) {
        self.credential = credential
        self.urlSession = urlSession
        self.interactionsURL = endpoint ?? Self.defaultInteractionsURL
        self.filesClient = GeminiFilesClient(
            credential: credential,
            endpoint: filesEndpoint,
            urlSession: urlSession
        )
    }

    func transcribeAudioFile(
        file: URL,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions()
    ) async throws -> String {
        let response = try await transcribeAudioFileDetailed(file: file, options: options)
        return response.text
    }

    func transcribeAudioFileDetailed(
        file: URL,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions()
    ) async throws -> GeminiFileTranscriptionResponse {
        guard credential.isConfigured else {
            throw SpeechError.providerNotConfigured(.gemini)
        }
        let resolved = try await credential.resolved(for: .gemini)

        let request: URLRequest
        switch try resolvedUploadStrategy(for: file, options: options) {
        case .automatic, .inline:
            request = try await makeRequest(file: file, options: options, credential: resolved)
        case .filesAPI:
            request = try await makeFilesAPIRequest(file: file, options: options, credential: resolved)
        }

        let response = try await send(request)
        return try await finishInteraction(response, options: options, credential: resolved)
    }

    func makeRequest(
        file: URL,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions()
    ) async throws -> URLRequest {
        guard credential.isConfigured else {
            throw SpeechError.providerNotConfigured(.gemini)
        }
        let resolved = try await credential.resolved(for: .gemini)
        return try await makeRequest(file: file, options: options, credential: resolved)
    }

    /// Builds an inline interactions request from an already-resolved credential.
    func makeRequest(
        file: URL,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions(),
        credential: SpeechResolvedCredential
    ) async throws -> URLRequest {
        try validate(options)
        try SpeechFileUploadSupport.validateFileExtension(
            file,
            allowedExtensions: allowedExtensions,
            provider: .gemini
        )
        try await SpeechFileUploadSupport.validateFileDuration(
            file,
            maxDuration: maxDuration(for: options),
            provider: .gemini
        )

        let audioData = try readFileData(from: file)
        let base64Audio = audioData.base64EncodedString()
        guard Int64(base64Audio.count) < maxInlineRequestBytes else {
            throw SpeechError.uploadFailed(
                provider: .gemini,
                reason: "Inline audio exceeds the \(maxInlineRequestBytes) byte request limit."
            )
        }

        return try makeRequest(
            input: GeminiInteractionInput(
                type: "audio",
                data: base64Audio,
                uri: nil,
                mimeType: SpeechFileUploadSupport.mimeType(for: file)
            ),
            options: options,
            credential: credential
        )
    }

    /// Builds an interactions request for an uploaded file from the configured long-lived API key.
    func makeRequest(
        fileURI: String,
        mimeType: String,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions()
    ) throws -> URLRequest {
        try makeRequest(
            fileURI: fileURI,
            mimeType: mimeType,
            options: options,
            credential: .apiKey(credential.staticAPIKey)
        )
    }

    /// Builds an interactions request for an uploaded file from an already-resolved credential.
    func makeRequest(
        fileURI: String,
        mimeType: String,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions(),
        credential: SpeechResolvedCredential
    ) throws -> URLRequest {
        try validate(options)
        return try makeRequest(
            input: GeminiInteractionInput(type: "audio", data: nil, uri: fileURI, mimeType: mimeType),
            options: options,
            credential: credential
        )
    }

    func makeFilesAPIRequest(
        file: URL,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions()
    ) async throws -> URLRequest {
        guard credential.isConfigured else {
            throw SpeechError.providerNotConfigured(.gemini)
        }
        let resolved = try await credential.resolved(for: .gemini)
        return try await makeFilesAPIRequest(file: file, options: options, credential: resolved)
    }

    /// Uploads a file through the Gemini Files API and builds the interactions request for it.
    func makeFilesAPIRequest(
        file: URL,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions(),
        credential: SpeechResolvedCredential
    ) async throws -> URLRequest {
        try validate(options)
        try SpeechFileUploadSupport.validateFileExtension(
            file,
            allowedExtensions: allowedExtensions,
            provider: .gemini
        )
        try await SpeechFileUploadSupport.validateFileDuration(
            file,
            maxDuration: maxDuration(for: options),
            provider: .gemini
        )

        let uploaded = try await filesClient.upload(
            file: file,
            mimeType: SpeechFileUploadSupport.mimeType(for: file),
            timeoutInterval: options.timeoutInterval
        )

        return try makeRequest(
            fileURI: uploaded.uri,
            mimeType: uploaded.mimeType,
            options: options,
            credential: credential
        )
    }

    /// Builds an interaction poll request from the configured long-lived API key.
    func makePollRequest(
        interactionID: String,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions()
    ) throws -> URLRequest {
        try makePollRequest(
            interactionID: interactionID,
            options: options,
            credential: .apiKey(credential.staticAPIKey)
        )
    }

    /// Builds an interaction poll request from an already-resolved credential.
    ///
    /// The polled URL is built relative to the configured interactions
    /// endpoint, so a proxy override keeps both requests on the same host.
    func makePollRequest(
        interactionID: String,
        options: GeminiFileTranscriptionOptions = GeminiFileTranscriptionOptions(),
        credential: SpeechResolvedCredential
    ) throws -> URLRequest {
        guard !credential.isEmpty else {
            throw SpeechError.providerNotConfigured(.gemini)
        }

        let trimmed = interactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpeechError.providerFailure(
                provider: .gemini,
                reason: "The Gemini response did not include an interaction identifier."
            )
        }

        let path = trimmed.hasPrefix("interactions/") ? trimmed : "interactions/\(trimmed)"
        guard let url = try pollURL(forPath: path) else {
            throw SpeechError.invalidResponse(provider: .gemini)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = options.timeoutInterval
        GeminiRESTAuthorization.apply(credential, to: &request)
        return request
    }

    /// Maps the interactions endpoint onto the resource URL for one interaction.
    private func pollURL(forPath path: String) throws -> URL? {
        guard let interactionsURL else {
            throw SpeechError.invalidResponse(provider: .gemini)
        }
        guard var components = URLComponents(url: interactionsURL, resolvingAgainstBaseURL: false) else {
            throw SpeechError.invalidResponse(provider: .gemini)
        }

        var basePath = components.path
        if basePath.hasSuffix("/interactions") {
            basePath.removeLast("interactions".count)
        }
        if !basePath.hasSuffix("/") {
            basePath += "/"
        }
        components.path = basePath + path
        return components.url
    }

    func resolvedUploadStrategy(
        for file: URL,
        options: GeminiFileTranscriptionOptions
    ) throws -> GeminiFileUploadStrategy {
        switch options.uploadStrategy {
        case .inline, .filesAPI:
            return options.uploadStrategy
        case .automatic:
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            return fileSize > options.inlineUploadThresholdBytes ? .filesAPI : .inline
        }
    }

    private func makeRequest(
        input: GeminiInteractionInput,
        options: GeminiFileTranscriptionOptions,
        credential: SpeechResolvedCredential
    ) throws -> URLRequest {
        guard !credential.isEmpty else {
            throw SpeechError.providerNotConfigured(.gemini)
        }
        guard let interactionsURL else {
            throw SpeechError.invalidResponse(provider: .gemini)
        }

        let payload = GeminiInteractionRequest(
            model: options.modelID.rawValue,
            input: [input],
            generationConfig: GeminiGenerationConfig(
                transcriptionConfig: GeminiTranscriptionConfig(
                    languageCodes: options.languageCodes.isEmpty ? nil : options.languageCodes,
                    customVocabulary: options.customVocabulary.isEmpty ? nil : options.customVocabulary,
                    mode: GeminiTranscriptionModeConfig(
                        type: options.mode.rawValue,
                        diarizationMode: options.diarize ? "speaker" : nil,
                        timestampGranularities: options.timestampGranularities.isEmpty
                            ? nil
                            : options.timestampGranularities.map(\.rawValue)
                    )
                )
            ),
            background: options.processingMode != .synchronous
        )

        var request = URLRequest(url: interactionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeoutInterval
        GeminiRESTAuthorization.apply(credential, to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw SpeechError.providerFailure(provider: .gemini, reason: error.localizedDescription)
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> GeminiFileTranscriptionResponse {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .gemini)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SpeechError.uploadFailed(provider: .gemini, reason: errorMessage(from: data, statusCode: httpResponse.statusCode))
        }

        do {
            return try JSONDecoder().decode(GeminiFileTranscriptionResponse.self, from: data)
        } catch {
            throw SpeechError.decodingFailed(provider: .gemini, reason: error.localizedDescription)
        }
    }

    /// Returns the completed interaction, polling a background interaction until it reaches a terminal status.
    private func finishInteraction(
        _ response: GeminiFileTranscriptionResponse,
        options: GeminiFileTranscriptionOptions,
        credential: SpeechResolvedCredential
    ) async throws -> GeminiFileTranscriptionResponse {
        guard case .background(let pollInterval) = options.processingMode else {
            return try completedInteraction(response)
        }

        var latest = response
        let deadline = Date().addingTimeInterval(options.timeoutInterval)

        while Self.pendingStatuses.contains(latest.status) {
            guard Date() < deadline else {
                throw SpeechError.providerFailure(
                    provider: .gemini,
                    reason: "Interaction \(identifier(for: latest)) did not finish within \(Int(options.timeoutInterval)) seconds."
                )
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(max(pollInterval, 0) * 1_000_000_000))
            } catch let cancellation as CancellationError {
                // The caller cancelled the polling task; keep that distinguishable.
                throw cancellation
            } catch {
                throw SpeechError.providerFailure(
                    provider: .gemini,
                    reason: "Polling interaction \(identifier(for: latest)) was cancelled."
                )
            }

            latest = try await send(
                try makePollRequest(interactionID: latest.id, options: options, credential: credential)
            )
        }

        return try completedInteraction(latest)
    }

    private func completedInteraction(
        _ response: GeminiFileTranscriptionResponse
    ) throws -> GeminiFileTranscriptionResponse {
        guard response.status == "completed" else {
            throw SpeechError.providerFailure(
                provider: .gemini,
                reason: "Interaction \(identifier(for: response)) finished with status \(response.status)."
            )
        }
        return response
    }

    private func identifier(for response: GeminiFileTranscriptionResponse) -> String {
        response.id.isEmpty ? "(unknown)" : response.id
    }

    private func validate(_ options: GeminiFileTranscriptionOptions) throws {
        let wantsWordTimestamps = options.timestampGranularities.contains(.word)

        if !options.customVocabulary.isEmpty, options.diarize || wantsWordTimestamps {
            throw SpeechError.providerFailure(
                provider: .gemini,
                reason: "customVocabulary cannot be combined with diarization or word timestamps."
            )
        }

        if options.mode == .smart, options.diarize || wantsWordTimestamps {
            throw SpeechError.providerFailure(
                provider: .gemini,
                reason: "smart mode cannot be combined with diarization or word timestamps."
            )
        }

        if options.customVocabulary.count > 1000 {
            throw SpeechError.providerFailure(
                provider: .gemini,
                reason: "customVocabulary cannot contain more than 1000 terms."
            )
        }

        if case .background(let pollInterval) = options.processingMode, pollInterval <= 0 {
            throw SpeechError.providerFailure(provider: .gemini, reason: "pollInterval must be greater than 0.")
        }

        if options.timeoutInterval <= 0 {
            throw SpeechError.providerFailure(provider: .gemini, reason: "timeoutInterval must be greater than 0.")
        }
    }

    private func maxDuration(for options: GeminiFileTranscriptionOptions) -> TimeInterval {
        let wantsAnnotations = options.diarize || options.timestampGranularities.contains(.word)
        return wantsAnnotations ? maxAnnotatedUploadDuration : maxUploadDuration
    }

    private func errorMessage(from data: Data, statusCode: Int) -> String {
        if let failure = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data),
           let message = failure.error?.message {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
    }

    private func readFileData(from fileURL: URL) throws -> Data {
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw SpeechError.providerFailure(provider: .gemini, reason: error.localizedDescription)
        }
    }
}

struct GeminiInteractionRequest: Encodable, Sendable {
    let model: String
    let input: [GeminiInteractionInput]
    let generationConfig: GeminiGenerationConfig
    let background: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case generationConfig = "generation_config"
        case background
    }
}

struct GeminiInteractionInput: Encodable, Sendable {
    let type: String
    let data: String?
    let uri: String?
    let mimeType: String

    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case uri
        case mimeType = "mime_type"
    }
}

struct GeminiGenerationConfig: Encodable, Sendable {
    let transcriptionConfig: GeminiTranscriptionConfig

    private enum CodingKeys: String, CodingKey {
        case transcriptionConfig = "transcription_config"
    }
}

struct GeminiTranscriptionConfig: Encodable, Sendable {
    let languageCodes: [String]?
    let customVocabulary: [String]?
    let mode: GeminiTranscriptionModeConfig

    private enum CodingKeys: String, CodingKey {
        case languageCodes = "language_codes"
        case customVocabulary = "custom_vocabulary"
        case mode
    }
}

struct GeminiTranscriptionModeConfig: Encodable, Sendable {
    let type: String
    let diarizationMode: String?
    let timestampGranularities: [String]?

    private enum CodingKeys: String, CodingKey {
        case type
        case diarizationMode = "diarization_mode"
        case timestampGranularities = "timestamp_granularities"
    }
}
