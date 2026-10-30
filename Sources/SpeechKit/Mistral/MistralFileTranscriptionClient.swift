import Foundation

/// Mistral Voxtral file transcription model identifiers supported by SpeechKit.
public enum MistralFileTranscriptionModelID: String, Sendable, CaseIterable {
    /// Voxtral Mini Transcribe 3, the efficient file transcription model.
    case voxtralMiniTranscribe3 = "voxtral-mini-transcribe-3"
    /// Voxtral Small Transcribe 3, the higher-accuracy file transcription model.
    case voxtralSmallTranscribe3 = "voxtral-small-transcribe-3"
}

/// Timestamp granularities supported by Mistral file transcription.
///
/// Voxtral 3 returns timestamps per segment only. Mistral rejects word-level
/// timestamps with a `400` error.
public enum MistralTimestampGranularity: String, Sendable, CaseIterable {
    /// Start and end times for each transcript segment.
    case segment
}

/// Options for a Mistral file transcription request.
public struct MistralFileTranscriptionOptions: Sendable, Equatable {
    /// The Voxtral transcription model to use.
    public var modelID: MistralFileTranscriptionModelID
    /// A two-letter ISO 639-1 language code such as `"en"`, or `nil` to let Mistral detect the language.
    public var language: String?
    /// Names, terms, or a descriptive sentence that bias transcription toward the right spelling.
    ///
    /// The entries share the model's context window with the audio, so keep the
    /// list short. Mistral rejects a request that exceeds the window.
    public var contextBias: [String]
    /// A Boolean value that indicates whether Mistral should label each segment with its speaker.
    ///
    /// Mistral requires segment timestamps for diarization, so SpeechKit
    /// requests them automatically when this is `true`.
    public var diarize: Bool
    /// The timestamp granularities to request from Mistral.
    public var timestampGranularities: [MistralTimestampGranularity]
    /// An optional sampling temperature.
    public var temperature: Double?
    /// The network timeout for the upload request.
    public var timeoutInterval: TimeInterval

    /// Creates Mistral file transcription options.
    public init(
        modelID: MistralFileTranscriptionModelID = .voxtralMiniTranscribe3,
        language: String? = nil,
        contextBias: [String] = [],
        diarize: Bool = false,
        timestampGranularities: [MistralTimestampGranularity] = [],
        temperature: Double? = nil,
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.modelID = modelID
        self.language = language
        self.contextBias = contextBias
        self.diarize = diarize
        self.timestampGranularities = timestampGranularities
        self.temperature = temperature
        self.timeoutInterval = timeoutInterval
    }

    /// The timestamp granularities sent to Mistral, including the segment granularity diarization requires.
    var resolvedTimestampGranularities: [MistralTimestampGranularity] {
        if diarize, !timestampGranularities.contains(.segment) {
            return timestampGranularities + [.segment]
        }
        return timestampGranularities
    }
}

/// One Mistral transcript segment.
public struct MistralTranscriptionSegment: Decodable, Sendable, Equatable {
    /// The segment text, including its leading space.
    public let text: String
    /// The segment start time, in seconds.
    public let start: Double?
    /// The segment end time, in seconds.
    public let end: Double?
    /// The speaker label, such as `"speaker_1"`, when the request used diarization.
    public let speakerID: String?

    /// Creates a Mistral transcript segment.
    public init(text: String, start: Double? = nil, end: Double? = nil, speakerID: String? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.speakerID = speakerID
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case start
        case end
        case speakerID = "speaker_id"
    }
}

/// Usage reported by a Mistral transcription.
public struct MistralTranscriptionUsage: Decodable, Sendable, Equatable {
    /// The duration of the processed audio, in seconds.
    public let promptAudioSeconds: Int?
    /// The number of prompt tokens.
    public let promptTokens: Int?
    /// The number of completion tokens.
    public let completionTokens: Int?
    /// The total number of tokens.
    public let totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case promptAudioSeconds = "prompt_audio_seconds"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

/// A detailed Mistral file transcription response.
public struct MistralFileTranscriptionResponse: Decodable, Sendable, Equatable {
    /// The model that produced the transcript.
    public let model: String?
    /// The full transcript text, without speaker labels.
    public let text: String
    /// The detected language, when Mistral reports one.
    public let language: String?
    /// The transcript segments. Empty unless the request asked for timestamps or diarization.
    public let segments: [MistralTranscriptionSegment]
    /// Usage reported by Mistral.
    public let usage: MistralTranscriptionUsage?

    private enum CodingKeys: String, CodingKey {
        case model
        case text
        case language
        case segments
        case usage
    }

    /// Creates a response by decoding Mistral's JSON.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.text = try container.decode(String.self, forKey: .text)
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.segments = try container.decodeIfPresent([MistralTranscriptionSegment].self, forKey: .segments) ?? []
        self.usage = try container.decodeIfPresent(MistralTranscriptionUsage.self, forKey: .usage)
    }
}

