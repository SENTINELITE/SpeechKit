import Foundation

/// A detailed ElevenLabs file transcription response.
public struct ElevenLabsFileTranscriptionResponse: Decodable, Sendable, Equatable {
    /// The transcribed text.
    public let text: String
    /// The detected or requested language code.
    public let languageCode: String?
    /// The model's confidence in the detected language, from 0 to 1.
    public let languageProbability: Double?
    /// The duration of the processed audio, in seconds.
    public let audioDurationSeconds: Double?
    /// The transcription identifier ElevenLabs assigned to the request.
    public let transcriptionID: String?
    /// Optional word-level timestamps, including speaker labels when the request used diarization.
    public let words: [ElevenLabsWordTimestamp]?
    /// The entities ElevenLabs detected, when the request used entity detection.
    public let entities: [ElevenLabsEntity]?

    private enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case languageProbability = "language_probability"
        case audioDurationSeconds = "audio_duration_secs"
        case transcriptionID = "transcription_id"
        case words
        case entities
    }
}

struct ElevenLabsFileTranscriptionClient {
    static let defaultUploadURL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")

    private let credential: SpeechCredential
    private let urlSession: URLSession
    private let uploadURL: URL?
    private let maxUploadBytes: Int64 = 5 * 1024 * 1024 * 1024
    private let maxUploadDuration: TimeInterval = 15 * 60 * 60

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
        options: ElevenLabsFileTranscriptionOptions = ElevenLabsFileTranscriptionOptions()
    ) async throws -> String {
        let response = try await transcribeAudioFileDetailed(file: file, options: options)
        return response.text
    }

    func transcribeAudioFile(file: URL, modelID: ElevenLabsModelID) async throws -> String {
        try await transcribeAudioFile(file: file, options: ElevenLabsFileTranscriptionOptions(modelID: modelID))
    }

    func transcribeAudioFileDetailed(
        file: URL,
        options: ElevenLabsFileTranscriptionOptions = ElevenLabsFileTranscriptionOptions()
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        try options.validate()
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .elevenLabs,
            optimizeUploads: credential.optimizeUploads, maxUploadBytes: maxUploadBytes, maxDuration: maxUploadDuration)
        defer { prepared.remove() }
        let file = prepared.file
        let request = try await makeRequest(file: file, options: options)
        let (data, response) = try await SpeechTransport.data(for: request, session: urlSession, prepare: self.credential.relayRequestPreparation)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.uploadFailed(.requestFailed)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SpeechFailure(.server, statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(ElevenLabsFileTranscriptionResponse.self, from: data)
        } catch {
            throw ElevenLabsError.decodingFailed(.decodingFailed)
        }
    }

    func transcribeAudioFileDetailed(
        file: URL,
        modelID: ElevenLabsModelID
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        try await transcribeAudioFileDetailed(file: file, options: ElevenLabsFileTranscriptionOptions(modelID: modelID))
    }

    func makeRequest(
        file: URL,
        options: ElevenLabsFileTranscriptionOptions = ElevenLabsFileTranscriptionOptions()
    ) async throws -> URLRequest {
        guard credential.isConfigured else {
            throw ElevenLabsError.apiKeyMissing
        }
        try options.validate()
        let resolved = try await credential.resolved(for: .elevenLabs, model: options.modelID.rawValue, endpoint: uploadURL)
        var request = try await makeRequest(file: file, options: options, secret: resolved.secret)
        request.setValue(nil, forHTTPHeaderField: "xi-api-key")
        try resolved.authorize(&request, provider: .elevenLabs, capability: .fileTranscription)
        return request
    }

    func makeRequest(file: URL, modelID: ElevenLabsModelID) async throws -> URLRequest {
        try await makeRequest(file: file, options: ElevenLabsFileTranscriptionOptions(modelID: modelID))
    }

    /// Builds an upload request from an already-resolved secret.
    ///
    /// API keys use `xi-api-key`; the resolved-credential overload places
    /// native vendor tokens in the `token` query parameter.
    func makeRequest(
        file: URL,
        options: ElevenLabsFileTranscriptionOptions,
        secret: String
    ) async throws -> URLRequest {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElevenLabsError.apiKeyMissing
        }
        guard let uploadURL else {
            throw ElevenLabsError.invalidURL
        }

        try options.validate()
        try await SpeechFileUploadSupport.validateFileForUpload(
            file,
            maxUploadBytes: maxUploadBytes,
            maxUploadDuration: maxUploadDuration
        )
        let audioData = try SpeechFileUploadSupport.readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"

        var parts: [SpeechMultipartFormPart] = [
            .text(name: "model_id", value: options.modelID.rawValue)
        ]
        if let language = options.language {
            parts.append(.text(name: "language_code", value: language))
        }
        for code in options.secondaryLanguages {
            parts.append(.text(name: "secondary_language_codes", value: code))
        }
        if let numbersFormat = options.numbersFormat {
            parts.append(.text(name: "numbers_format", value: numbersFormat.rawValue))
        }
        if options.diarize {
            parts.append(.text(name: "diarize", value: "true"))
        }
        if let speakerCount = options.speakerCount {
            parts.append(.text(name: "num_speakers", value: String(speakerCount)))
        }
        if let threshold = options.diarizationThreshold {
            parts.append(.text(name: "diarization_threshold", value: String(threshold)))
        }
        for keyterm in options.keyterms {
            parts.append(.text(name: "keyterms", value: keyterm))
        }
        if options.tagAudioEvents {
            parts.append(.text(name: "tag_audio_events", value: "true"))
        }
        if options.noVerbatim {
            parts.append(.text(name: "no_verbatim", value: "true"))
        }
        for value in options.entityDetectionValues {
            parts.append(.text(name: "entity_detection", value: value))
        }
        parts.append(
            .file(
                name: "file",
                fileURL: credential.uploadFileURL(file),
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: credential.uploadFileURL(file))
            )
        )

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeoutInterval
        request.setValue(secret, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(boundary: boundary, parts: parts)
        return request
    }

    private func resolvedSecret() async throws -> String {
        try await credential.resolved(for: .elevenLabs, endpoint: uploadURL).secret
    }
}
