import Foundation

public enum GrokAudioFormat: String, Sendable, CaseIterable {
    case pcm
    case mulaw
    case alaw
}

public enum GrokModelID: String, Sendable, CaseIterable {
    case stt = "grok-stt"
}

public enum GrokTimestampGranularity: String, Sendable, CaseIterable {
    case word
}

public enum GrokLanguage: String, Sendable, CaseIterable {
    case arabic = "ar"
    case czech = "cs"
    case danish = "da"
    case dutch = "nl"
    case english = "en"
    case filipino = "fil"
    case french = "fr"
    case german = "de"
    case hindi = "hi"
    case indonesian = "id"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case macedonian = "mk"
    case malay = "ms"
    case persian = "fa"
    case polish = "pl"
    case portuguese = "pt"
    case romanian = "ro"
    case russian = "ru"
    case spanish = "es"
    case swedish = "sv"
    case thai = "th"
    case turkish = "tr"
    case vietnamese = "vi"
}

public struct GrokFileTranscriptionOptions: Sendable, Equatable {
    public var modelId: GrokModelID
    public var language: GrokLanguage?
    public var format: Bool
    public var multichannel: Bool
    public var channels: Int?
    public var diarize: Bool
    public var timestampGranularities: [GrokTimestampGranularity]
    public var audioFormat: GrokAudioFormat?
    public var sampleRate: Int?
    public var timeoutInterval: TimeInterval

    public init(
        modelId: GrokModelID = .stt,
        language: GrokLanguage? = nil,
        format: Bool = false,
        multichannel: Bool = false,
        channels: Int? = nil,
        diarize: Bool = false,
        timestampGranularities: [GrokTimestampGranularity] = [.word],
        audioFormat: GrokAudioFormat? = nil,
        sampleRate: Int? = nil,
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.modelId = modelId
        self.language = language
        self.format = format
        self.multichannel = multichannel
        self.channels = channels
        self.diarize = diarize
        self.timestampGranularities = timestampGranularities
        self.audioFormat = audioFormat
        self.sampleRate = sampleRate
        self.timeoutInterval = timeoutInterval
    }
}

public struct GrokWordTimestamp: Decodable, Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double
    public let speaker: Int?
}

public struct GrokTranscriptionChannel: Decodable, Sendable, Equatable {
    public let index: Int
    public let text: String
    public let words: [GrokWordTimestamp]?
}

public struct GrokFileTranscriptionResponse: Decodable, Sendable, Equatable {
    public let text: String
    public let language: String?
    public let duration: Double?
    public let words: [GrokWordTimestamp]?
    public let channels: [GrokTranscriptionChannel]?
}

struct GrokFileTranscriptionClient {
    private let apiKey: String
    private let urlSession: URLSession
    private let uploadURL = URL(string: "https://api.x.ai/v1/stt")
    private let maxUploadBytes: Int64 = 500 * 1024 * 1024

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func transcribeAudioFile(
        file: URL,
        options: GrokFileTranscriptionOptions = GrokFileTranscriptionOptions()
    ) async throws -> String {
        let response = try await transcribeAudioFileDetailed(file: file, options: options)
        return response.text
    }

