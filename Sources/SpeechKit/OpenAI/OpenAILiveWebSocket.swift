import Foundation

/// Keeps GPT-Live input audio chunks 16-bit aligned.
///
/// GPT-Live rejects a chunk whose byte count is odd, so a trailing byte is
/// carried over and prefixed to the next chunk instead of being dropped.
struct OpenAILiveAudioChunkAligner: Sendable, Equatable {
    /// The byte held back from the previous chunk, if any.
    private(set) var carryOverByte: UInt8?

    /// Returns an even-length chunk, prefixing any carried byte and holding back a new trailing byte.
    ///
    /// - Parameter data: The next captured audio chunk.
    /// - Returns: An even-length chunk, which is empty when there is nothing to send yet.
    mutating func aligned(_ data: Data) -> Data {
        var chunk = Data()
        if let carryOverByte {
            chunk.append(carryOverByte)
        }
        chunk.append(data)
        carryOverByte = nil

        if !chunk.isEmpty, !chunk.count.isMultiple(of: 2) {
            carryOverByte = chunk.removeLast()
        }
        return chunk
    }

    /// Drops any carried byte.
    mutating func reset() {
        carryOverByte = nil
    }
}

actor OpenAILiveWebSocket {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<OpenAILiveMessage, Error>.Continuation?
    private var audioChunkAligner = OpenAILiveAudioChunkAligner()

    /// A Boolean value that indicates whether the provider acknowledged `session.close`.
    ///
    /// GPT-Live drops the socket a moment after `session.closed`, so a transport
    /// failure after this flag is set is a normal close rather than an error.
    private(set) var didReceiveSessionClosed = false

    static let defaultURL = URL(string: "wss://api.openai.com/v1/live/sessions")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isConnected: Bool {
        webSocketTask?.state == .running
    }

    /// Builds the WebSocket handshake request for a GPT-Live session.
    ///
    /// GPT-Live takes no query items: the model travels in `session.start`.
    /// OpenAI documents no ephemeral client secret for Live, so the bearer is
    /// either a long-lived API key or whatever token a `liveEndpoint` proxy expects.
    nonisolated static func makeConnectRequest(
        credential: SpeechResolvedCredential,
        options: OpenAILiveSessionOptions,
        endpoint: URL? = nil
    ) throws -> URLRequest {
        try options.validate()
        guard let url = endpoint ?? defaultURL else {
            throw OpenAILiveError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential.secret)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Opens a GPT-Live session and returns the decoded server event stream.
    ///
    /// The `session.start` event goes out immediately, but this method does not
    /// wait for `session.started`; the service owns that handshake so it can keep
    /// its lifecycle state in one place.
    func connect(
        credential: SpeechResolvedCredential,
        options: OpenAILiveSessionOptions,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<OpenAILiveMessage, Error> {
        let request = try Self.makeConnectRequest(credential: credential, options: options, endpoint: endpoint)

        didReceiveSessionClosed = false
        audioChunkAligner.reset()

        let session = URLSession(configuration: .default)
        self.session = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task

        task.resume()
        try await sendEncodable(OpenAILiveSessionStartMessage(options: options))

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

    /// Streams a chunk of microphone audio, keeping the wire chunks 16-bit aligned.
    func sendInputAudio(_ data: Data) async throws {
        let chunk = audioChunkAligner.aligned(data)
        guard !chunk.isEmpty else { return }
        try await sendEncodable(OpenAILiveInputAudioAppendMessage(audioData: chunk))
    }

    /// Stops the provider from hearing microphone audio.
    func sendInputAudioMute() async throws {
        try await sendEncodable(OpenAILiveInputAudioMuteMessage())
    }

    /// Lets the provider hear microphone audio again.
    func sendInputAudioUnmute() async throws {
        try await sendEncodable(OpenAILiveInputAudioUnmuteMessage())
    }

    /// Updates the mutable Responses delegation settings of a running session.
    func send(_ message: OpenAILiveSessionUpdateMessage) async throws {
        try await sendEncodable(message)
    }

    /// Pushes instructions, thinking, or commentary into a running session.
    func send(_ message: OpenAILiveContextAppendMessage) async throws {
        try await sendEncodable(message)
    }

    /// Forwards a raw Responses item to a delegated backend.
    func send(_ message: OpenAILiveResponseItemCreateMessage) async throws {
        try await sendEncodable(message)
    }

    /// Forwards a raw Responses request to a delegated backend.
    func send(_ message: OpenAILiveResponseCreateMessage) async throws {
        try await sendEncodable(message)
    }

    /// Asks the provider to end the session, and keeps the stream open for `session.closed`.
    func requestClose() async throws {
        try await sendEncodable(OpenAILiveSessionCloseMessage())
    }

    /// Cancels the socket and finishes the message stream.
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        continuation?.finish()
        continuation = nil
        audioChunkAligner.reset()
        session?.invalidateAndCancel()
        session = nil
    }

    private func sendEncodable<T: Encodable & Sendable>(_ message: T) async throws {
        guard let task = webSocketTask, task.state == .running else {
            throw OpenAILiveError.disconnected
        }

        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw OpenAILiveError.encodingFailed
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
                if task.state != .running || didReceiveSessionClosed {
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
            let decoded = try decoder.decode(OpenAILiveMessage.self, from: data)
            if case .sessionClosed = decoded {
                didReceiveSessionClosed = true
            }
            continuation?.yield(decoded)
        } catch {
            continuation?.yield(.unknown("decode_error"))
        }
    }
}
