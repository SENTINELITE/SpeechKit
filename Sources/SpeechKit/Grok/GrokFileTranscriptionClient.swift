import Foundation

/// Raw audio formats supported by Grok transcription requests.
public enum GrokAudioFormat: String, Sendable, CaseIterable {
    /// Linear PCM raw audio.
    case pcm
    /// mu-law raw audio.
    case mulaw
    /// A-law raw audio.
    case alaw
}

/// Grok speech-to-text model identifiers supported by SpeechKit.
public enum GrokModelID: String, Sendable, CaseIterable {
    /// Grok speech-to-text.
    case stt = "grok-stt"
}

/// Timestamp granularities supported by Grok transcription.
public enum GrokTimestampGranularity: String, Sendable, CaseIterable {
    /// Word-level timestamps.
    case word
}

/// Grok language hints for file transcription.
public enum GrokLanguage: String, Sendable, CaseIterable {
    /// Arabic.
    case arabic = "ar"
    /// Czech.
    case czech = "cs"
    /// Danish.
    case danish = "da"
    /// Dutch.
    case dutch = "nl"
    /// English.
    case english = "en"
    /// Filipino.
    case filipino = "fil"
    /// French.
    case french = "fr"
    /// German.
    case german = "de"
    /// Hindi.
    case hindi = "hi"
    /// Indonesian.
    case indonesian = "id"
    /// Italian.
    case italian = "it"
    /// Japanese.
    case japanese = "ja"
    /// Korean.
    case korean = "ko"
    /// Macedonian.
    case macedonian = "mk"
    /// Malay.
    case malay = "ms"
    /// Persian.
    case persian = "fa"
    /// Polish.
    case polish = "pl"
    /// Portuguese.
    case portuguese = "pt"
    /// Romanian.
    case romanian = "ro"
    /// Russian.
    case russian = "ru"
    /// Spanish.
    case spanish = "es"
    /// Swedish.
    case swedish = "sv"
    /// Thai.
    case thai = "th"
    /// Turkish.
    case turkish = "tr"
    /// Vietnamese.
    case vietnamese = "vi"
}

/// Options for a Grok file transcription request.
public struct GrokFileTranscriptionOptions: Sendable, Equatable {
    /// The Grok speech-to-text model to use.
    public var modelID: GrokModelID
    /// An optional language hint.
    public var language: GrokLanguage?
    /// A Boolean value that indicates whether Grok should format the transcript.
    public var format: Bool
    /// A Boolean value that indicates whether Grok should process multichannel audio.
    public var multichannel: Bool
    /// The number of audio channels for multichannel processing.
    public var channels: Int?
    /// A Boolean value that indicates whether Grok should identify speakers.
    public var diarize: Bool
    /// The timestamp granularities to request.
    public var timestampGranularities: [GrokTimestampGranularity]
    /// The raw audio format, required for raw audio uploads.
    public var audioFormat: GrokAudioFormat?
    /// The raw audio sample rate, required for raw audio uploads.
    public var sampleRate: Int?
    /// The network timeout for the upload request.
    public var timeoutInterval: TimeInterval

    /// Creates Grok file transcription options.
    public init(
        modelID: GrokModelID = .stt,
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
        self.modelID = modelID
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

/// A word-level Grok timestamp.
public struct GrokWordTimestamp: Decodable, Sendable, Equatable {
    /// The word or token text.
    public let text: String
    /// The start time, in seconds.
    public let start: Double
    /// The end time, in seconds.
    public let end: Double
    /// The optional speaker index.
    public let speaker: Int?
}

/// A Grok transcript for one audio channel.
public struct GrokTranscriptionChannel: Decodable, Sendable, Equatable {
    /// The zero-based channel index.
    public let index: Int
    /// The transcribed channel text.
    public let text: String
    /// Optional word-level timestamps for this channel.
    public let words: [GrokWordTimestamp]?
}

/// A detailed Grok file transcription response.
public struct GrokFileTranscriptionResponse: Decodable, Sendable, Equatable {
    /// The transcribed text.
    public let text: String
    /// The detected or requested language code.
    public let language: String?
    /// The audio duration, in seconds.
    public let duration: Double?
    /// Optional word-level timestamps.
    public let words: [GrokWordTimestamp]?
    /// Optional per-channel transcripts.
    public let channels: [GrokTranscriptionChannel]?
}

struct GrokFileTranscriptionClient {
    static let defaultUploadURL = URL(string: "https://api.x.ai/v1/stt")

    private let credential: SpeechCredential
    private let urlSession: URLSession
    private let uploadURL: URL?
    private let maxUploadBytes: Int64 = 500 * 1024 * 1024

    init(apiKey: String, endpoint: URL? = nil, urlSession: URLSession = SpeechTransport.session()) {
        self.init(credential: .apiKey(apiKey), endpoint: endpoint, urlSession: urlSession)
    }

    init(credential: SpeechCredential, endpoint: URL? = nil, urlSession: URLSession = SpeechTransport.session()) {
        self.credential = credential
        self.urlSession = SpeechTransport.session(copying: urlSession, pinnedPublicKeyHashes: credential.pinnedPublicKeyHashes)
        self.uploadURL = endpoint ?? Self.defaultUploadURL
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
        if credential.optimizeUploads != nil, options.audioFormat != nil,
           options.audioFormat != .pcm || options.sampleRate == nil || options.channels != nil || options.multichannel {
            throw SpeechFailure(.unsupportedMediaType)
        }
        let rawPCM = options.audioFormat == .pcm ? options.sampleRate.map { SpeechRelayAudioImport.RawPCM(sampleRate: $0) } : nil
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .grok,
            optimizeUploads: credential.optimizeUploads, rawPCM: rawPCM, maxUploadBytes: maxUploadBytes)
        defer { prepared.remove() }
        let file = prepared.file
        var options = options
        if prepared.directory != nil {
            guard !options.multichannel, options.channels == nil else { throw SpeechFailure(.unsupportedMediaType) }
            options.audioFormat = nil
            options.sampleRate = nil
        }
        let request = try await makeAuthorizedRequest(file: file, options: options)
        let (data, response) = try await SpeechTransport.data(for: request, session: urlSession, prepare: self.credential.relayRequestPreparation)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .grok)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SpeechFailure(.server, statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(GrokFileTranscriptionResponse.self, from: data)
        } catch {
            throw SpeechError.decodingFailed(provider: .grok, reason: .decodingFailed)
        }
    }

