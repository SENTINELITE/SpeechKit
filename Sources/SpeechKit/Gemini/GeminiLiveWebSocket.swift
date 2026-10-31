import Foundation

actor GeminiLiveWebSocket {
    private var connectionGeneration = UUID()
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
    /// API keys use `x-goog-api-key`. Google vendor tokens use the Constrained
    /// method and `Authorization: Token`. Relay tickets use Bearer authorization.
    nonisolated static func makeConnectRequest(
        credential: SpeechResolvedCredential,
        options: GeminiRealtimeOptions,
        endpoint: URL? = nil
    ) throws -> URLRequest {
        try options.validate()
        try SpeechEndpointPolicy.validate(endpoint ?? defaultURL, websocket: true)
        try SpeechResolvedCredential.validateSecret(credential.secret)
        guard !credential.isEmpty else {
            throw GeminiRealtimeError.apiKeyMissing
        }
        guard let baseURL = endpoint ?? defaultURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GeminiRealtimeError.invalidURL
        }

        if credential.kind == .vendorToken && components.host?.lowercased() == "generativelanguage.googleapis.com" {
            components.path = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained"
        }

        guard let url = components.url else {
            throw GeminiRealtimeError.invalidURL
        }

        var request = URLRequest(url: url)
        try credential.authorize(&request, provider: .gemini, capability: .realtime)
        return request
    }

    func connect(
        credential: SpeechResolvedCredential,
        options: GeminiRealtimeOptions,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<GeminiLiveMessage, Error> {
        let request = try Self.makeConnectRequest(credential: credential, options: options, endpoint: endpoint)

        sampleRate = options.sampleRate

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
            try await sendEncodable(options.setupMessage())
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
            throw GeminiRealtimeError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw GeminiRealtimeError.encodingFailed
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
            let decoded = try decoder.decode(GeminiLiveMessage.self, from: data)
            continuation?.yield(decoded)
        } catch {
            continuation?.yield(.unknown)
        }
    }
}
