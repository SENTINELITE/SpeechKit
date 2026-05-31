import Foundation

/// OpenAI file transcription model identifiers supported by SpeechKit.
public enum OpenAIFileTranscriptionModelID: String, Sendable, CaseIterable {
    /// OpenAI Whisper transcription.
    case whisper1 = "whisper-1"
    /// GPT-4o transcription.
    case gpt4oTranscribe = "gpt-4o-transcribe"
    /// GPT-4o mini transcription.
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    /// GPT-4o mini transcription snapshot.
    case gpt4oMiniTranscribe20251215 = "gpt-4o-mini-transcribe-2025-12-15"
    /// GPT-4o transcription with speaker diarization.
    case gpt4oTranscribeDiarize = "gpt-4o-transcribe-diarize"
}

/// OpenAI realtime transcription model identifiers supported by SpeechKit.
public enum OpenAIRealtimeTranscriptionModelID: String, Sendable, CaseIterable {
    /// GPT-4o realtime transcription.
    case gpt4oTranscribe = "gpt-4o-transcribe"
    /// GPT-4o mini realtime transcription.
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    /// GPT-4o realtime transcription latest alias.
    case gpt4oTranscribeLatest = "gpt-4o-transcribe-latest"
    /// OpenAI Whisper transcription.
    case whisper1 = "whisper-1"
}

/// OpenAI Realtime connection model identifiers supported by SpeechKit.
public enum OpenAIRealtimeSessionModelID: String, Sendable, CaseIterable {
    /// OpenAI Realtime model used to host realtime transcription sessions.
    case gptRealtime = "gpt-realtime"
}

/// OpenAI timestamp granularities supported for Whisper verbose JSON transcription responses.
public enum OpenAITimestampGranularity: String, Sendable, CaseIterable {
    /// Segment-level timestamps.
    case segment
    /// Word-level timestamps.
    case word
}

/// A Voice Activity Detection configuration for OpenAI diarized file transcription chunking.
public struct OpenAIDiarizationVADOptions: Sendable, Equatable {
    /// The audio activation threshold from 0 to 1.
    public var threshold: Double?
    /// The amount of audio, in milliseconds, to include before detected speech.
    public var prefixPaddingMilliseconds: Int?
    /// The silence duration, in milliseconds, used to detect speech stop.
    public var silenceDurationMilliseconds: Int?

    /// Creates an OpenAI diarization VAD configuration.
    public init(
        threshold: Double? = nil,
        prefixPaddingMilliseconds: Int? = nil,
        silenceDurationMilliseconds: Int? = nil
    ) {
        self.threshold = threshold
        self.prefixPaddingMilliseconds = prefixPaddingMilliseconds
        self.silenceDurationMilliseconds = silenceDurationMilliseconds
    }
}

/// The chunking strategy OpenAI should use for diarized file transcription.
public enum OpenAIDiarizationChunkingStrategy: Sendable, Equatable {
    /// Lets OpenAI normalize loudness and choose chunk boundaries with VAD.
    case auto
    /// Uses OpenAI server-side VAD with explicit tuning.
    case serverVAD(OpenAIDiarizationVADOptions = OpenAIDiarizationVADOptions())

    var multipartValue: String {
        switch self {
        case .auto:
            return "auto"
        case .serverVAD(let options):
            var fields = ["\"type\":\"server_vad\""]
            if let threshold = options.threshold {
                fields.append("\"threshold\":\(threshold)")
            }
            if let prefixPaddingMilliseconds = options.prefixPaddingMilliseconds {
                fields.append("\"prefix_padding_ms\":\(prefixPaddingMilliseconds)")
            }
            if let silenceDurationMilliseconds = options.silenceDurationMilliseconds {
                fields.append("\"silence_duration_ms\":\(silenceDurationMilliseconds)")
            }
            return "{\(fields.joined(separator: ","))}"
        }
    }
}

/// A known speaker reference for OpenAI diarized file transcription.
public struct OpenAIKnownSpeaker: Sendable, Equatable {
    /// The speaker name OpenAI should use when the reference matches.
    public var name: String
    /// A short reference clip encoded as a data URL.
    public var referenceDataURL: String

    /// Creates a known speaker reference.
    public init(name: String, referenceDataURL: String) {
        self.name = name
        self.referenceDataURL = referenceDataURL
    }
}

