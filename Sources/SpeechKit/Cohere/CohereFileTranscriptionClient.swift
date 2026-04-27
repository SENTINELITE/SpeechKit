import Foundation

public enum CohereModelID: String, Sendable, CaseIterable {
    case transcribe032026 = "cohere-transcribe-03-2026"
}

struct CohereFileTranscriptionClient {
    struct Response: Decodable, Sendable {
        let text: String
    }

    private let apiKey: String
    private let urlSession: URLSession
    private let uploadURL = URL(string: "https://api.cohere.com/v2/audio/transcriptions")

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func transcribeAudioFile(
        file: URL,
        modelId: CohereModelID,
        language: String,
        temperature: Double?
    ) async throws -> String {
        let request = try await makeRequest(file: file, modelId: modelId, language: language, temperature: temperature)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .cohere)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SpeechError.uploadFailed(provider: .cohere, reason: message)
        }

        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.text
        } catch {
            throw SpeechError.decodingFailed(provider: .cohere, reason: error.localizedDescription)
        }
    }

    func makeRequest(
        file: URL,
        modelId: CohereModelID,
        language: String,
        temperature: Double?
    ) async throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw SpeechError.providerNotConfigured(.cohere)
        }
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .cohere)
        }

        let audioData = try SpeechFileUploadSupport.readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"
        var parts: [SpeechMultipartFormPart] = [
            .text(name: "model", value: modelId.rawValue),
            .text(name: "language", value: language),
            .file(
                name: "file",
                fileURL: file,
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: file)
            )
        ]

        if let temperature {
            parts.insert(.text(name: "temperature", value: String(temperature)), at: 2)
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(boundary: boundary, parts: parts)
        return request
    }
}
