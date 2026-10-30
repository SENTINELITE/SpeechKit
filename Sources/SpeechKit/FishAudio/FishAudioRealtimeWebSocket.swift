import Foundation

/// What a Fish Audio realtime socket received.
enum FishAudioRealtimeSocketEvent: Sendable, Equatable {
    /// A binary frame.
    case frame(Data)
    /// A text frame. Fish Audio never sends one, so SpeechKit ignores it.
    case text(String)
    /// The server closed the connection with this WebSocket close code.
    case closed(code: Int, reason: String?)
}

/// The raw WebSocket under ``FishAudioRealtimeWebSocket``.
///
/// Tests replace it with an in-memory fake, so the protocol framing, the
/// handshake, and the close-code mapping run without a network.
protocol FishAudioRealtimeSocket: AnyObject, Sendable {
    /// Sends one binary frame.
    func send(_ data: Data) async throws
    /// Waits for the next event. Throws when the connection fails rather than closes.
    func receive() async throws -> FishAudioRealtimeSocketEvent
    /// Closes the connection normally.
    func close()
}

/// Opens a socket for a handshake request.
typealias FishAudioRealtimeSocketFactory = @Sendable (URLRequest) -> any FishAudioRealtimeSocket

/// A ``FishAudioRealtimeSocket`` backed by `URLSessionWebSocketTask`.
final class FishAudioURLSessionRealtimeSocket: FishAudioRealtimeSocket, @unchecked Sendable {
    // Both are set once in `init` and only read afterwards; `URLSession` and
    // `URLSessionWebSocketTask` are thread-safe.
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(request: URLRequest) {
        session = URLSession(configuration: .default)
        task = session.webSocketTask(with: request)
        task.resume()
    }

    static let factory: FishAudioRealtimeSocketFactory = { request in
        FishAudioURLSessionRealtimeSocket(request: request)
    }

    func send(_ data: Data) async throws {
        do {
            try await task.send(.data(data))
        } catch {
            throw mappedError(error)
        }
    }

    func receive() async throws -> FishAudioRealtimeSocketEvent {
        do {
            switch try await task.receive() {
            case .data(let data):
                return .frame(data)
            case .string(let text):
                return .text(text)
            @unknown default:
                return .text("")
            }
        } catch {
            // A close frame from the server surfaces as a receive error with the close code set.
            if task.closeCode != .invalid {
                let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
                return .closed(code: task.closeCode.rawValue, reason: reason?.isEmpty == true ? nil : reason)
            }
            throw mappedError(error)
        }
    }

