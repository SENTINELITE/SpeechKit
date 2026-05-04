import Foundation

/// Aqua transcription model identifiers supported by SpeechKit.
public enum AquaModelID: String, Sendable, CaseIterable {
    /// Aqua Avalon v1.5.
    case avalonV15 = "avalon-v1.5"
}

/// Aqua language hints for file transcription.
public enum AquaLanguage: String, Sendable, CaseIterable {
    /// Ask Aqua to detect the language automatically.
    case auto
    /// English.
    case english = "en"
    /// German.
    case german = "de"
    /// Spanish.
    case spanish = "es"
    /// French.
    case french = "fr"
    /// Japanese.
    case japanese = "ja"
    /// Russian.
    case russian = "ru"
}

/// Options for an Aqua file transcription request.
public struct AquaFileTranscriptionOptions: Sendable, Equatable {
    /// The Aqua transcription model to use.
    public var modelID: AquaModelID
    /// An optional language hint.
    public var language: AquaLanguage?

    /// Creates Aqua file transcription options.
    public init(
        modelID: AquaModelID = .avalonV15,
        language: AquaLanguage? = nil
    ) {
        self.modelID = modelID
        self.language = language
    }
}

/// A detailed Aqua file transcription response.
public struct AquaFileTranscriptionResponse: Decodable, Sendable, Equatable {
    /// Aqua usage metadata for the transcription request.
    public struct Usage: Decodable, Sendable, Equatable {
        /// The usage unit reported by Aqua.
        public let type: String
        /// The number of billable audio seconds reported by Aqua.
        public let seconds: Double
    }

    /// The transcribed text.
    public let text: String
    /// Usage metadata for the request.
    public let usage: Usage
    /// Aqua's request identifier.
    public let requestID: String

    private enum CodingKeys: String, CodingKey {
        case text
        case usage
        case requestID = "_request_id"
    }
}

struct AquaFileTranscriptionClient {
    private let apiKey: String
    private let urlSession: URLSession
    private let uploadURL = URL(string: "https://api.aquavoice.com/api/v1/audio/transcriptions")
    private let maxUploadBytes: Int64 = 25 * 1024 * 1024
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
        try SpeechFileUploadSupport.validateFileSize(file, maxUploadBytes: maxUploadBytes, provider: .aqua)
        let audioData = try readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"
        var parts: [SpeechMultipartFormPart] = [
            .file(
                name: "file",
                fileURL: file,
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: file)
            ),
            .text(name: "model", value: options.modelID.rawValue)
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
