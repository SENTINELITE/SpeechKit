import Foundation

actor ElevenLabsWebSocket {
    private var connectionGeneration = UUID()
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<ElevenLabsMessage, Error>.Continuation?
    
    static let defaultURL = URL(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    var isConnected: Bool {
        webSocketTask?.state == .running
    }
    
    /// Builds the WebSocket handshake request for a realtime session.
    ///
    /// An API key goes in the `xi-api-key` header. A short-lived ElevenLabs
    /// token goes in the `token` query parameter, which is where ElevenLabs
    /// accepts single-use realtime scribe tokens.
    nonisolated static func makeConnectRequest(
        credential: SpeechResolvedCredential,
        modelID: ElevenLabsModelID,
        endpoint: URL? = nil
    ) throws -> URLRequest {
        try SpeechEndpointPolicy.validate(endpoint ?? defaultURL, websocket: true)
        try SpeechResolvedCredential.validateSecret(credential.secret)
        guard let baseURL = endpoint ?? defaultURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ElevenLabsError.invalidURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "model_id", value: modelID.rawValue))

        components.queryItems = queryItems

        guard let url = components.url else {
            throw ElevenLabsError.invalidURL
        }

        var request = URLRequest(url: url)
        try credential.authorize(&request, provider: .elevenLabs, capability: .realtime)
        return request
    }

    func connect(
        credential: SpeechResolvedCredential,
        modelID: ElevenLabsModelID,
        endpoint: URL? = nil
    ) async throws -> AsyncThrowingStream<ElevenLabsMessage, Error> {
        let request = try Self.makeConnectRequest(credential: credential, modelID: modelID, endpoint: endpoint)

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
    
    func send(_ chunk: InputAudioChunk) async throws {
        try Task.checkCancellation()
        guard let task = webSocketTask, task.state == .running else {
            throw ElevenLabsError.disconnected
        }
        
        let data = try encoder.encode(chunk)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ElevenLabsError.encodingFailed
        }
        
        try await task.send(.string(jsonString))
    }
    
    func sendEndOfStream() async throws {
        try Task.checkCancellation()
        guard let task = webSocketTask, task.state == .running else {
            throw ElevenLabsError.disconnected
        }
        
        let message = EndOfStreamMessage()
        let data = try encoder.encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ElevenLabsError.encodingFailed
        }
        
        try await task.send(.string(jsonString))
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
                    do {
                        let decoded = try decoder.decode(ElevenLabsMessage.self, from: data)
                        continuation?.yield(decoded)
                    } catch {
                        continuation?.yield(.unknown("decode_error"))
                    }
                    
                case .data(let data):
                    do {
                        let decoded = try decoder.decode(ElevenLabsMessage.self, from: data)
                        continuation?.yield(decoded)
                    } catch {
                        continuation?.yield(.unknown("decode_error"))
                    }
                    
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
}