/// Options for an OpenAI file transcription request.
public struct OpenAIFileTranscriptionOptions: Sendable, Equatable {
    /// The OpenAI file transcription model to use.
    public var modelID: OpenAIFileTranscriptionModelID
    /// An optional ISO-639-1 language hint.
    public var language: String?
    /// An optional prompt to guide transcription style or spelling.
    public var prompt: String?
    /// An optional sampling temperature.
    public var temperature: Double?
    /// A Boolean value that indicates whether OpenAI should return token log probabilities.
    public var includeLogprobs: Bool
    /// The timestamp granularities to request for Whisper verbose JSON responses.
    public var timestampGranularities: [OpenAITimestampGranularity]
    /// The chunking strategy used by OpenAI diarization models.
    public var diarizationChunkingStrategy: OpenAIDiarizationChunkingStrategy?
    /// Known speaker reference clips used by OpenAI diarization models.
    public var knownSpeakers: [OpenAIKnownSpeaker]
    /// The network timeout for the upload request.
    public var timeoutInterval: TimeInterval

    /// Creates OpenAI file transcription options.
    public init(
        modelID: OpenAIFileTranscriptionModelID = .gpt4oTranscribe,
        language: String? = nil,
        prompt: String? = nil,
        temperature: Double? = nil,
        includeLogprobs: Bool = false,
        timestampGranularities: [OpenAITimestampGranularity] = [],
        diarizationChunkingStrategy: OpenAIDiarizationChunkingStrategy? = nil,
        knownSpeakers: [OpenAIKnownSpeaker] = [],
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.modelID = modelID
        self.language = language
        self.prompt = prompt
        self.temperature = temperature
        self.includeLogprobs = includeLogprobs
        self.timestampGranularities = timestampGranularities
        self.diarizationChunkingStrategy = diarizationChunkingStrategy
        self.knownSpeakers = knownSpeakers
        self.timeoutInterval = timeoutInterval
    }
}

/// A token log probability returned by OpenAI transcription.
public struct OpenAITranscriptionLogprob: Decodable, Sendable, Equatable {
    /// The output token text.
    public let token: String
    /// The token log probability.
    public let logprob: Double
    /// The UTF-8 bytes for the token, when returned.
    public let bytes: [Int]?
}

/// A word-level OpenAI timestamp.
public struct OpenAIWordTimestamp: Decodable, Sendable, Equatable {
    /// The word text.
    public let word: String
    /// The start time, in seconds.
    public let start: Double
    /// The end time, in seconds.
    public let end: Double
}

/// A segment-level OpenAI timestamp.
public struct OpenAITranscriptionSegment: Decodable, Sendable, Equatable {
    /// The segment identifier.
    public let id: Int?
    /// The segment start time, in seconds.
    public let start: Double?
    /// The segment end time, in seconds.
    public let end: Double?
    /// The segment text.
    public let text: String

    private enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleIntIfPresent(forKey: .id)
        start = try container.decodeIfPresent(Double.self, forKey: .start)
        end = try container.decodeIfPresent(Double.self, forKey: .end)
        text = try container.decode(String.self, forKey: .text)
    }
}

/// A diarized OpenAI transcription segment.
public struct OpenAIDiarizedSegment: Decodable, Sendable, Equatable {
    /// The segment speaker label, when returned.
    public let speaker: String?
    /// The segment start time, in seconds.
    public let start: Double?
    /// The segment end time, in seconds.
    public let end: Double?
    /// The segment text.
    public let text: String

    private enum CodingKeys: String, CodingKey {
        case speaker
        case start
        case end
        case text
    }
}

/// OpenAI transcription usage metadata.
public struct OpenAITranscriptionUsage: Decodable, Sendable, Equatable {
    /// The usage type reported by OpenAI.
    public let type: String?
    /// The audio duration, in seconds, when returned.
    public let seconds: Double?
    /// The number of input tokens, when returned.
    public let inputTokens: Int?
    /// The number of output tokens, when returned.
    public let outputTokens: Int?
    /// The total number of tokens, when returned.
    public let totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case type
        case seconds
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

/// A detailed OpenAI file transcription response.
public struct OpenAIFileTranscriptionResponse: Decodable, Sendable, Equatable {
    /// The transcribed text.
    public let text: String
    /// The detected or requested language code.
    public let language: String?
    /// The audio duration, in seconds.
    public let duration: Double?
    /// Usage metadata for the transcription request.
    public let usage: OpenAITranscriptionUsage?
    /// Token log probabilities, when requested and returned.
    public let logprobs: [OpenAITranscriptionLogprob]?
    /// Word-level timestamps, when requested and returned.
    public let words: [OpenAIWordTimestamp]?
    /// Segment-level timestamps, when requested and returned.
    public let segments: [OpenAITranscriptionSegment]?
    /// Speaker diarization segments, when returned by a diarization model.
    public let diarizedSegments: [OpenAIDiarizedSegment]?

