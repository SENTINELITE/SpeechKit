import Foundation

public enum GrokAudioFormat: String, Sendable, CaseIterable {
    case pcm
    case mulaw
    case alaw
}

public struct GrokFileTranscriptionOptions: Sendable, Equatable {
    public var language: String?
    public var format: Bool
    public var multichannel: Bool
    public var channels: Int?
    public var diarize: Bool
    public var audioFormat: GrokAudioFormat?
    public var sampleRate: Int?

    public init(
        language: String? = nil,
        format: Bool = false,
        multichannel: Bool = false,
        channels: Int? = nil,
        diarize: Bool = false,
        audioFormat: GrokAudioFormat? = nil,
        sampleRate: Int? = nil
    ) {
        self.language = language
        self.format = format
        self.multichannel = multichannel
        self.channels = channels
        self.diarize = diarize
        self.audioFormat = audioFormat
        self.sampleRate = sampleRate
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
        let audioData = try readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"
        var parts = makeOptionParts(options)
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(boundary: boundary, parts: parts)
        return request
    }

    private func makeOptionParts(_ options: GrokFileTranscriptionOptions) -> [SpeechMultipartFormPart] {
        var parts: [SpeechMultipartFormPart] = [
            .text(name: "format", value: String(options.format)),
            .text(name: "multichannel", value: String(options.multichannel)),
            .text(name: "diarize", value: String(options.diarize))
        ]

        if let language = options.language {
            parts.append(.text(name: "language", value: language))
        }
        if let channels = options.channels {
            parts.append(.text(name: "channels", value: String(channels)))
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
    }

    private func readFileData(from fileURL: URL) throws -> Data {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? NSNumber,
               fileSize.int64Value > maxUploadBytes {
                throw SpeechError.uploadFailed(provider: .grok, reason: "Audio file exceeds 500 MB limit.")
            }
            return try Data(contentsOf: fileURL)
        } catch let error as SpeechError {
            throw error
        } catch {
            throw SpeechError.providerFailure(provider: .grok, reason: error.localizedDescription)
        }
    }
}
