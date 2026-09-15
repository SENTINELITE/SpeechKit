import Foundation

/// A resumable uploader for the Gemini Files API.
///
/// Gemini rejects inline audio above the request body limit, so large recordings
/// are uploaded here first and referenced by URI in the transcription request.
struct GeminiFilesClient {
    /// A file that finished uploading and became active.
    struct UploadedFile: Sendable, Equatable {
        let name: String
        let uri: String
        let mimeType: String
    }

    static let defaultUploadURL = URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files")

    private let credential: SpeechCredential
    private let urlSession: URLSession
    private let uploadURL: URL?
    private let statePollInterval: TimeInterval
    private let maxStatePollAttempts: Int

    init(
        apiKey: String,
        endpoint: URL? = nil,
        urlSession: URLSession = .shared,
        statePollInterval: TimeInterval = 1,
        maxStatePollAttempts: Int = 60
    ) {
        self.init(
            credential: .apiKey(apiKey),
            endpoint: endpoint,
            urlSession: urlSession,
            statePollInterval: statePollInterval,
            maxStatePollAttempts: maxStatePollAttempts
        )
    }

    init(
        credential: SpeechCredential,
        endpoint: URL? = nil,
        urlSession: URLSession = .shared,
        statePollInterval: TimeInterval = 1,
        maxStatePollAttempts: Int = 60
    ) {
        self.credential = credential
        self.urlSession = urlSession
        self.uploadURL = endpoint ?? Self.defaultUploadURL
        self.statePollInterval = statePollInterval
        self.maxStatePollAttempts = maxStatePollAttempts
    }

    /// Uploads a file with the resumable protocol and waits until Gemini reports it as active.
    func upload(
        file: URL,
        mimeType: String,
        timeoutInterval: TimeInterval
    ) async throws -> UploadedFile {
        let audioData = try readFileData(from: file)
        guard credential.isConfigured else {
            throw SpeechError.providerNotConfigured(.gemini)
        }
        let resolved = try await credential.resolved(for: .gemini)

        let startRequest = try makeStartRequest(
            file: file,
            mimeType: mimeType,
            byteCount: audioData.count,
            timeoutInterval: timeoutInterval,
            credential: resolved
        )
        let (startData, startResponse) = try await urlSession.data(for: startRequest)
        let startHTTPResponse = try httpResponse(from: startResponse)
        try validateStatusCode(startHTTPResponse, data: startData)

        guard let sessionURLString = startHTTPResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let sessionURL = URL(string: sessionURLString) else {
            throw SpeechError.uploadFailed(
                provider: .gemini,
                reason: "The Gemini Files API did not return a resumable upload URL."
            )
        }

        var uploadRequest = makeUploadRequest(
            sessionURL: sessionURL,
            byteCount: audioData.count,
            timeoutInterval: timeoutInterval
        )
        uploadRequest.httpBody = audioData

        let (uploadData, uploadResponse) = try await urlSession.data(for: uploadRequest)
        let uploadHTTPResponse = try httpResponse(from: uploadResponse)
        try validateStatusCode(uploadHTTPResponse, data: uploadData)

        let resource = try decodeFileResource(from: uploadData)
        return try await activeFile(from: resource, timeoutInterval: timeoutInterval, credential: resolved)
    }

    /// Builds a resumable upload start request from the configured long-lived API key.
    func makeStartRequest(
        file: URL,
        mimeType: String,
        byteCount: Int,
        timeoutInterval: TimeInterval
    ) throws -> URLRequest {
        try makeStartRequest(
            file: file,
            mimeType: mimeType,
            byteCount: byteCount,
            timeoutInterval: timeoutInterval,
            credential: .apiKey(credential.staticAPIKey)
        )
    }

    /// Builds a resumable upload start request from an already-resolved credential.
    func makeStartRequest(
        file: URL,
        mimeType: String,
        byteCount: Int,
        timeoutInterval: TimeInterval,
        credential: SpeechResolvedCredential
    ) throws -> URLRequest {
        guard !credential.isEmpty else {
            throw SpeechError.providerNotConfigured(.gemini)
        }
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .gemini)
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        GeminiRESTAuthorization.apply(credential, to: &request)
        request.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue("\(byteCount)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        request.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let displayName = file.lastPathComponent.isEmpty ? "audio" : file.lastPathComponent
        do {
            request.httpBody = try JSONEncoder().encode(GeminiFileUploadMetadata(displayName: displayName))
        } catch {
            throw SpeechError.providerFailure(provider: .gemini, reason: error.localizedDescription)
        }
        return request
    }