    func transcribeAudioFileDetailed(
        file: URL,
        options: GrokFileTranscriptionOptions = GrokFileTranscriptionOptions()
    ) async throws -> GrokFileTranscriptionResponse {
        let request = try makeRequest(file: file, options: options)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .grok)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SpeechError.uploadFailed(provider: .grok, reason: message)
        }

        do {
            return try JSONDecoder().decode(GrokFileTranscriptionResponse.self, from: data)
        } catch {
            throw SpeechError.decodingFailed(provider: .grok, reason: error.localizedDescription)
        }
    }

    func makeRequest(
        file: URL,
        options: GrokFileTranscriptionOptions = GrokFileTranscriptionOptions()
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw SpeechError.providerNotConfigured(.grok)
        }
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .grok)
        }

        try validate(options)
        let audioData = try readFileData(from: file, options: options)
        let boundary = "SpeechKit-\(UUID().uuidString)"
        var parts: [SpeechMultipartFormPart] = [
            .file(
                name: "file",
                fileURL: file,
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: file)
            )
        ]
        parts.append(contentsOf: makeOptionParts(options))

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeoutInterval
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(boundary: boundary, parts: parts)
        return request
    }

    private func makeOptionParts(_ options: GrokFileTranscriptionOptions) -> [SpeechMultipartFormPart] {
        var parts: [SpeechMultipartFormPart] = [
            .text(name: "model", value: options.modelId.rawValue)
        ]

        for granularity in options.timestampGranularities {
            parts.append(.text(name: "timestamp_granularities", value: granularity.rawValue))
        }

        if let language = options.language {
            parts.append(.text(name: "language", value: language.rawValue))
        }
        if options.format {
            parts.append(.text(name: "format", value: "true"))
        }
        if options.multichannel {
            parts.append(.text(name: "multichannel", value: "true"))
        }
        if let channels = options.channels {
            parts.append(.text(name: "channels", value: String(channels)))
        }
        if options.diarize {
            parts.append(.text(name: "diarize", value: "true"))
        }
        if let audioFormat = options.audioFormat {
            parts.append(.text(name: "audio_format", value: audioFormat.rawValue))
        }
        if let sampleRate = options.sampleRate {
            parts.append(.text(name: "sample_rate", value: String(sampleRate)))
        }

        return parts
    }

    private func validate(_ options: GrokFileTranscriptionOptions) throws {
        if options.format, options.language == nil {
            throw SpeechError.providerFailure(provider: .grok, reason: "format=true requires a language.")
        }

        if options.audioFormat != nil, options.sampleRate == nil {
            throw SpeechError.providerFailure(provider: .grok, reason: "Raw audio requires sample_rate.")
        }

        if let sampleRate = options.sampleRate,
           ![8000, 16000, 22050, 24000, 44100, 48000].contains(sampleRate) {
            throw SpeechError.providerFailure(provider: .grok, reason: "Unsupported sample_rate: \(sampleRate).")
        }

        if let channels = options.channels,
           !(2...8).contains(channels) {
            throw SpeechError.providerFailure(provider: .grok, reason: "channels must be between 2 and 8.")
        }

        if options.timeoutInterval <= 0 {
            throw SpeechError.providerFailure(provider: .grok, reason: "timeoutInterval must be greater than 0.")
        }
    }

    private func readFileData(from fileURL: URL, options: GrokFileTranscriptionOptions) throws -> Data {
        do {
            if fileURL.pathExtension.isEmpty {
                throw SpeechError.providerFailure(provider: .grok, reason: "Unsupported file extension: (none).")
            }
            if isRawAudio(fileURL) {
                if options.audioFormat == nil || options.sampleRate == nil {
                    throw SpeechError.providerFailure(provider: .grok, reason: "Raw audio requires audio_format and sample_rate.")
                }
            } else {
                try SpeechFileUploadSupport.validateFileExtension(
                    fileURL,
                    allowedExtensions: ["wav", "mp3", "ogg", "opus", "flac", "aac", "mp4", "m4a", "mkv"],
                    provider: .grok
                )
            }
            try SpeechFileUploadSupport.validateFileSize(fileURL, maxUploadBytes: maxUploadBytes, provider: .grok)
            return try Data(contentsOf: fileURL)
        } catch let error as SpeechError {
            throw error
        } catch {
            throw SpeechError.providerFailure(provider: .grok, reason: error.localizedDescription)
        }
    }

    private func isRawAudio(_ fileURL: URL) -> Bool {
        ["pcm", "mulaw", "alaw"].contains(fileURL.pathExtension.lowercased())
    }
}
