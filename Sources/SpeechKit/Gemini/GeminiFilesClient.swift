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
    let uploadURL: URL?
    private let statePollInterval: TimeInterval
    private let maxStatePollAttempts: Int

    init(
        apiKey: String,
        endpoint: URL? = nil,
        urlSession: URLSession = SpeechTransport.session(),
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
        urlSession: URLSession = SpeechTransport.session(),
        statePollInterval: TimeInterval = 1,
        maxStatePollAttempts: Int = 60
    ) {
        self.credential = credential
        self.urlSession = SpeechTransport.session(copying: urlSession, pinnedPublicKeyHashes: credential.pinnedPublicKeyHashes)
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
        let resolved = try await credential.resolved(for: .gemini, endpoint: uploadURL)
        return try await upload(file: file, mimeType: mimeType, timeoutInterval: timeoutInterval, credential: resolved)
    }

    func upload(file: URL, mimeType: String, timeoutInterval: TimeInterval,
                credential resolved: SpeechResolvedCredential) async throws -> UploadedFile {
        try SpeechEndpointPolicy.validate(uploadURL)
        try SpeechResolvedCredential.validateSecret(resolved.secret)
        let audioData = try readFileData(from: file)
        let startRequest = try makeStartRequest(
            file: file,
            mimeType: mimeType,
            byteCount: audioData.count,
            timeoutInterval: timeoutInterval,
            credential: resolved
        )
        let (startData, startResponse) = try await SpeechTransport.data(for: startRequest, session: urlSession, prepare: self.credential.relayRequestPreparation)
        let startHTTPResponse = try httpResponse(from: startResponse)
        try validateStatusCode(startHTTPResponse, data: startData)

        guard let sessionURLString = startHTTPResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let sessionURL = URL(string: sessionURLString) else {
            throw SpeechError.uploadFailed(
                provider: .gemini,
                reason: .uploadFailed)
        }

        try validateUploadSession(sessionURL, credential: resolved)
        var uploadRequest = makeUploadRequest(
            sessionURL: sessionURL,
            byteCount: audioData.count,
            timeoutInterval: timeoutInterval
        )
        if resolved.kind == .relay {
            try resolved.authorize(&uploadRequest, provider: .gemini, capability: .fileTranscription)
        }
        uploadRequest.httpBody = audioData

        let (uploadData, uploadResponse) = try await SpeechTransport.data(for: uploadRequest, session: urlSession, prepare: self.credential.relayRequestPreparation)
        let uploadHTTPResponse = try httpResponse(from: uploadResponse)
        try validateStatusCode(uploadHTTPResponse, data: uploadData)

        let resource = try decodeFileResource(from: uploadData)
        return try await activeFile(from: resource, timeoutInterval: timeoutInterval, credential: resolved)
    }

    func validateUploadSession(_ url: URL, credential: SpeechResolvedCredential) throws {
        try SpeechEndpointPolicy.validate(url)
        guard let uploadURL, SpeechEndpointPolicy.sameOrigin(url, uploadURL) else {
            throw SpeechFailure(.invalidEndpoint)
        }
        if credential.kind == .relay {
            let prefix = uploadURL.path.replacingOccurrences(of: "/upload/v1beta/files", with: "/upload-sessions/")
            guard url.path.hasPrefix(prefix), url.query == nil else { throw SpeechFailure(.invalidEndpoint) }
            do { _ = try GeminiRoute.identifier(String(url.path.dropFirst(prefix.count)), prefix: "") }
            catch { throw SpeechFailure(.invalidEndpoint) }
        }
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
        try SpeechEndpointPolicy.validate(uploadURL)
        guard credential.kind != .vendorToken else { throw SpeechFailure(.unsupportedAuthentication) }
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
            throw SpeechError.providerFailure(provider: .gemini, reason: .requestFailed)
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
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
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
        try SpeechEndpointPolicy.validate(uploadURL)
        guard credential.kind != .vendorToken else { throw SpeechFailure(.unsupportedAuthentication) }
        guard !credential.isEmpty else {
            throw SpeechError.providerNotConfigured(.gemini)
        }

        let trimmed = "files/" + (try GeminiRoute.identifier(fileName, prefix: "files"))
        guard !trimmed.isEmpty, let url = try stateURL(forFileName: trimmed) else {
            throw SpeechError.uploadFailed(
                provider: .gemini,
                reason: .uploadFailed)
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
            throw SpeechError.decodingFailed(provider: .gemini, reason: .decodingFailed)
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
                    reason: .uploadFailed)
            default:
                break
            }

            guard let name = latest.name, !name.isEmpty else {
                throw SpeechError.uploadFailed(
                    provider: .gemini,
                    reason: .uploadFailed)
            }
            guard attempt < maxStatePollAttempts else {
                throw SpeechError.uploadFailed(
                    provider: .gemini,
                    reason: .uploadFailed)
            }
            attempt += 1

            do {
                try await Task.sleep(nanoseconds: UInt64(max(statePollInterval, 0) * 1_000_000_000))
            } catch let cancellation as CancellationError {
                // The caller cancelled the upload task; keep that distinguishable.
                throw cancellation
            } catch {
                throw SpeechError.uploadFailed(provider: .gemini, reason: .uploadFailed)
            }

            let request = try makeStateRequest(
                fileName: name,
                timeoutInterval: timeoutInterval,
                credential: credential
            )
            let (data, response) = try await SpeechTransport.data(for: request, session: urlSession, prepare: self.credential.relayRequestPreparation)
            try validateStatusCode(try httpResponse(from: response), data: data)
            latest = try decodeFileResource(from: data)
        }
    }

    private func uploadedFile(from resource: GeminiFileResource) throws -> UploadedFile {
        guard let uri = resource.uri, !uri.isEmpty else {
            throw SpeechError.uploadFailed(
                provider: .gemini,
                reason: .uploadFailed)
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
            throw SpeechFailure(.server, statusCode: response.statusCode)
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
            throw SpeechError.providerFailure(provider: .gemini, reason: .requestFailed)
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
/// API keys use `x-goog-api-key`. Explicit OAuth and relay credentials use
/// Bearer authorization. Native Live tokens do not authorize REST transcription.
enum GeminiRESTAuthorization {
    static func apply(_ credential: SpeechResolvedCredential, to request: inout URLRequest) {
        // Callers validate mode and destination before this nonthrowing serializer.
        if credential.kind == .apiKey {
            request.setValue(credential.secret, forHTTPHeaderField: "x-goog-api-key")
        } else {
            request.setValue("Bearer \(credential.secret)", forHTTPHeaderField: "Authorization")
        }
    }
}