    func makeUploadRequest(
        sessionURL: URL,
        byteCount: Int,
        timeoutInterval: TimeInterval
    ) -> URLRequest {
        var request = URLRequest(url: sessionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("\(byteCount)", forHTTPHeaderField: "Content-Length")
        request.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        request.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        return request
    }

    /// Builds a file state request from the configured long-lived API key.
    func makeStateRequest(fileName: String, timeoutInterval: TimeInterval) throws -> URLRequest {
        try makeStateRequest(
            fileName: fileName,
            timeoutInterval: timeoutInterval,
            credential: .apiKey(credential.staticAPIKey)
        )
    }

    /// Builds a file state request from an already-resolved credential.
    ///
    /// The polled URL is built relative to the configured upload endpoint, so a
    /// proxy override keeps both requests on the same host.
    func makeStateRequest(
        fileName: String,
        timeoutInterval: TimeInterval,
        credential: SpeechResolvedCredential
    ) throws -> URLRequest {
        guard !credential.isEmpty else {
            throw SpeechError.providerNotConfigured(.gemini)
        }

        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = try stateURL(forFileName: trimmed) else {
            throw SpeechError.uploadFailed(
                provider: .gemini,
                reason: "The Gemini Files API did not return a file name."
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        GeminiRESTAuthorization.apply(credential, to: &request)
        return request
    }

    /// Maps the resumable upload endpoint onto the Files API resource URL for one file.
    private func stateURL(forFileName fileName: String) throws -> URL? {
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .gemini)
        }
        guard var components = URLComponents(url: uploadURL, resolvingAgainstBaseURL: false) else {
            throw SpeechError.invalidResponse(provider: .gemini)
        }

        var path = components.path
        if let uploadRange = path.range(of: "/upload/") {
            path.replaceSubrange(uploadRange, with: "/")
        }
        if path.hasSuffix("/files") {
            path.removeLast("files".count)
        }
        if !path.hasSuffix("/") {
            path += "/"
        }
        components.path = path + fileName
        return components.url
    }

    func decodeFileResource(from data: Data) throws -> GeminiFileResource {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(GeminiFileEnvelope.self, from: data), let file = envelope.file {
            return file
        }
        do {
            return try decoder.decode(GeminiFileResource.self, from: data)
        } catch {
            throw SpeechError.decodingFailed(provider: .gemini, reason: error.localizedDescription)
        }
    }

    private func activeFile(
        from resource: GeminiFileResource,
        timeoutInterval: TimeInterval,
        credential: SpeechResolvedCredential
    ) async throws -> UploadedFile {
        var latest = resource
        var attempt = 0

        while true {
            switch latest.state?.uppercased() {
            case "ACTIVE":
                return try uploadedFile(from: latest)
            case "FAILED":
                throw SpeechError.uploadFailed(
                    provider: .gemini,
                    reason: latest.error?.message ?? "The Gemini Files API failed to process the upload."
                )
            default:
                break
            }

            guard let name = latest.name, !name.isEmpty else {
                throw SpeechError.uploadFailed(
                    provider: .gemini,
                    reason: "The Gemini Files API did not return a file name."
                )
            }
            guard attempt < maxStatePollAttempts else {
                throw SpeechError.uploadFailed(
                    provider: .gemini,
                    reason: "The uploaded file \(name) did not become active in time."
                )
            }
            attempt += 1

            do {
                try await Task.sleep(nanoseconds: UInt64(max(statePollInterval, 0) * 1_000_000_000))
            } catch let cancellation as CancellationError {
                // The caller cancelled the upload task; keep that distinguishable.
                throw cancellation
            } catch {
                throw SpeechError.uploadFailed(provider: .gemini, reason: "Waiting for \(name) was cancelled.")
            }

            let request = try makeStateRequest(
                fileName: name,
                timeoutInterval: timeoutInterval,
                credential: credential
            )
            let (data, response) = try await urlSession.data(for: request)
            try validateStatusCode(try httpResponse(from: response), data: data)
            latest = try decodeFileResource(from: data)
        }
    }

    private func uploadedFile(from resource: GeminiFileResource) throws -> UploadedFile {
        guard let uri = resource.uri, !uri.isEmpty else {
            throw SpeechError.uploadFailed(
                provider: .gemini,
                reason: "The Gemini Files API did not return a file URI."
            )
        }
        return UploadedFile(
            name: resource.name ?? "",
            uri: uri,
            mimeType: resource.mimeType ?? "application/octet-stream"
        )
    }

    private func httpResponse(from response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .gemini)
        }
        return httpResponse
    }

    private func validateStatusCode(_ response: HTTPURLResponse, data: Data) throws {
        guard (200...299).contains(response.statusCode) else {
            throw SpeechError.uploadFailed(provider: .gemini, reason: errorMessage(from: data, statusCode: response.statusCode))
        }
    }

    private func errorMessage(from data: Data, statusCode: Int) -> String {
        if let failure = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data),
           let message = failure.error?.message {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
    }

    private func readFileData(from fileURL: URL) throws -> Data {
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw SpeechError.providerFailure(provider: .gemini, reason: error.localizedDescription)
        }
    }
}

struct GeminiFileUploadMetadata: Encodable, Sendable {
    struct File: Encodable, Sendable {
        let displayName: String

        private enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    let file: File

    init(displayName: String) {
        self.file = File(displayName: displayName)
    }
}

struct GeminiFileEnvelope: Decodable, Sendable {
    let file: GeminiFileResource?
}

struct GeminiFileResource: Decodable, Sendable, Equatable {
    struct Failure: Decodable, Sendable, Equatable {
        let message: String?
    }

    let name: String?
    let uri: String?
    let mimeType: String?
    let state: String?
    let error: Failure?
}

/// Applies a resolved credential to a Gemini REST request.
///
/// Google accepts a long-lived API key in `x-goog-api-key`. A short-lived
/// token is sent as an OAuth-style bearer token, because Google's ephemeral
/// Live tokens do not authorize REST transcription.
enum GeminiRESTAuthorization {
    static func apply(_ credential: SpeechResolvedCredential, to request: inout URLRequest) {
        switch credential {
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .token(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
