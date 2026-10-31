import Foundation

/// A detailed ElevenLabs file transcription response.
public struct ElevenLabsFileTranscriptionResponse: Decodable, Sendable, Equatable {
    /// The transcribed text.
    public let text: String
    /// The detected or requested language code.
    public let languageCode: String?
    /// Optional word-level timestamps.
    public let words: [ElevenLabsWordTimestamp]?

    private enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case words
    }
}

struct ElevenLabsFileTranscriptionClient {
    static let defaultUploadURL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")

    private let credential: SpeechCredential
    private let urlSession: URLSession
    private let uploadURL: URL?
    private let maxUploadBytes: Int64 = 3 * 1024 * 1024 * 1024
    private let maxUploadDuration: TimeInterval = 10 * 60 * 60

    init(apiKey: String, endpoint: URL? = nil, urlSession: URLSession = SpeechTransport.session()) {
        self.init(credential: .apiKey(apiKey), endpoint: endpoint, urlSession: urlSession)
    }

    init(credential: SpeechCredential, endpoint: URL? = nil, urlSession: URLSession = SpeechTransport.session()) {
        self.credential = credential
        self.urlSession = SpeechTransport.session(copying: urlSession, pinnedPublicKeyHashes: credential.pinnedPublicKeyHashes)
        self.uploadURL = endpoint ?? Self.defaultUploadURL
    }

    func transcribeAudioFile(file: URL, modelID: ElevenLabsModelID) async throws -> String {
        let response = try await transcribeAudioFileDetailed(file: file, modelID: modelID)
        return response.text
    }

    func transcribeAudioFileDetailed(
        file: URL,
        modelID: ElevenLabsModelID
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .elevenLabs,
            optimizeUploads: credential.optimizeUploads, maxUploadBytes: maxUploadBytes, maxDuration: maxUploadDuration)
        defer { prepared.remove() }
        let file = prepared.file
        let request = try await makeRequest(file: file, modelID: modelID)
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

    func makeRequest(file: URL, modelID: ElevenLabsModelID) async throws -> URLRequest {
        guard credential.isConfigured else {
            throw ElevenLabsError.apiKeyMissing
        }
        let resolved = try await credential.resolved(for: .elevenLabs, model: modelID.rawValue, endpoint: uploadURL)
        var request = try await makeRequest(file: file, modelID: modelID, secret: resolved.secret)
        request.setValue(nil, forHTTPHeaderField: "xi-api-key")
        try resolved.authorize(&request, provider: .elevenLabs, capability: .fileTranscription)
        return request
    }

    /// Builds an upload request from an already-resolved secret.
    ///
    /// API keys use `xi-api-key`; the resolved-credential overload places
    /// native vendor tokens in the `token` query parameter.
    func makeRequest(file: URL, modelID: ElevenLabsModelID, secret: String) async throws -> URLRequest {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElevenLabsError.apiKeyMissing
        }
        guard modelID.supportsFileTranscription else {
            throw ElevenLabsError.unsupportedModel(.invalidOptions)
        }
        guard let uploadURL else {
            throw ElevenLabsError.invalidURL
        }

        try await SpeechFileUploadSupport.validateFileForUpload(
            file,
            maxUploadBytes: maxUploadBytes,
            maxUploadDuration: maxUploadDuration
        )
        let audioData = try SpeechFileUploadSupport.readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(secret, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(
            boundary: boundary,
            parts: [
                .text(name: "model_id", value: modelID.rawValue),
                .file(
                    name: "file",
                    fileURL: credential.uploadFileURL(file),
                    fileData: audioData,
                    contentType: SpeechFileUploadSupport.mimeType(for: credential.uploadFileURL(file))
                )
            ]
        )
        return request
    }

    private func resolvedSecret() async throws -> String {
        try await credential.resolved(for: .elevenLabs, endpoint: uploadURL).secret
    }
}
