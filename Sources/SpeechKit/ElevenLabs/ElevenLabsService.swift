import Foundation
import SwiftUI

@Observable
@MainActor
public final class ElevenLabsService {
    
    // MARK: - Public State
    
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var partialTranscript: String = ""
    public private(set) var committedTranscripts: [TranscriptEntry] = []
    public private(set) var lastError: Error?
    
    // MARK: - Configuration
    
    public var apiKey: String
    public var modelId: ElevenLabsModelID
    
    // MARK: - Private
    
    private let audioManager = AudioCaptureManager()
    private let webSocket = ElevenLabsWebSocket()
    private var listeningTask: Task<Void, Never>?
    
    // MARK: - Types
    
    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(sessionId: String)
        case listening
        case error(String)
        
        public var isActive: Bool {
            switch self {
            case .connected, .listening:
                return true
            default:
                return false
            }
        }
        
        public var isListening: Bool {
            if case .listening = self { return true }
            return false
        }
    }
    
    public struct TranscriptEntry: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let text: String
        public let timestamp: Date
        
        public init(id: UUID = UUID(), text: String, timestamp: Date = Date()) {
            self.id = id
            self.text = text
            self.timestamp = timestamp
        }
    }
    
    // MARK: - Computed Properties
    
    public var fullTranscript: String {
        committedTranscripts.map(\.text).joined(separator: " ")
    }
    
    // MARK: - Initialization
    
    public init(apiKey: String = "", modelId: ElevenLabsModelID = .scribeV2Realtime) {
        self.apiKey = apiKey
        self.modelId = modelId
    }
    
    // MARK: - Public Methods
    
    public func startListening() async {
        guard !apiKey.isEmpty else {
            connectionState = .error("API key not configured")
            lastError = ElevenLabsError.apiKeyMissing
            return
        }
        
        let hasPermission = await audioManager.requestPermission()
        guard hasPermission else {
            connectionState = .error("Microphone permission denied")
            lastError = ElevenLabsError.permissionDenied
            return
        }
        
        connectionState = .connecting
        partialTranscript = ""
        lastError = nil
        
        listeningTask = Task {
            do {
                let messageStream = try await webSocket.connect(apiKey: apiKey, modelId: modelId)
                
                var sendTask: Task<Void, Never>?
                
                for try await message in messageStream {
                    if Task.isCancelled { break }
                    
                    switch message {
                    case .sessionStarted(let session):
                        connectionState = .connected(sessionId: session.sessionId)
                        
                        do {
                            let audioStream = try audioManager.startCapture()
                            connectionState = .listening
                            
                            sendTask = Task {
                                await sendAudioChunks(audioStream)
                            }
                        } catch {
                            lastError = error
                            connectionState = .error("Failed to start audio capture")
                        }
                        
                    case .partialTranscript(let partial):
                        partialTranscript = partial.text
                        
                    case .committedTranscript(let committed):
                        if !committed.text.isEmpty {
                            let entry = TranscriptEntry(text: committed.text)
                            committedTranscripts.append(entry)
                            partialTranscript = ""
                        }
                        
                    case .committedTranscriptWithTimestamps(let committed):
                        if !committed.text.isEmpty {
                            let entry = TranscriptEntry(text: committed.text)
                            committedTranscripts.append(entry)
                            partialTranscript = ""
                        }
                        
                    case .unknown(let type):
                        print("[ElevenLabsService] Unknown message type: \(type)")
                    }
                }
                
                sendTask?.cancel()
                
            } catch {
                if !Task.isCancelled {
                    lastError = error
                    connectionState = .error(error.localizedDescription)
                }
            }
            
            await cleanupAfterStop()
        }
    }
    
    public func stopListening() async {
        listeningTask?.cancel()
        listeningTask = nil
        
        do {
            try await webSocket.sendEndOfStream()
        } catch {
            // Ignore errors when stopping
        }
        
        await webSocket.disconnect()
        audioManager.stopCapture()
        connectionState = .disconnected
    }
    
    public func clearTranscripts() {
        committedTranscripts.removeAll()
        partialTranscript = ""
    }
    
    // MARK: - Private Methods
    
    private func sendAudioChunks(_ stream: AsyncStream<Data>) async {
        for await audioData in stream {
            if Task.isCancelled { break }
            
            let chunk = InputAudioChunk(audioData: audioData)
            do {
                try await webSocket.send(chunk)
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        lastError = error
                    }
                }
                break
            }
        }
    }
    
    private func cleanupAfterStop() async {
        audioManager.stopCapture()
        await webSocket.disconnect()
        if case .listening = connectionState {
            connectionState = .disconnected
        }
    }
}