    /// Builds an upload request, resolving the credential first.
    func makeAuthorizedRequest(
        file: URL,
        options: GrokFileTranscriptionOptions = GrokFileTranscriptionOptions()
    ) async throws -> URLRequest {
        guard credential.isConfigured else {
            throw SpeechError.providerNotConfigured(.grok)
        }
        try validate(options)
        let resolved = try await credential.resolved(for: .grok, model: options.modelID.rawValue, endpoint: uploadURL)
        return try makeRequest(file: file, options: options, secret: resolved.secret)
    }

    /// Builds an upload request from the configured long-lived API key.
    func makeRequest(
        file: URL,
        options: GrokFileTranscriptionOptions = GrokFileTranscriptionOptions()
    ) throws -> URLRequest {
        try makeRequest(file: file, options: options, secret: credential.staticAPIKey)
    }

    /// Builds an upload request from an already-resolved secret.
    ///
    /// Grok API keys and custom proxy credentials use Bearer authorization.
    /// Native vendor-token mode is unsupported for this capability.
    func makeRequest(
        file: URL,
        options: GrokFileTranscriptionOptions = GrokFileTranscriptionOptions(),
        secret: String
    ) throws -> URLRequest {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
                fileURL: credential.uploadFileURL(file),
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: credential.uploadFileURL(file))
            )
        ]
        parts.append(contentsOf: makeOptionParts(options))

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeoutInterval
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(boundary: boundary, parts: parts)
        return request
    }

    private func makeOptionParts(_ options: GrokFileTranscriptionOptions) -> [SpeechMultipartFormPart] {
        var parts: [SpeechMultipartFormPart] = [
            .text(name: "model", value: options.modelID.rawValue)
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
            throw SpeechError.providerFailure(provider: .grok, reason: .requestFailed)
        }

        if options.audioFormat != nil, options.sampleRate == nil {
            throw SpeechError.providerFailure(provider: .grok, reason: .requestFailed)
        }

        if let sampleRate = options.sampleRate,
           ![8000, 16000, 22050, 24000, 44100, 48000].contains(sampleRate) {
            throw SpeechError.providerFailure(provider: .grok, reason: .requestFailed)
        }

        if let channels = options.channels,
           !(2...8).contains(channels) {
            throw SpeechError.providerFailure(provider: .grok, reason: .requestFailed)
        }

        if options.timeoutInterval <= 0 {
            throw SpeechError.providerFailure(provider: .grok, reason: .requestFailed)
        }
    }

    private func readFileData(from fileURL: URL, options: GrokFileTranscriptionOptions) throws -> Data {
        do {
            if fileURL.pathExtension.isEmpty {
                throw SpeechError.providerFailure(provider: .grok, reason: .requestFailed)
            }
            if isRawAudio(fileURL) {
                if options.audioFormat == nil || options.sampleRate == nil {
                    throw SpeechError.providerFailure(provider: .grok, reason: .requestFailed)
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
            throw SpeechError.providerFailure(provider: .grok, reason: .requestFailed)
        }
    }

    private func isRawAudio(_ fileURL: URL) -> Bool {
        ["pcm", "mulaw", "alaw"].contains(fileURL.pathExtension.lowercased())
    }
}
