import Foundation

actor GrokRealtimeWebSocket {
    private var connectionGeneration = UUID()
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<GrokRealtimeMessage, Error>.Continuation?

    static let defaultURL = URL(string: "wss://api.x.ai/v1/stt")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isConnected: Bool {
        webSocketTask?.state == .running
    }

    /// Builds the WebSocket handshake request for a realtime session.
    ///
    /// Grok API keys and custom proxy credentials use Bearer authorization.
    /// Native vendor-token mode is unsupported for this capability.
    nonisolated static func makeConnectRequest(
        credential: SpeechResolvedCredential,
        options: GrokRealtimeOptions,
        endpoint: URL? = nil
    ) throws -> URLRequest {
        guard let baseURL = endpoint ?? defaultURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GrokRealtimeError.invalidURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: try options.queryItems())
        components.queryItems = queryItems

        guard let url = components.url else {
            throw GrokRealtimeError.invalidURL
        }

        var request = URLRequest(url: url)
        try credential.authorize(&request, provider: .grok, capability: .realtime)
        return request
    }

    func connect(
        credential: SpeechResolvedCredential,
        options: GrokRealtimeOptions,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<GrokRealtimeMessage, Error> {
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

    func sendAudio(_ audioData: Data) async throws {
        try Task.checkCancellation()
        guard let task = webSocketTask, task.state == .running else {
            throw GrokRealtimeError.disconnected
        }

        try await task.send(.data(audioData))
    }

    func sendAudioDone() async throws {
        try await sendEncodable(GrokAudioDoneMessage())
    }

    func disconnect() {
        connectionGeneration = UUID()
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
            throw GrokRealtimeError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw GrokRealtimeError.encodingFailed
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
            let decoded = try decoder.decode(GrokRealtimeMessage.self, from: data)
            continuation?.yield(decoded)
        } catch {
            continuation?.yield(.unknown("decode_error"))
        }
    }
}
