import Foundation

/// Meta speech-to-text model identifiers supported by SpeechKit.
public enum MetaModelID: String, Sendable, CaseIterable {
    /// Meta Muse Voice Transcribe 1.0.
    case museVoiceTranscribe1 = "muse-voice-transcribe-1.0"
}

/// Transcription modes supported by Meta Muse Voice Transcribe.
public enum MetaTranscriptionMode: String, Sendable, CaseIterable {
    /// One turn per session, ended by the client.
    case pushToTalk = "PUSH_TO_TALK"
    /// Server-side endpointing splits audio into turns.
    case endpointing = "ENDPOINTING"
    /// Server-side endpointing with speaker labels.
    case diarization = "DIARIZATION"
}

/// Audio encodings supported by Meta transcription requests.
public enum MetaAudioEncoding: String, Sendable, CaseIterable {
    /// WAV container audio, for prerecorded uploads.
    case wav = "WAV"
    /// Raw 24 kHz mono 16-bit little-endian PCM audio.
    case pcm24kHz = "PCM_24KHZ"
    /// Raw 16 kHz mono 16-bit little-endian PCM audio.
    case pcm16kHz = "PCM_16KHZ"

    /// The sample rate implied by the encoding, in hertz, when the encoding fixes one.
    public var sampleRate: Int? {
        switch self {
        case .wav:
            return nil
        case .pcm24kHz:
            return 24000
        case .pcm16kHz:
            return 16000
        }
    }
}

/// Meta language hints for transcription.
///
/// Meta biases transcription with language names instead of BCP-47 codes, so
/// each raw value is the name the API expects.
public enum MetaLanguage: String, Sendable, CaseIterable {
    /// Arabic.
    case arabic = "Arabic"
    /// Bengali.
    case bengali = "Bengali"
    /// Dutch.
    case dutch = "Dutch"
    /// English.
    case english = "English"
    /// French.
    case french = "French"
    /// German.
    case german = "German"
    /// Hebrew.
    case hebrew = "Hebrew"
    /// Hindi.
    case hindi = "Hindi"
    /// Indonesian.
    case indonesian = "Indonesian"
    /// Italian.
    case italian = "Italian"
    /// Japanese.
    case japanese = "Japanese"
    /// Kannada.
    case kannada = "Kannada"
    /// Korean.
    case korean = "Korean"
    /// Malay.
    case malay = "Malay"
    /// Mandarin Chinese.
    case mandarinChinese = "Mandarin Chinese"
    /// Marathi.
    case marathi = "Marathi"
    /// Polish.
    case polish = "Polish"
    /// Portuguese.
    case portuguese = "Portuguese"
    /// Spanish.
    case spanish = "Spanish"
    /// Tagalog.
    case tagalog = "Tagalog"
    /// Tamil.
    case tamil = "Tamil"
    /// Telugu.
    case telugu = "Telugu"
    /// Thai.
    case thai = "Thai"
    /// Turkish.
    case turkish = "Turkish"
    /// Vietnamese.
    case vietnamese = "Vietnamese"
}

/// Options for a Meta file transcription request.
public struct MetaFileTranscriptionOptions: Sendable, Equatable {
    /// The Meta transcription model to use.
    public var modelID: MetaModelID
    /// The transcription mode for the request.
    public var mode: MetaTranscriptionMode
    /// The encoding of the uploaded audio.
    public var audioEncoding: MetaAudioEncoding
    /// Language names that bias transcription.
    public var languageBias: [MetaLanguage]
    /// Literal terms that may appear in the recording.
    public var keywords: [String]
    /// An optional client-supplied session identifier.
    public var sessionID: String?
    /// The network timeout for the upload request.
    public var timeoutInterval: TimeInterval

    /// Creates Meta file transcription options.
    public init(
        modelID: MetaModelID = .museVoiceTranscribe1,
        mode: MetaTranscriptionMode = .endpointing,
        audioEncoding: MetaAudioEncoding = .wav,
        languageBias: [MetaLanguage] = [],
        keywords: [String] = [],
        sessionID: String? = nil,
        timeoutInterval: TimeInterval = 10 * 60
    ) {
        self.modelID = modelID
        self.mode = mode
        self.audioEncoding = audioEncoding
        self.languageBias = languageBias
        self.keywords = keywords
        self.sessionID = sessionID
        self.timeoutInterval = timeoutInterval
    }
}

/// One Meta transcription turn.
public struct MetaTranscriptionTurn: Decodable, Sendable, Equatable {
    /// The turn identifier assigned by Meta.
    public let turnID: Int
    /// The turn start time, in milliseconds.
    public let startMs: Int
    /// The turn end time, in milliseconds.
    public let endMs: Int
    /// The transcribed turn text.
    public let transcript: String
    /// The speaker label, when the request used diarization.
    public let speaker: String?

    private enum CodingKeys: String, CodingKey {
        case turnID = "turnId"
        case startMs
        case endMs
        case transcript
        case speaker
    }
}

/// A detailed Meta file transcription response.
public struct MetaFileTranscriptionResponse: Decodable, Sendable, Equatable {
    /// The session identifier assigned by Meta.
    public let sessionID: String?
    /// The transcribed text.
    public let transcript: String
    /// The audio duration, in milliseconds.
    public let audioDurationMs: Int?
    /// The transcription turns, when the request mode produces them.
    public let turns: [MetaTranscriptionTurn]?

    /// The transcribed text.
    public var text: String { transcript }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case transcript
        case audioDurationMs
        case turns
    }
}