    /// Reports a refused upgrade by its HTTP status, and strips URLs from anything else.
    private func mappedError(_ error: Error) -> Error {
        // A refused upgrade leaves the plain HTTP response on the task.
        if let response = task.response as? HTTPURLResponse, response.statusCode != 101 {
            return FishAudioRealtimeError.connectionRefused(statusCode: response.statusCode)
        }
        return SpeechRealtimeErrorRedaction.redacted(error)
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

/// The Fish Audio realtime protocol over one WebSocket.
///
/// Every message, in both directions, is one MessagePack map in a binary
/// frame. SpeechKit sends `config` as the first frame, then waits for
/// `session_started`. While the session is open it sends `keepalive` whenever
/// nothing else has been sent for ``keepaliveInterval``, because Fish Audio
/// closes a session after 30 seconds without a client message.
actor FishAudioRealtimeWebSocket {
    static let defaultURL = URL(string: "wss://api.fish.audio/v1/asr/realtime")
    /// The realtime model, sent as the `model` header.
    static let modelID = "transcribe-stream-1"

    private let socketFactory: FishAudioRealtimeSocketFactory
    private let keepaliveInterval: Duration
    private let handshakeTimeout: Duration
    private var socket: (any FishAudioRealtimeSocket)?
    private var connectionID: UUID?
    private var continuation: AsyncThrowingStream<FishAudioRealtimeServerMessage, Error>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var didStartSession = false
    private var lastSendInstant = ContinuousClock.now
    private var lastServerError: FishAudioRealtimeServerError?

    init(
        socketFactory: @escaping FishAudioRealtimeSocketFactory = FishAudioURLSessionRealtimeSocket.factory,
        keepaliveInterval: Duration = .seconds(15),
        handshakeTimeout: Duration = .seconds(10)
    ) {
        self.socketFactory = socketFactory
        self.keepaliveInterval = keepaliveInterval
        self.handshakeTimeout = handshakeTimeout
    }

    var isConnected: Bool {
        socket != nil
    }

    /// Builds the WebSocket handshake request for a realtime session.
    ///
    /// Fish Audio has no short-lived tokens, so an API key and a fetched token
    /// are both sent as the bearer secret.
    nonisolated static func makeConnectRequest(
        credential: SpeechResolvedCredential,
        options: FishAudioRealtimeOptions,
        endpoint: URL? = nil
    ) throws -> URLRequest {
        try options.validate()
        guard !credential.isEmpty else {
            throw FishAudioRealtimeError.apiKeyMissing
        }
        guard let url = endpoint ?? defaultURL,
              let scheme = url.scheme?.lowercased(),
              ["wss", "ws", "https", "http"].contains(scheme) else {
            throw FishAudioRealtimeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential.secret)", forHTTPHeaderField: "Authorization")
        request.setValue(modelID, forHTTPHeaderField: "model")
        return request
    }

    /// Opens a realtime session and sends `config` as the first frame.
    ///
    /// The returned stream yields every server message, including
    /// `session_started`. It finishes after a normal close (1000) and throws
    /// ``FishAudioRealtimeError`` for an error close code, a refused upgrade, or
    /// a missing `session_started`.
    func connect(
        credential: SpeechResolvedCredential,
        options: FishAudioRealtimeOptions,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<FishAudioRealtimeServerMessage, Error> {
        let request = try Self.makeConnectRequest(credential: credential, options: options, endpoint: endpoint)

        disconnect()
        let socket = socketFactory(request)
        let connectionID = UUID()
        self.socket = socket
        self.connectionID = connectionID
        didStartSession = false
        lastServerError = nil

        let (stream, continuation) = AsyncThrowingStream<FishAudioRealtimeServerMessage, Error>.makeStream()
        self.continuation = continuation
        // Tied to this connection: the termination of a replaced stream runs
        // later and must not close the connection that replaced it.
        continuation.onTermination = { @Sendable _ in
            Task { await self.disconnect(connectionID: connectionID) }
        }

        do {
            try await sendFrame(options.configMessage().encoded())
        } catch {
            disconnect()
            throw SpeechRealtimeErrorRedaction.redacted(error)
        }

        receiveTask = Task { [weak self] in
            await self?.receiveMessages(from: socket)
        }
        handshakeTimeoutTask = Task { [weak self, handshakeTimeout] in
            guard (try? await Task.sleep(for: handshakeTimeout)) != nil else { return }
            await self?.failHandshakeIfNotStarted()
        }
        keepaliveTask = Task { [weak self] in
            await self?.runKeepalive()
        }

        return stream
    }

    /// Sends one client message.
    func send(_ message: FishAudioRealtimeClientMessage) async throws {
        try await sendFrame(message.encoded())
    }

    /// Disconnects only if `connectionID` is still the current connection.
    func disconnect(connectionID: UUID) {
        guard self.connectionID == connectionID else { return }
        disconnect()
    }

    func disconnect() {
        connectionID = nil
        receiveTask?.cancel()
        receiveTask = nil
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        socket?.close()
        socket = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.finish()
    }

    private func sendFrame(_ data: Data) async throws {
        guard let socket else {
            throw FishAudioRealtimeError.disconnected
        }
        lastSendInstant = .now
        try await socket.send(data)
    }

    private func receiveMessages(from socket: any FishAudioRealtimeSocket) async {
        while !Task.isCancelled {
            let event: FishAudioRealtimeSocketEvent
            do {
                event = try await socket.receive()
            } catch {
                finish(throwing: error, from: socket)
                return
            }
            guard self.socket === socket else { return }

            switch event {
            case .frame(let data):
                handleFrame(data)
            case .text:
                // Fish Audio frames everything as binary MessagePack.
                continuation?.yield(.unknown("text_frame"))
            case .closed(let code, let reason):
                finish(throwing: closeError(code: code, reason: reason), from: socket)
                return
            }
        }
    }

    private func handleFrame(_ data: Data) {
        let message: FishAudioRealtimeServerMessage
        do {
            message = try FishAudioRealtimeServerMessage.decode(data)
        } catch {
            continuation?.yield(.unknown("decode_error"))
            return
        }

        switch message {
        case .sessionStarted:
            didStartSession = true
            handshakeTimeoutTask?.cancel()
            handshakeTimeoutTask = nil
        case .error(let serverError):
            lastServerError = serverError
        default:
            break
        }
        continuation?.yield(message)
    }

    /// Maps a close code to an error, or `nil` for a normal close.
    private func closeError(code: Int, reason: String?) -> Error? {
        switch code {
        case 1000:
            return nil
        case 1012:
            return FishAudioRealtimeError.serverRestarting
        default:
            return FishAudioRealtimeError.sessionClosed(
                code: code,
                errorType: lastServerError?.errorType,
                message: lastServerError?.message ?? reason
            )
        }
    }

    private func finish(throwing error: Error?, from socket: any FishAudioRealtimeSocket) {
        guard self.socket === socket else { return }
        let continuation = self.continuation
        self.continuation = nil
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        disconnect()
    }

    private func failHandshakeIfNotStarted() {
        guard !didStartSession, let socket else { return }
        handshakeTimeoutTask = nil
        finish(throwing: FishAudioRealtimeError.handshakeTimedOut, from: socket)
    }

    /// Sends `keepalive` whenever nothing has been sent for ``keepaliveInterval``.
    private func runKeepalive() async {
        while !Task.isCancelled, socket != nil {
            let deadline = lastSendInstant.advanced(by: keepaliveInterval)
            guard (try? await Task.sleep(until: deadline, clock: .continuous)) != nil else { return }
            guard socket != nil else { return }
            if ContinuousClock.now - lastSendInstant >= keepaliveInterval {
                try? await sendFrame(FishAudioRealtimeClientMessage.keepalive.encoded())
            }
        }
    }
}
