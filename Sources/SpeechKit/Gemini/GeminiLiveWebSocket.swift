import Foundation

actor GeminiLiveWebSocket {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<GeminiLiveMessage, Error>.Continuation?
    private var sampleRate = 16000

    static let defaultURL = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isConnected: Bool {
        webSocketTask?.state == .running
    }

    /// Builds the WebSocket handshake request for a Gemini Live session.
    ///
    /// An API key goes in the `key` query parameter. A short-lived Google
    /// ephemeral token goes in an `Authorization: Token` header instead, which
    /// keeps the secret out of the URL.
    nonisolated static func makeConnectRequest(
        credential: SpeechResolvedCredential,
        options: GeminiRealtimeOptions,
        endpoint: URL? = nil
    ) throws -> URLRequest {
        try options.validate()
        guard !credential.isEmpty else {
            throw GeminiRealtimeError.apiKeyMissing
        }
        guard let baseURL = endpoint ?? defaultURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GeminiRealtimeError.invalidURL
        }

        if case .apiKey(let key) = credential {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "key", value: key))
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw GeminiRealtimeError.invalidURL
        }

        var request = URLRequest(url: url)
        if case .token(let token) = credential {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func connect(
        credential: SpeechResolvedCredential,
        options: GeminiRealtimeOptions,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<GeminiLiveMessage, Error> {
        let request = try Self.makeConnectRequest(credential: credential, options: options, endpoint: endpoint)

        sampleRate = options.sampleRate

        let session = URLSession(configuration: .default)
        self.session = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task

        task.resume()
        try await sendEncodable(options.setupMessage())

        return AsyncThrowingStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { await self.disconnect() }
            }

            Task {
                await self.receiveMessages()
            }
        }
    }

    func sendAudio(_ audioData: Data) async throws {
        try await sendEncodable(GeminiRealtimeAudioMessage(audioData: audioData, sampleRate: sampleRate))
    }

    func sendActivityStart() async throws {
        try await sendEncodable(GeminiActivityMessage(kind: .activityStart))
    }

    func sendActivityEnd() async throws {
        try await sendEncodable(GeminiActivityMessage(kind: .activityEnd))
    }

    func sendAudioStreamEnd() async throws {
        try await sendEncodable(GeminiAudioStreamEndMessage())
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        continuation?.finish()
        continuation = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func sendEncodable<T: Encodable & Sendable>(_ message: T) async throws {
        guard let task = webSocketTask, task.state == .running else {
            throw GeminiRealtimeError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw GeminiRealtimeError.encodingFailed
        }

        try await task.send(.string(jsonString))
    }

    private func receiveMessages() async {
        guard let task = webSocketTask else { return }

        while task.state == .running {
            do {
                let message = try await task.receive()

                switch message {
                case .string(let text):
                    guard let data = text.data(using: .utf8) else { continue }
                    yieldDecodedMessage(data)

                case .data(let data):
                    yieldDecodedMessage(data)

                @unknown default:
                    break
                }
            } catch {
                if task.state != .running {
                    break
                }
                continuation?.finish(throwing: error)
                return
            }
        }

        continuation?.finish()
    }

    private func yieldDecodedMessage(_ data: Data) {
        do {
            let decoded = try decoder.decode(GeminiLiveMessage.self, from: data)
            continuation?.yield(decoded)
        } catch {
            continuation?.yield(.unknown)
        }
    }
}
