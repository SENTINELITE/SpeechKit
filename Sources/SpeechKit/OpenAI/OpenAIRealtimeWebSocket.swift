import Foundation

actor OpenAIRealtimeWebSocket {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<OpenAIRealtimeMessage, Error>.Continuation?

    private let baseURL = "wss://api.openai.com/v1/realtime"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isConnected: Bool {
        webSocketTask?.state == .running
    }

    func connect(
        apiKey: String,
        options: OpenAIRealtimeSessionOptions
    ) async throws -> AsyncThrowingStream<OpenAIRealtimeMessage, Error> {
        guard let url = URL(string: "\(baseURL)?model=\(options.sessionModelID.rawValue)") else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        self.session = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task

        task.resume()
        try await send(OpenAIRealtimeSessionUpdateMessage(options: options))

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

    func send(_ message: OpenAIRealtimeSessionUpdateMessage) async throws {
        try await sendEncodable(message)
    }

    func send(_ message: OpenAIInputAudioBufferAppendMessage) async throws {
        try await sendEncodable(message)
    }

    func commitInputAudioBuffer() async throws {
        try await sendEncodable(OpenAIInputAudioBufferCommitMessage())
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
            throw OpenAIError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw OpenAIError.encodingFailed
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
            let decoded = try decoder.decode(OpenAIRealtimeMessage.self, from: data)
            continuation?.yield(decoded)
        } catch {
            continuation?.yield(.unknown("decode_error"))
        }
    }
}