    private enum CodingKeys: String, CodingKey {
        case text
        case language
        case duration
        case usage
        case logprobs
        case words
        case segments
        case diarizedSegments = "diarized_segments"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        usage = try container.decodeIfPresent(OpenAITranscriptionUsage.self, forKey: .usage)
        logprobs = try container.decodeIfPresent([OpenAITranscriptionLogprob].self, forKey: .logprobs)
        words = try container.decodeIfPresent([OpenAIWordTimestamp].self, forKey: .words)
        segments = try container.decodeIfPresent([OpenAITranscriptionSegment].self, forKey: .segments)
        diarizedSegments = try container.decodeIfPresent([OpenAIDiarizedSegment].self, forKey: .diarizedSegments)
            ?? Self.decodeDiarizedSegments(from: container)
    }

    private static func decodeDiarizedSegments(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [OpenAIDiarizedSegment]? {
        guard let values = try container.decodeIfPresent([OpenAIDiarizedSegment].self, forKey: .segments),
              values.contains(where: { $0.speaker != nil }) else {
            return nil
        }
        return values
    }
}

struct OpenAIFileTranscriptionClient {
    private let apiKey: String
    private let urlSession: URLSession
    private let uploadURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")
    private let maxUploadBytes: Int64 = 25 * 1024 * 1024
    private let allowedExtensions: Set<String> = ["mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm"]

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func transcribeAudioFile(
        file: URL,
        options: OpenAIFileTranscriptionOptions = OpenAIFileTranscriptionOptions()
    ) async throws -> String {
        let response = try await transcribeAudioFileDetailed(file: file, options: options)
        return response.text
    }

    func transcribeAudioFileDetailed(
        file: URL,
        options: OpenAIFileTranscriptionOptions = OpenAIFileTranscriptionOptions()
    ) async throws -> OpenAIFileTranscriptionResponse {
        let request = try makeRequest(file: file, options: options)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .openAI)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SpeechError.uploadFailed(provider: .openAI, reason: message)
        }

        do {
            return try JSONDecoder().decode(OpenAIFileTranscriptionResponse.self, from: data)
        } catch {
            throw SpeechError.decodingFailed(provider: .openAI, reason: error.localizedDescription)
        }
    }

