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
    
    /// The credential used for realtime transcription.
    public var credential: SpeechCredential
    /// The ElevenLabs API key used for realtime transcription.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// An override for the ElevenLabs realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL?
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
    
    /// Creates an ElevenLabs realtime transcription service with a long-lived API key.
    public init(
        apiKey: String = "",
        realtimeModelID: ElevenLabsModelID = .scribeV2Realtime,
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = .apiKey(apiKey)
        self.realtimeModelID = realtimeModelID
        self.realtimeEndpoint = realtimeEndpoint
    }

    /// Creates an ElevenLabs realtime transcription service with any credential.
    public init(
        credential: SpeechCredential,
        realtimeModelID: ElevenLabsModelID = .scribeV2Realtime,
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = credential
        self.realtimeModelID = realtimeModelID
        self.realtimeEndpoint = realtimeEndpoint
    }
    
    // MARK: - Public Methods
    
    /// Starts realtime microphone transcription.
    public func startListening() async {
        guard !connectionState.isLifecycleActive else { return }

        guard credential.isConfigured else {
            connectionState = .error("API key not configured")
            lastError = ElevenLabsError.apiKeyMissing
            return
        }

        let resolvedCredential: SpeechResolvedCredential
        do {
            resolvedCredential = try await credential.resolved()
        } catch {
            connectionState = .error(error.localizedDescription)
            lastError = error
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

        let realtimeModelID = realtimeModelID
        let realtimeEndpoint = realtimeEndpoint

        listeningTask = Task {
            do {
                let messageStream = try await webSocket.connect(
                    credential: resolvedCredential,
                    modelID: realtimeModelID,
                    endpoint: realtimeEndpoint
                )
                guard isCurrentLifecycleRun(runID) else {
                    await webSocket.disconnect()
                    return
                }
                
                var sendTask: Task<Void, Never>?
                
                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID) else { break }
                    
                    if let startedSendTask = handleMessage(message, runID: runID, startsCapture: true) {
                        sendTask = startedSendTask
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

    /// Feeds a realtime message to the state machine for tests that run without opening audio devices.
    func handleMessageForTesting(_ message: ElevenLabsMessage) {
        _ = handleMessage(message, runID: lifecycleRunID, startsCapture: false)
    }

    /// Applies one server message to the session state machine.
    ///
    /// Returns the audio send task when the message started microphone capture.
    private func handleMessage(
        _ message: ElevenLabsMessage,
        runID: UUID,
        startsCapture: Bool
    ) -> Task<Void, Never>? {
        switch message {
        case .sessionStarted(let session):
            // Ignore a duplicate acknowledgement: re-running this branch would
            // start a second capture and orphan the running audio send task.
            guard connectionState == .connecting else { return nil }
            connectionState = .connected(sessionID: session.sessionID)
            guard startsCapture else { return nil }
            do {
                let audioStream = try audioManager.startCapture()
                connectionState = .listening
                return Task {
                    await sendAudioChunks(audioStream, runID: runID)
                }
            } catch {
                if isCurrentLifecycleRun(runID) {
                    lastError = error
                    connectionState = .error("Failed to start audio capture")
                }
                return nil
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

        return nil
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
