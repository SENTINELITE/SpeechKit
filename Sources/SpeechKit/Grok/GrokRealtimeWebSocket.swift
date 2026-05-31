import Foundation

actor GrokRealtimeWebSocket {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<GrokRealtimeMessage, Error>.Continuation?

    private let baseURL = "wss://api.x.ai/v1/stt"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isConnected: Bool {
        webSocketTask?.state == .running
    }

    func connect(
        apiKey: String,
        options: GrokRealtimeOptions
    ) async throws -> AsyncThrowingStream<GrokRealtimeMessage, Error> {
        guard var components = URLComponents(string: baseURL) else {
            throw GrokRealtimeError.invalidURL
        }
        components.queryItems = try options.queryItems()
        guard let url = components.url else {
            throw GrokRealtimeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        self.session = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task

        task.resume()

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
        guard let task = webSocketTask, task.state == .running else {
            throw GrokRealtimeError.disconnected
        }

        try await task.send(.data(audioData))
    }

    func sendAudioDone() async throws {
        try await sendEncodable(GrokAudioDoneMessage())
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
            throw GrokRealtimeError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw GrokRealtimeError.encodingFailed
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
            let decoded = try decoder.decode(GrokRealtimeMessage.self, from: data)
            continuation?.yield(decoded)
        } catch {
            continuation?.yield(.unknown("decode_error"))
        }
    }
}
