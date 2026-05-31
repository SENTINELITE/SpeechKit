import Foundation

struct ElevenLabsFileTranscriptionResponse: Decodable, Sendable {
    let text: String
    let languageCode: String?
    let words: [ElevenLabsWordTimestamp]?

    private enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case words
    }
}

struct ElevenLabsFileTranscriptionClient {
    private let apiKey: String
    private let urlSession: URLSession
    private let uploadURL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")
    private let maxUploadBytes: Int64 = 3 * 1024 * 1024 * 1024
    private let maxUploadDuration: TimeInterval = 10 * 60 * 60

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func transcribeAudioFile(file: URL, modelID: ElevenLabsModelID) async throws -> String {
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
            let decoded = try JSONDecoder().decode(ElevenLabsFileTranscriptionResponse.self, from: data)
            return decoded.text
        } catch {
            throw ElevenLabsError.decodingFailed(error.localizedDescription)
        }
    }

    func makeRequest(file: URL, modelID: ElevenLabsModelID) async throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw ElevenLabsError.apiKeyMissing
        }
        guard modelID == .scribeV1 || modelID == .scribeV2 else {
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
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
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
}
