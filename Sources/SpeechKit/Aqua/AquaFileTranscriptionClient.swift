import Foundation

public enum AquaModelID: String, Sendable, CaseIterable {
    case avalonV15 = "avalon-v1.5"
}

public enum AquaLanguage: String, Sendable, CaseIterable {
    case auto
    case english = "en"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case japanese = "ja"
    case russian = "ru"
}

public struct AquaFileTranscriptionOptions: Sendable, Equatable {
    public var modelId: AquaModelID
    public var language: AquaLanguage?

    public init(
        modelId: AquaModelID = .avalonV15,
        language: AquaLanguage? = nil
    ) {
        self.modelId = modelId
        self.language = language
    }
}

public struct AquaFileTranscriptionResponse: Decodable, Sendable, Equatable {
    public struct Usage: Decodable, Sendable, Equatable {
        public let type: String
        public let seconds: Double
    }

    public let text: String
    public let usage: Usage
    public let requestId: String

    private enum CodingKeys: String, CodingKey {
        case text
        case usage
        case requestId = "_request_id"
    }
}

struct AquaFileTranscriptionClient {
    private let apiKey: String
    private let urlSession: URLSession
    private let uploadURL = URL(string: "https://api.aquavoice.com/api/v1/audio/transcriptions")
    private let allowedExtensions: Set<String> = ["flac", "mp3", "mp4", "mpeg", "mpga", "m4a", "ogg", "wav", "webm"]

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    func transcribeAudioFile(
        file: URL,
        options: AquaFileTranscriptionOptions = AquaFileTranscriptionOptions()
    ) async throws -> String {
        let response = try await transcribeAudioFileDetailed(file: file, options: options)
        return response.text
    }

    func transcribeAudioFileDetailed(
        file: URL,
        options: AquaFileTranscriptionOptions = AquaFileTranscriptionOptions()
    ) async throws -> AquaFileTranscriptionResponse {
        let request = try makeRequest(file: file, options: options)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .aqua)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SpeechError.uploadFailed(provider: .aqua, reason: message)
        }

        do {
            return try JSONDecoder().decode(AquaFileTranscriptionResponse.self, from: data)
        } catch {
            throw SpeechError.decodingFailed(provider: .aqua, reason: error.localizedDescription)
        }
    }

    func makeRequest(
        file: URL,
        options: AquaFileTranscriptionOptions = AquaFileTranscriptionOptions()
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw SpeechError.providerNotConfigured(.aqua)
        }
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .aqua)
        }

        try SpeechFileUploadSupport.validateFileExtension(file, allowedExtensions: allowedExtensions, provider: .aqua)
        let audioData = try readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"
        var parts: [SpeechMultipartFormPart] = [
            .file(
                name: "file",
                fileURL: file,
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: file)
            ),
            .text(name: "model", value: options.modelId.rawValue)
        ]

        if let language = options.language {
            parts.append(.text(name: "language", value: language.rawValue))
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
            throw SpeechError.providerFailure(provider: .aqua, reason: error.localizedDescription)
        }
    }
}
