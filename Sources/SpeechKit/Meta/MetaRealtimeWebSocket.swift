import Foundation

actor MetaRealtimeWebSocket {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<MetaRealtimeMessage, Error>.Continuation?

    static let defaultURL = URL(string: "wss://api.meta.ai/v1/asr/realtime")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let handshakeTimeoutNanoseconds: UInt64 = 10_000_000_000
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var didAcknowledgeHandshake = false

    var isConnected: Bool {
        webSocketTask?.state == .running
    }

    /// Builds the WebSocket handshake request for a realtime session.
    ///
    /// Meta carries the credential in the handshake frame, so the request only
    /// determines the socket URL.
    nonisolated static func makeConnectRequest(
        credential: SpeechResolvedCredential,
        options: MetaRealtimeOptions,
        endpoint: URL? = nil
    ) throws -> URLRequest {
        try options.validate()
        guard !credential.isEmpty else {
            throw MetaRealtimeError.apiKeyMissing
        }
        guard let baseURL = endpoint ?? defaultURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw MetaRealtimeError.invalidURL
        }

        if let sessionID = options.sessionID, !sessionID.isEmpty {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "sessionId", value: sessionID))
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw MetaRealtimeError.invalidURL
        }
        return URLRequest(url: url)
    }

    func connect(
        credential: SpeechResolvedCredential,
        options: MetaRealtimeOptions,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<MetaRealtimeMessage, Error> {
        let request = try Self.makeConnectRequest(credential: credential, options: options, endpoint: endpoint)

        let session = URLSession(configuration: .default)
        self.session = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        didAcknowledgeHandshake = false

        task.resume()
        try await sendEncodable(options.handshakeMessage(secret: credential.secret))

        return AsyncThrowingStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { await self.disconnect() }
            }

            self.handshakeTimeoutTask = Task { [weak self, handshakeTimeoutNanoseconds] in
                do {
                    try await Task.sleep(nanoseconds: handshakeTimeoutNanoseconds)
                } catch {
                    return
                }

                await self?.failHandshakeIfUnacknowledged()
            }

            Task {
                await self.receiveMessages()
            }
        }
    }

    func sendAudio(_ audioData: Data) async throws {
        guard let task = webSocketTask, task.state == .running else {
            throw MetaRealtimeError.disconnected
        }

        try await task.send(.data(audioData))
    }

    func sendEndStream() async throws {
        try await sendEncodable(MetaEndStreamMessage())
    }

    func disconnect() {
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        didAcknowledgeHandshake = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        continuation?.finish()
        continuation = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func sendEncodable<T: Encodable & Sendable>(_ message: T) async throws {
        guard let task = webSocketTask, task.state == .running else {
            throw MetaRealtimeError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw MetaRealtimeError.encodingFailed
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
            let decoded = try decoder.decode(MetaRealtimeMessage.self, from: data)
            if case .sessionCreated = decoded {
                acknowledgeHandshake()
            }
            continuation?.yield(decoded)
        } catch {
            continuation?.yield(.unknown("decode_error"))
        }
    }

    private func acknowledgeHandshake() {
        didAcknowledgeHandshake = true
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
    }

    private func failHandshakeIfUnacknowledged() {
        guard !didAcknowledgeHandshake else { return }

        handshakeTimeoutTask = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.finish(throwing: MetaRealtimeError.handshakeTimedOut)
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
    }
}