    func makeRequest(
        file: URL,
        options: OpenAIFileTranscriptionOptions = OpenAIFileTranscriptionOptions()
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw SpeechError.providerNotConfigured(.openAI)
        }
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .openAI)
        }

        try validate(options)
        try SpeechFileUploadSupport.validateFileExtension(file, allowedExtensions: allowedExtensions, provider: .openAI)
        try SpeechFileUploadSupport.validateFileSize(file, maxUploadBytes: maxUploadBytes, provider: .openAI)
        let audioData = try readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"

        var parts: [SpeechMultipartFormPart] = [
            .file(
                name: "file",
                fileURL: file,
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: file)
            ),
            .text(name: "model", value: options.modelID.rawValue),
            .text(name: "response_format", value: responseFormat(for: options))
        ]

        if let language = options.language {
            parts.append(.text(name: "language", value: language))
        }
        if let prompt = options.prompt {
            parts.append(.text(name: "prompt", value: prompt))
        }
        if let temperature = options.temperature {
            parts.append(.text(name: "temperature", value: String(temperature)))
        }
        if options.includeLogprobs {
            parts.append(.text(name: "include[]", value: "logprobs"))
        }
        for granularity in options.timestampGranularities {
            parts.append(.text(name: "timestamp_granularities[]", value: granularity.rawValue))
        }
        if let chunkingStrategy = effectiveDiarizationChunkingStrategy(for: options) {
            parts.append(.text(name: "chunking_strategy", value: chunkingStrategy.multipartValue))
        }
        for knownSpeaker in options.knownSpeakers {
            parts.append(.text(name: "known_speaker_names[]", value: knownSpeaker.name))
            parts.append(.text(name: "known_speaker_references[]", value: knownSpeaker.referenceDataURL))
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeoutInterval
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(boundary: boundary, parts: parts)
        return request
    }

    private func validate(_ options: OpenAIFileTranscriptionOptions) throws {
        if options.modelID == .gpt4oTranscribeDiarize {
            if options.prompt != nil {
                throw SpeechError.providerFailure(provider: .openAI, reason: "prompt is not supported with gpt-4o-transcribe-diarize.")
            }
            if options.includeLogprobs {
                throw SpeechError.providerFailure(provider: .openAI, reason: "includeLogprobs is not supported with gpt-4o-transcribe-diarize.")
            }
            if !options.timestampGranularities.isEmpty {
                throw SpeechError.providerFailure(provider: .openAI, reason: "timestampGranularities are not supported with gpt-4o-transcribe-diarize.")
            }
        } else {
            if options.diarizationChunkingStrategy != nil {
                throw SpeechError.providerFailure(provider: .openAI, reason: "diarizationChunkingStrategy requires gpt-4o-transcribe-diarize.")
            }
            if !options.knownSpeakers.isEmpty {
                throw SpeechError.providerFailure(provider: .openAI, reason: "knownSpeakers require gpt-4o-transcribe-diarize.")
            }
        }

        if !options.timestampGranularities.isEmpty, options.modelID != .whisper1 {
            throw SpeechError.providerFailure(provider: .openAI, reason: "timestampGranularities are only supported with whisper-1.")
        }

        if options.includeLogprobs,
           options.modelID != .gpt4oTranscribe,
           options.modelID != .gpt4oMiniTranscribe,
           options.modelID != .gpt4oMiniTranscribe20251215 {
            throw SpeechError.providerFailure(provider: .openAI, reason: "includeLogprobs is only supported with GPT-4o transcription models.")
        }

        if options.knownSpeakers.count > 4 {
            throw SpeechError.providerFailure(provider: .openAI, reason: "knownSpeakers supports at most 4 speakers.")
        }
        for knownSpeaker in options.knownSpeakers {
            if knownSpeaker.name.isEmpty {
                throw SpeechError.providerFailure(provider: .openAI, reason: "knownSpeakers names cannot be empty.")
            }
            if knownSpeaker.referenceDataURL.isEmpty {
                throw SpeechError.providerFailure(provider: .openAI, reason: "knownSpeakers referenceDataURL cannot be empty.")
            }
            if !knownSpeaker.referenceDataURL.hasPrefix("data:audio/") {
                throw SpeechError.providerFailure(provider: .openAI, reason: "knownSpeakers referenceDataURL must be an audio data URL.")
            }
        }

        if case .serverVAD(let vadOptions) = options.diarizationChunkingStrategy {
            if let threshold = vadOptions.threshold, threshold < 0 || threshold > 1 {
                throw SpeechError.providerFailure(provider: .openAI, reason: "diarization VAD threshold must be between 0 and 1.")
            }
            if let prefixPaddingMilliseconds = vadOptions.prefixPaddingMilliseconds, prefixPaddingMilliseconds < 0 {
                throw SpeechError.providerFailure(provider: .openAI, reason: "diarization VAD prefixPaddingMilliseconds must be at least 0.")
            }
            if let silenceDurationMilliseconds = vadOptions.silenceDurationMilliseconds, silenceDurationMilliseconds < 0 {
                throw SpeechError.providerFailure(provider: .openAI, reason: "diarization VAD silenceDurationMilliseconds must be at least 0.")
            }
        }

        if options.timeoutInterval <= 0 {
            throw SpeechError.providerFailure(provider: .openAI, reason: "timeoutInterval must be greater than 0.")
        }
    }

    private func responseFormat(for options: OpenAIFileTranscriptionOptions) -> String {
        if options.modelID == .gpt4oTranscribeDiarize {
            return "diarized_json"
        }
        if !options.timestampGranularities.isEmpty {
            return "verbose_json"
        }
        return "json"
    }

    private func effectiveDiarizationChunkingStrategy(
        for options: OpenAIFileTranscriptionOptions
    ) -> OpenAIDiarizationChunkingStrategy? {
        guard options.modelID == .gpt4oTranscribeDiarize else {
            return nil
        }
        return options.diarizationChunkingStrategy ?? .auto
    }

    private func readFileData(from fileURL: URL) throws -> Data {
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw SpeechError.providerFailure(provider: .openAI, reason: error.localizedDescription)
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}
