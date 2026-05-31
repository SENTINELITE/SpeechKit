import AVFoundation
import Foundation
import OSLog
import SwiftUI

/// A SwiftUI-observable ElevenLabs realtime transcription service.
@Observable
@MainActor
public final class ElevenLabsService {
    
    // MARK: - Public State
    
    /// The current realtime connection state.
    public private(set) var connectionState: SpeechRealtimeConnectionState = .disconnected
    /// The latest partial transcript text.
    public private(set) var partialTranscriptText: String = ""
    /// The committed transcript entries.
    public private(set) var transcriptEntries: [SpeechTranscriptEntry] = []
    /// The most recent realtime error, if any.
    public private(set) var lastError: Error?
    
    // MARK: - Configuration
    
    /// The ElevenLabs API key used for realtime and file transcription.
    public var apiKey: String
    /// The ElevenLabs realtime model used when listening.
    public var realtimeModelID: ElevenLabsModelID
    
    // MARK: - Private
    
    private let audioManager = AudioCaptureManager()
    private let webSocket = ElevenLabsWebSocket()
    private var listeningTask: Task<Void, Never>?
    private var lifecycleRunID = UUID()
    private static let logger = Logger(subsystem: "com.sentinelite.SpeechKit", category: "ElevenLabsRealtime")
    // MARK: - Types
    
    /// A nested name for the shared realtime connection state.
    public typealias ConnectionState = SpeechRealtimeConnectionState
    
    /// A committed realtime transcript entry.
    /// A nested name for normalized realtime transcript entries.
    public typealias TranscriptEntry = SpeechTranscriptEntry

    // MARK: - Computed Properties
    
    /// The committed transcript text joined with spaces.
    public var transcriptText: String {
        transcriptEntries.map(\.text).joined(separator: " ")
    }

    /// The latest normalized microphone input level for the active realtime capture.
    public var realtimeAudioLevel: Double {
        audioManager.currentLevel
    }

    /// The latest realtime microphone recording as WAV data, if capture has produced audio.
    public var realtimeRecordingData: Data? {
        audioManager.recordedWAVData
    }

    // MARK: - Initialization
    
    /// Creates an ElevenLabs realtime transcription service.
    public init(apiKey: String = "", realtimeModelID: ElevenLabsModelID = .scribeV2Realtime) {
        self.apiKey = apiKey
        self.realtimeModelID = realtimeModelID
    }
    
    // MARK: - Public Methods
    
    /// Starts realtime microphone transcription.
    public func startListening() async {
        guard !connectionState.isLifecycleActive else { return }

        guard !apiKey.isEmpty else {
            connectionState = .error("API key not configured")
            lastError = ElevenLabsError.apiKeyMissing
            return
        }

        let runID = beginLifecycleRun()
        connectionState = .connecting
        partialTranscriptText = ""
        lastError = nil
        
        let hasPermission = await audioManager.requestPermission()
        guard isCurrentLifecycleRun(runID) else { return }
        guard hasPermission else {
            connectionState = .error("Microphone permission denied")
            lastError = ElevenLabsError.permissionDenied
            return
        }

        let apiKey = apiKey
        let realtimeModelID = realtimeModelID
        
        listeningTask = Task {
            do {
                let messageStream = try await webSocket.connect(apiKey: apiKey, modelID: realtimeModelID)
                guard isCurrentLifecycleRun(runID) else {
                    await webSocket.disconnect()
                    return
                }
                
                var sendTask: Task<Void, Never>?
                
                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID) else { break }
                    
                    switch message {
                    case .sessionStarted(let session):
                        connectionState = .connected(sessionID: session.sessionID)
                        
                        do {
                            let audioStream = try audioManager.startCapture()
                            connectionState = .listening
                            
                            sendTask = Task {
                                await sendAudioChunks(audioStream, runID: runID)
                            }
                        } catch {
                            if isCurrentLifecycleRun(runID) {
                                lastError = error
                                connectionState = .error("Failed to start audio capture")
                            }
                        }
                        
                    case .partialTranscript(let partial):
                        partialTranscriptText = partial.text
                        
                    case .committedTranscript(let committed):
                        if !committed.text.isEmpty {
                            let entry = SpeechTranscriptEntry(provider: .elevenLabs, text: committed.text)
                            transcriptEntries.append(entry)
                            partialTranscriptText = ""
                        }
                        
                    case .committedTranscriptWithTimestamps(let committed):
                        if !committed.text.isEmpty {
                            let entry = SpeechTranscriptEntry(
                                provider: .elevenLabs,
                                text: committed.text,
                                words: committed.words?.map(SpeechTranscriptWord.init) ?? []
                            )
                            transcriptEntries.append(entry)
                            partialTranscriptText = ""
                        }
                        
                    case .unknown(let type):
                        Self.logger.debug("Ignoring unknown ElevenLabs realtime message type: \(type, privacy: .public)")
                    }
                }
                
                sendTask?.cancel()
                
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    lastError = error
                    connectionState = .error(error.localizedDescription)
                }
            }
            
            await cleanupAfterStop(runID: runID)
        }
    }
    
    /// Stops realtime microphone transcription and disconnects the WebSocket.
    public func stopListening() async {
        guard connectionState.isLifecycleActive || listeningTask != nil || audioManager.isCapturing else {
            connectionState = .disconnected
            return
        }

        invalidateLifecycleRun()
        connectionState = .stopping
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
    public func clearTranscript() {
        transcriptEntries.removeAll()
        partialTranscriptText = ""
    }

    /// Sets lifecycle state for tests that exercise facade orchestration without opening audio devices.
    func setLifecycleStateForTesting(_ state: SpeechRealtimeConnectionState) {
        connectionState = state
    }

    // MARK: - Private Methods
    
    private func sendAudioChunks(_ stream: AsyncStream<Data>, runID: UUID) async {
        for await audioData in stream {
            if Task.isCancelled { break }
            guard isCurrentLifecycleRun(runID) else { break }
            
            let chunk = InputAudioChunk(audioData: audioData)
            do {
                try await webSocket.send(chunk)
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    await MainActor.run {
                        lastError = error
                    }
                }
                break
            }
        }
    }
    
    private func cleanupAfterStop(runID: UUID) async {
        guard isCurrentLifecycleRun(runID) else { return }
        audioManager.stopCapture()
        await webSocket.disconnect()
        if connectionState.isLifecycleActive {
            connectionState = .disconnected
        }
    }

    private func beginLifecycleRun() -> UUID {
        let runID = UUID()
        lifecycleRunID = runID
        return runID
    }

    private func invalidateLifecycleRun() {
        lifecycleRunID = UUID()
    }

    private func isCurrentLifecycleRun(_ runID: UUID) -> Bool {
        lifecycleRunID == runID
    }

}
