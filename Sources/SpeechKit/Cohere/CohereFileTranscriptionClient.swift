import Foundation

/// Cohere transcription model identifiers supported by SpeechKit.
public enum CohereModelID: String, Sendable, CaseIterable {
    /// Cohere Transcribe model released in March 2026.
    case transcribe032026 = "cohere-transcribe-03-2026"
}

/// Cohere language hints for file transcription.
public enum CohereLanguage: String, Sendable, CaseIterable {
    /// English.
    case english = "en"
    /// German.
    case german = "de"
    /// French.
    case french = "fr"
    /// Italian.
    case italian = "it"
    /// Spanish.
    case spanish = "es"
    /// Portuguese.
    case portuguese = "pt"
    /// Greek.
    case greek = "el"
    /// Dutch.
    case dutch = "nl"
    /// Polish.
    case polish = "pl"
    /// Vietnamese.
    case vietnamese = "vi"
    /// Chinese.
    case chinese = "zh"
    /// Arabic.
    case arabic = "ar"
    /// Japanese.
    case japanese = "ja"
    /// Korean.
    case korean = "ko"
}

struct CohereFileTranscriptionClient {
    struct Response: Decodable, Sendable {
        let text: String
    }

    private let apiKey: String
    private let urlSession: URLSession
    private let uploadURL = URL(string: "https://api.cohere.com/v2/audio/transcriptions")
    private let maxUploadBytes: Int64 = 25 * 1024 * 1024
    private let allowedExtensions: Set<String> = ["flac", "mp3", "mpeg", "mpga", "ogg", "wav"]

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func transcribeAudioFile(
        file: URL,
        modelID: CohereModelID,
        language: CohereLanguage,
        temperature: Double?
    ) async throws -> String {
        let request = try await makeRequest(file: file, modelID: modelID, language: language, temperature: temperature)
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
        modelID: CohereModelID,
        language: CohereLanguage,
        temperature: Double?
    ) async throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw SpeechError.providerNotConfigured(.cohere)
        }
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .cohere)
        }

        try SpeechFileUploadSupport.validateFileExtension(file, allowedExtensions: allowedExtensions, provider: .cohere)
        try SpeechFileUploadSupport.validateFileSize(file, maxUploadBytes: maxUploadBytes, provider: .cohere)
        let audioData = try readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"
        var parts: [SpeechMultipartFormPart] = [
            .text(name: "model", value: modelID.rawValue),
            .text(name: "language", value: language.rawValue),
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

    private func readFileData(from fileURL: URL) throws -> Data {
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw SpeechError.providerFailure(provider: .cohere, reason: error.localizedDescription)
        }
    }
}