struct MistralFileTranscriptionClient {
    static let defaultUploadURL = URL(string: "https://api.mistral.ai/v1/audio/transcriptions")

    private let credential: SpeechCredential
    private let urlSession: URLSession
    private let uploadURL: URL?

    init(apiKey: String, endpoint: URL? = nil, urlSession: URLSession = .shared) {
        self.init(credential: .apiKey(apiKey), endpoint: endpoint, urlSession: urlSession)
    }

    init(credential: SpeechCredential, endpoint: URL? = nil, urlSession: URLSession = .shared) {
        self.credential = credential
        self.urlSession = urlSession
        self.uploadURL = endpoint ?? Self.defaultUploadURL
    }

    func transcribeAudioFile(
        file: URL,
        options: MistralFileTranscriptionOptions = MistralFileTranscriptionOptions()
    ) async throws -> String {
        let response = try await transcribeAudioFileDetailed(file: file, options: options)
        return response.text
    }

    func transcribeAudioFileDetailed(
        file: URL,
        options: MistralFileTranscriptionOptions = MistralFileTranscriptionOptions()
    ) async throws -> MistralFileTranscriptionResponse {
        let request = try await makeRequest(file: file, options: options)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .mistral)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SpeechError.uploadFailed(provider: .mistral, reason: message)
        }

        do {
            return try JSONDecoder().decode(MistralFileTranscriptionResponse.self, from: data)
        } catch {
            throw SpeechError.decodingFailed(provider: .mistral, reason: error.localizedDescription)
        }
    }

    func makeRequest(
        file: URL,
        options: MistralFileTranscriptionOptions = MistralFileTranscriptionOptions()
    ) async throws -> URLRequest {
        guard credential.isConfigured else {
            throw SpeechError.providerNotConfigured(.mistral)
        }
        let resolved = try await credential.resolved(for: .mistral)
        return try makeRequest(file: file, options: options, secret: resolved.secret)
    }

    /// Builds an upload request from an already-resolved secret.
    ///
    /// Mistral accepts both a long-lived API key and a short-lived token as a
    /// bearer token.
    func makeRequest(
        file: URL,
        options: MistralFileTranscriptionOptions = MistralFileTranscriptionOptions(),
        secret: String
    ) throws -> URLRequest {
        guard !secret.isEmpty else {
            throw SpeechError.providerNotConfigured(.mistral)
        }
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .mistral)
        }

        try validate(options)

        let audioData = try readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"
        var parts: [SpeechMultipartFormPart] = [
            .text(name: "model", value: options.modelID.rawValue)
        ]
        if let language = options.language {
            parts.append(.text(name: "language", value: language))
        }
        if let temperature = options.temperature {
            parts.append(.text(name: "temperature", value: String(temperature)))
        }
        if options.diarize {
            parts.append(.text(name: "diarize", value: "true"))
        }
        for granularity in options.resolvedTimestampGranularities {
            parts.append(.text(name: "timestamp_granularities", value: granularity.rawValue))
        }
        for entry in options.contextBias {
            parts.append(.text(name: "context_bias", value: entry))
        }
        parts.append(
            .file(
                name: "file",
                fileURL: file,
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: file)
            )
        )

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeoutInterval
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(boundary: boundary, parts: parts)
        return request
    }

    private func validate(_ options: MistralFileTranscriptionOptions) throws {
        try MistralValidation.validateLanguage(options.language)
        try MistralValidation.validateContextBias(options.contextBias)

        if options.timeoutInterval <= 0 {
            throw SpeechError.providerFailure(provider: .mistral, reason: "timeoutInterval must be greater than 0.")
        }
    }

    private func readFileData(from fileURL: URL) throws -> Data {
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw SpeechError.providerFailure(provider: .mistral, reason: error.localizedDescription)
        }
    }
}

/// Validation shared by Mistral file and realtime requests.
enum MistralValidation {
    /// Rejects a language that is not a two-letter ISO 639-1 code.
    static func validateLanguage(_ language: String?) throws {
        guard let language else { return }
        let isTwoLetterCode = language.count == 2 && language.allSatisfy { $0.isASCII && $0.isLetter }
        guard isTwoLetterCode else {
            throw SpeechError.providerFailure(
                provider: .mistral,
                reason: "language must be a two-letter ISO 639-1 code: \"\(language)\"."
            )
        }
    }

    /// Rejects blank context bias entries.
    static func validateContextBias(_ contextBias: [String]) throws {
        if let entry = contextBias.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw SpeechError.providerFailure(provider: .mistral, reason: "contextBias entries cannot be empty: \"\(entry)\".")
        }
    }
}
