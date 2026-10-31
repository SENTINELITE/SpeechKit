import Foundation

actor MistralRealtimeWebSocket {
    private var connectionGeneration = UUID()
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<MistralRealtimeMessage, Error>.Continuation?
    private var options = MistralRealtimeOptions()

    static let defaultURL = URL(string: "wss://api.mistral.ai/v1/audio/transcriptions/realtime")
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
    /// Mistral takes the model as a query parameter. API keys use Bearer;
    /// supported native tokens use the `realtime, <token>` subprotocol.
    nonisolated static func makeConnectRequest(
        credential: SpeechResolvedCredential,
        options: MistralRealtimeOptions,
        endpoint: URL? = nil
    ) throws -> URLRequest {
        try options.validate()
        if credential.kind == .vendorToken && options.modelID != .voxtralMiniTranscribeRealtime2602 { throw SpeechFailure(.unsupportedAuthentication) }
        try SpeechEndpointPolicy.validate(endpoint ?? defaultURL, websocket: true)
        try SpeechResolvedCredential.validateSecret(credential.secret)
        guard !credential.isEmpty else {
            throw MistralRealtimeError.apiKeyMissing
        }
        guard let baseURL = endpoint ?? defaultURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw MistralRealtimeError.invalidURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "model", value: options.modelID.rawValue))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw MistralRealtimeError.invalidURL
        }

        var request = URLRequest(url: url)
        try credential.authorize(&request, provider: .mistral, capability: .realtime)
        return request
    }

    /// Opens a realtime session.
    ///
    /// The session is configured in two steps: Mistral announces the session
    /// with `session.created`, SpeechKit answers with `session.update`, and
    /// Mistral confirms with `session.updated`. Audio must not flow before that
    /// confirmation, because Mistral locks the settings on the first chunk.
    func connect(
        credential: SpeechResolvedCredential,
        options: MistralRealtimeOptions,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<MistralRealtimeMessage, Error> {
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
        self.options = options
        didAcknowledgeHandshake = false


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
        try await sendEncodable(MistralInputAudioAppendMessage(audioData: audioData))
    }

    func sendAudioEnd() async throws {
        try await sendEncodable(MistralInputAudioEndMessage())
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
            throw MistralRealtimeError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw MistralRealtimeError.encodingFailed
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
                    await handleReceivedData(data, from: task)

                case .data(let data):
                    await handleReceivedData(data, from: task)

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

        continuation?.finish()
    }

    private func handleReceivedData(_ data: Data, from task: URLSessionWebSocketTask) async {
        guard webSocketTask === task else { return }
        let decoded: MistralRealtimeMessage
        do {
            decoded = try decoder.decode(MistralRealtimeMessage.self, from: data)
        } catch {
            continuation?.yield(.unknown("decode_error"))
            return
        }

        switch decoded {
        case .sessionCreated:
            continuation?.yield(decoded)
            do {
                try await sendEncodable(options.sessionUpdateMessage())
            } catch {
                guard webSocketTask === task else { return }
                continuation?.finish(throwing: SpeechErrorBoundary.safe(error))
            }
        case .sessionUpdated:
            acknowledgeHandshake()
            continuation?.yield(decoded)
        default:
            continuation?.yield(decoded)
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
        continuation?.finish(throwing: MistralRealtimeError.handshakeTimedOut)
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
    }
}
