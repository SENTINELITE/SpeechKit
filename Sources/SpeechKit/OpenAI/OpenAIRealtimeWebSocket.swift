import Foundation

actor OpenAIRealtimeWebSocket {
    private var connectionGeneration = UUID()
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<OpenAIRealtimeMessage, Error>.Continuation?
    private var inputAudioCommitGate = OpenAIInputAudioCommitGate()

    static let defaultURL = URL(string: "wss://api.openai.com/v1/realtime")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isConnected: Bool {
        webSocketTask?.state == .running
    }

    /// Builds the WebSocket handshake request for a Realtime session.
    ///
    /// OpenAI accepts both a long-lived API key and an ephemeral client secret
    /// as a bearer token.
    nonisolated static func makeConnectRequest(
        credential: SpeechResolvedCredential,
        options: OpenAIRealtimeSessionOptions,
        endpoint: URL? = nil
    ) throws -> URLRequest {
        try options.validate()
        try SpeechEndpointPolicy.validate(endpoint ?? defaultURL, websocket: true)
        try SpeechResolvedCredential.validateSecret(credential.secret)
        guard let baseURL = endpoint ?? defaultURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw OpenAIError.invalidURL
        }

        var queryItems = (components.queryItems ?? []).filter { !["model", "intent"].contains($0.name) }
        queryItems.append(URLQueryItem(name: "intent", value: "transcription"))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        try credential.authorize(&request, provider: .openAI, capability: .realtime)
        return request
    }

    func connect(
        credential: SpeechResolvedCredential,
        options: OpenAIRealtimeSessionOptions,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<OpenAIRealtimeMessage, Error> {
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

        do {
            try await send(OpenAIRealtimeSessionUpdateMessage(options: options))
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

            Task {
                await self.receiveMessages(from: task)
            }
        }
    }

    func send(_ message: OpenAIRealtimeSessionUpdateMessage) async throws {
        try await sendEncodable(message)
    }

    func send(_ message: OpenAIInputAudioBufferAppendMessage) async throws {
        try await sendEncodable(message)
        inputAudioCommitGate.append(message.byteCount)
    }

    func commitInputAudioBuffer() async throws {
        guard inputAudioCommitGate.isReady else { return }
        try await sendEncodable(OpenAIInputAudioBufferCommitMessage())
        inputAudioCommitGate.markCommitted()
    }

    func disconnect() {
        connectionGeneration = UUID()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        continuation?.finish()
        continuation = nil
        inputAudioCommitGate.reset()
        session?.invalidateAndCancel()
        session = nil
    }

    private func sendEncodable<T: Encodable & Sendable>(_ message: T) async throws {
        try Task.checkCancellation()
        guard let task = webSocketTask, task.state == .running else {
            throw OpenAIError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw OpenAIError.encodingFailed
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
            let decoded = try decoder.decode(OpenAIRealtimeMessage.self, from: data)
            continuation?.yield(decoded)
        } catch {
            continuation?.yield(.unknown("decode_error"))
        }
    }
}
