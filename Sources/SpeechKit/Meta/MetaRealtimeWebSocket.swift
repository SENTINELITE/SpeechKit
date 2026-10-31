import Foundation

actor MetaRealtimeWebSocket {
    private var connectionGeneration = UUID()
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
        try SpeechEndpointPolicy.validate(endpoint ?? defaultURL, websocket: true)
        try SpeechResolvedCredential.validateSecret(credential.secret)
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
        var request = URLRequest(url: url)
        try credential.authorize(&request, provider: .meta, capability: .realtime)
        return request
    }

    func connect(
        credential: SpeechResolvedCredential,
        options: MetaRealtimeOptions,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<MetaRealtimeMessage, Error> {
        let request = try Self.makeConnectRequest(credential: credential, options: options, endpoint: endpoint)

        disconnect()
        let generation = connectionGeneration
        let opened = try await SpeechSocketConnection.open(request: request, credential: credential)
        guard generation == connectionGeneration, !Task.isCancelled else {
            opened.task.cancel(with: .goingAway, reason: nil)
            opened.session.invalidateAndCancel()
            throw CancellationError()
        }
        let session = opened.session
        let task = opened.task
        self.session = session
        self.webSocketTask = task
        didAcknowledgeHandshake = false

        do {
            try await sendEncodable(options.handshakeMessage(secret: opened.credential.secret))
        } catch {
            disconnect(ifCurrent: task)
            throw SpeechErrorBoundary.safe(error)
        }

        guard webSocketTask === task, !Task.isCancelled else {
            disconnect(ifCurrent: task)
            throw CancellationError()
        }

        return AsyncThrowingStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { await self.disconnect(ifCurrent: task) }
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
                await self.receiveMessages(from: task)
            }
        }
    }

    func sendAudio(_ audioData: Data) async throws {
        try Task.checkCancellation()
        guard let task = webSocketTask, task.state == .running else {
            throw MetaRealtimeError.disconnected
        }

        try await task.send(.data(audioData))
    }

    func sendEndStream() async throws {
        try await sendEncodable(MetaEndStreamMessage())
    }

    func disconnect() {
        connectionGeneration = UUID()
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
        try Task.checkCancellation()
        guard let task = webSocketTask, task.state == .running else {
            throw MetaRealtimeError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw MetaRealtimeError.encodingFailed
        }

        try await task.send(.string(jsonString))
    }

    private func disconnect(ifCurrent task: URLSessionWebSocketTask) {
        guard webSocketTask === task else { return }
        disconnect()
    }

    private func receiveMessages(from task: URLSessionWebSocketTask) async {
        guard webSocketTask === task else { return }

        while task.state == .running && webSocketTask === task {
            do {
                let message = try await task.receive()

                guard webSocketTask === task else { return }
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
                guard webSocketTask === task else { return }
                continuation?.finish(throwing: SpeechErrorBoundary.safe(error))
                return
            }
        }

        if webSocketTask === task { continuation?.finish() }
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
