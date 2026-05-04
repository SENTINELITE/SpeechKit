import Foundation

actor ElevenLabsWebSocket {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var continuation: AsyncThrowingStream<ElevenLabsMessage, Error>.Continuation?
    
    private let baseURL = "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    var isConnected: Bool {
        webSocketTask?.state == .running
    }
    
    func connect(apiKey: String, modelID: ElevenLabsModelID) async throws -> AsyncThrowingStream<ElevenLabsMessage, Error> {
        guard let url = URL(string: "\(baseURL)?model_id=\(modelID.rawValue)") else {
            throw ElevenLabsError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
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
    
    func send(_ chunk: InputAudioChunk) async throws {
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
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        continuation?.finish()
        continuation = nil
        session?.invalidateAndCancel()
        session = nil
    }
    
    private func receiveMessages() async {
        guard let task = webSocketTask else { return }
        
        while task.state == .running {
            do {
                let message = try await task.receive()
                
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
                continuation?.finish(throwing: error)
                return
            }
        }
        
        continuation?.finish()
    }
}
