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

    init(apiKey: String, endpoint: URL? = nil, urlSession: URLSession = .shared) {
        self.init(credential: .apiKey(apiKey), endpoint: endpoint, urlSession: urlSession)
    }

    init(credential: SpeechCredential, endpoint: URL? = nil, urlSession: URLSession = .shared) {
        self.credential = credential
        self.urlSession = urlSession
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
        let request = try await makeRequest(file: file, modelID: modelID)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.uploadFailed("Invalid response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw ElevenLabsError.uploadFailed(message)
        }

        do {
            return try JSONDecoder().decode(ElevenLabsFileTranscriptionResponse.self, from: data)
        } catch {
            throw ElevenLabsError.decodingFailed(error.localizedDescription)
        }
    }

    func makeRequest(file: URL, modelID: ElevenLabsModelID) async throws -> URLRequest {
        guard credential.isConfigured else {
            throw ElevenLabsError.apiKeyMissing
        }
        let resolved = try await resolvedSecret()
        return try await makeRequest(file: file, modelID: modelID, secret: resolved)
    }

    /// Builds an upload request from an already-resolved secret.
    ///
    /// ElevenLabs accepts both a long-lived API key and a short-lived token in
    /// the `xi-api-key` header for file transcription.
    func makeRequest(file: URL, modelID: ElevenLabsModelID, secret: String) async throws -> URLRequest {
        guard !secret.isEmpty else {
            throw ElevenLabsError.apiKeyMissing
        }
        guard modelID.supportsFileTranscription else {
            throw ElevenLabsError.unsupportedModel(modelID.rawValue)
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
                    fileURL: file,
                    fileData: audioData,
                    contentType: SpeechFileUploadSupport.mimeType(for: file)
                )
            ]
        )
        return request
    }

    private func resolvedSecret() async throws -> String {
        try await credential.resolved(for: .elevenLabs).secret
    }
}