struct MetaFileTranscriptionClient {
    static let defaultUploadURL = URL(string: "https://api.meta.ai/v1/asr/transcribe")

    private let credential: SpeechCredential
    private let urlSession: URLSession
    private let uploadURL: URL?
    private let maxUploadBytes: Int64 = 32 * 1024 * 1024
    private let maxUploadDuration: TimeInterval = 600

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
        options: MetaFileTranscriptionOptions = MetaFileTranscriptionOptions()
    ) async throws -> String {
        let response = try await transcribeAudioFileDetailed(file: file, options: options)
        return response.text
    }

    func transcribeAudioFileDetailed(
        file: URL,
        options: MetaFileTranscriptionOptions = MetaFileTranscriptionOptions()
    ) async throws -> MetaFileTranscriptionResponse {
        let request = try await makeRequest(file: file, options: options)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .meta)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SpeechError.uploadFailed(provider: .meta, reason: message)
        }

        do {
            return try JSONDecoder().decode(MetaFileTranscriptionResponse.self, from: data)
        } catch {
            throw SpeechError.decodingFailed(provider: .meta, reason: error.localizedDescription)
        }
    }

    func makeRequest(
        file: URL,
        options: MetaFileTranscriptionOptions = MetaFileTranscriptionOptions()
    ) async throws -> URLRequest {
        guard credential.isConfigured else {
            throw SpeechError.providerNotConfigured(.meta)
        }
        let resolved = try await credential.resolved(for: .meta)
        return try await makeRequest(file: file, options: options, secret: resolved.secret)
    }

    /// Builds an upload request from an already-resolved secret.
    ///
    /// Meta accepts both a long-lived API key and a short-lived token as a
    /// bearer token.
    func makeRequest(
        file: URL,
        options: MetaFileTranscriptionOptions = MetaFileTranscriptionOptions(),
        secret: String
    ) async throws -> URLRequest {
        guard !secret.isEmpty else {
            throw SpeechError.providerNotConfigured(.meta)
        }
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .meta)
        }

        try validate(options)
        try SpeechFileUploadSupport.validateFileExtension(
            file,
            allowedExtensions: allowedExtensions(for: options.audioEncoding),
            provider: .meta
        )
        try SpeechFileUploadSupport.validateFileSize(file, maxUploadBytes: maxUploadBytes, provider: .meta)
        try await SpeechFileUploadSupport.validateFileDuration(
            file,
            maxDuration: maxUploadDuration,
            provider: .meta
        )
        if let sampleRate = options.audioEncoding.sampleRate {
            // AVFoundation reads no duration from headerless PCM, but the byte
            // count and the fixed bit rate give it exactly.
            try SpeechFileUploadSupport.validateRawPCMDuration(
                fileURL: file,
                sampleRate: sampleRate,
                maxDuration: maxUploadDuration,
                provider: .meta
            )
        }

        let audioData = try readFileData(from: file)
        let payload = try makeRequestPayload(options)
        let boundary = "SpeechKit-\(UUID().uuidString)"
        let parts: [SpeechMultipartFormPart] = [
            .json(name: "request", data: payload),
            .file(
                name: "audio",
                fileURL: file,
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: file)
            )
        ]

        var request = URLRequest(url: try makeUploadURL(uploadURL, sessionID: options.sessionID))
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeoutInterval
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(boundary: boundary, parts: parts)
        return request
    }

    private func makeUploadURL(_ uploadURL: URL, sessionID: String?) throws -> URL {
        guard let sessionID, !sessionID.isEmpty else {
            return uploadURL
        }
        guard var components = URLComponents(url: uploadURL, resolvingAgainstBaseURL: false) else {
            throw SpeechError.invalidResponse(provider: .meta)
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "sessionId", value: sessionID))
        components.queryItems = queryItems
        guard let url = components.url else {
            throw SpeechError.invalidResponse(provider: .meta)
        }
        return url
    }

    private func makeRequestPayload(_ options: MetaFileTranscriptionOptions) throws -> Data {
        let payload = MetaTranscribeRequestPayload(
            mode: options.mode.rawValue,
            model: options.modelID.rawValue,
            audioEncoding: options.audioEncoding.rawValue,
            languageBias: options.languageBias.map(\.rawValue),
            keywords: options.keywords
        )

        do {
            return try JSONEncoder().encode(payload)
        } catch {
            throw SpeechError.providerFailure(provider: .meta, reason: error.localizedDescription)
        }
    }

    private func validate(_ options: MetaFileTranscriptionOptions) throws {
        if let keyword = options.keywords.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw SpeechError.providerFailure(provider: .meta, reason: "keywords cannot be empty: \"\(keyword)\".")
        }

        if options.keywords.contains(where: { $0.contains(where: \.isNewline) }) {
            throw SpeechError.providerFailure(provider: .meta, reason: "keywords cannot contain newlines.")
        }

        if options.timeoutInterval <= 0 {
            throw SpeechError.providerFailure(provider: .meta, reason: "timeoutInterval must be greater than 0.")
        }
    }

    private func allowedExtensions(for audioEncoding: MetaAudioEncoding) -> Set<String> {
        switch audioEncoding {
        case .wav:
            return ["wav"]
        case .pcm24kHz, .pcm16kHz:
            return ["pcm", "raw"]
        }
    }

    private func readFileData(from fileURL: URL) throws -> Data {
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw SpeechError.providerFailure(provider: .meta, reason: error.localizedDescription)
        }
    }
}

struct MetaTranscribeRequestPayload: Encodable, Sendable {
    let mode: String
    let model: String
    let audioEncoding: String
    let languageBias: [String]
    let keywords: [String]
}
