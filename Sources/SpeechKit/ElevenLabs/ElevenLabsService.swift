import AVFoundation
import Foundation
import SwiftUI

/// A SwiftUI-observable ElevenLabs realtime transcription service.
@Observable
@MainActor
public final class ElevenLabsService {
    
    // MARK: - Public State
    
    /// The current realtime connection state.
    public private(set) var connectionState: ConnectionState = .disconnected
    /// The latest partial transcript text.
    public private(set) var partialTranscript: String = ""
    /// The committed transcript entries.
    public private(set) var committedTranscripts: [TranscriptEntry] = []
    /// The most recent realtime error, if any.
    public private(set) var lastError: Error?
    
    // MARK: - Configuration
    
    /// The ElevenLabs API key used for realtime and file transcription.
    public var apiKey: String
    /// The ElevenLabs realtime model used when listening.
    public var modelID: ElevenLabsModelID
    
    // MARK: - Private
    
    private let audioManager = AudioCaptureManager()
    private let webSocket = ElevenLabsWebSocket()
    private var listeningTask: Task<Void, Never>?
    // MARK: - Types
    
    /// The realtime connection lifecycle state.
    public enum ConnectionState: Equatable, Sendable {
        /// The service is disconnected.
        case disconnected
        /// The service is opening a realtime connection.
        case connecting
        /// The service is connected to a realtime session but not yet sending audio.
        case connected(sessionID: String)
        /// The service is connected and streaming microphone audio.
        case listening
        /// The service is stopped because of an error.
        case error(String)
        
        /// A Boolean value that indicates whether the service has an active realtime session.
        public var isActive: Bool {
            switch self {
            case .connected, .listening:
                return true
            default:
                return false
            }
        }
        
        /// A Boolean value that indicates whether the service is streaming microphone audio.
        public var isListening: Bool {
            if case .listening = self { return true }
            return false
        }
    }
    
    /// A committed realtime transcript entry.
    public struct TranscriptEntry: Identifiable, Equatable, Sendable {
        /// The stable identity of the entry.
        public let id: UUID
        /// The committed transcript text.
        public let text: String
        /// The time when the entry was created.
        public let timestamp: Date
        
        /// Creates a transcript entry.
        public init(id: UUID = UUID(), text: String, timestamp: Date = Date()) {
            self.id = id
            self.text = text
            self.timestamp = timestamp
        }
    }

    /// A detailed ElevenLabs file transcription response.
    public struct FileTranscriptionResponse: Decodable, Sendable {
        /// The transcribed text.
        public let text: String
        /// The detected language code, when ElevenLabs returns one.
        public let languageCode: String?
        /// Optional word-level timestamps.
        public let words: [WordTimestamp]?

        private enum CodingKeys: String, CodingKey {
            case text
            case languageCode = "language_code"
            case words
        }
    }
    
    // MARK: - Computed Properties
    
    /// The committed transcript text joined with spaces.
    public var fullTranscript: String {
        committedTranscripts.map(\.text).joined(separator: " ")
    }
    
    // MARK: - Initialization
    
    /// Creates an ElevenLabs realtime transcription service.
    public init(apiKey: String = "", modelID: ElevenLabsModelID = .scribeV2Realtime) {
        self.apiKey = apiKey
        self.modelID = modelID
    }
    
    // MARK: - Public Methods
    
    /// Starts realtime microphone transcription.
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
                let messageStream = try await webSocket.connect(apiKey: apiKey, modelID: modelID)
                
                var sendTask: Task<Void, Never>?
                
                for try await message in messageStream {
                    if Task.isCancelled { break }
                    
                    switch message {
                    case .sessionStarted(let session):
                        connectionState = .connected(sessionID: session.sessionID)
                        
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
    
    /// Stops realtime microphone transcription and disconnects the WebSocket.
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
    
    /// Clears committed and partial realtime transcript text.
    public func clearTranscripts() {
        committedTranscripts.removeAll()
        partialTranscript = ""
    }

    /// Transcribes an audio file with ElevenLabs Scribe.
    ///
    /// - Throws: ``ElevenLabsError`` when the API key is missing, the file fails validation, or the upload fails.
    public func transcribeAudioFile(file: URL, modelID: ElevenLabsModelID = .scribeV1) async throws -> String {
        let client = ElevenLabsFileTranscriptionClient(apiKey: apiKey)
        return try await client.transcribeAudioFile(file: file, modelID: modelID)
    }

    /// Transcribes a security-scoped audio file URL with ElevenLabs Scribe.
    ///
    /// - Throws: ``ElevenLabsError`` when the URL cannot be accessed, the API key is missing, the file fails validation, or the upload fails.
    public func transcribeAudioFile(securityScopedURL: URL, modelID: ElevenLabsModelID = .scribeV1) async throws -> String {
        let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw ElevenLabsError.securityScopeDenied
        }
        defer { securityScopedURL.stopAccessingSecurityScopedResource() }
        return try await transcribeAudioFile(file: securityScopedURL, modelID: modelID)
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
