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
    var credential: SpeechCredential { didSet { if oldValue != credential { configurationDidChange() } } }
    /// The configured authorization mode, without exposing its value.
    public var credentialKind: SpeechCredential.Kind { credential.kind }
    public var hasCredential: Bool { credential.isConfigured }
    public func setCredential(_ credential: SpeechCredential) {
        configurationDidChange()
        self.credential = credential
    }

    /// An override for the ElevenLabs realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL? { didSet { if oldValue != realtimeEndpoint { configurationDidChange() } } }
    /// The ElevenLabs realtime model used when listening.
    public var realtimeModelID: ElevenLabsModelID
    
    // MARK: - Private
    
    private let audioManager = AudioCaptureManager()
    private let webSocket = ElevenLabsWebSocket()
    private var listeningTask: Task<Void, Never>?
    private var authorizationTask: Task<SpeechResolvedCredential, Error>?
    private var reconfigurationTask: Task<Void, Never>?
    public var credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys {
        didSet { if oldValue != credentialPolicy { configurationDidChange() } }
    }
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

    /// Recording retention after a session stops. The default preserves export after stop.
    public var recordingRetention: SpeechRecordingRetention {
        get { audioManager.recordingRetention }
        set { audioManager.recordingRetention = newValue }
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
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credential = .apiKey(apiKey)
        self.credentialPolicy = credentialPolicy
        self.realtimeModelID = realtimeModelID
        self.realtimeEndpoint = realtimeEndpoint
    }

    /// Creates an ElevenLabs realtime transcription service with any credential.
    public init(
        credential: SpeechCredential,
        realtimeModelID: ElevenLabsModelID = .scribeV2Realtime,
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credential = credential
        self.credentialPolicy = credentialPolicy
        self.realtimeModelID = realtimeModelID
        self.realtimeEndpoint = realtimeEndpoint
    }
    
    // MARK: - Public Methods
    
    /// Starts realtime microphone transcription.
    public func startListening() async {
        guard !connectionState.isLifecycleActive else { return }

        let runID = beginLifecycleRun()
        defer {
            if isCurrentLifecycleRun(runID) {
                authorizationTask = nil
                if Task.isCancelled { configurationDidChange() }
            }
        }
        let credentialPolicy = credentialPolicy
        let credential = credential
        let realtimeModelID = realtimeModelID
        let realtimeEndpoint = realtimeEndpoint
        connectionState = .connecting
        let teardown = reconfigurationTask
        await teardown?.value
        guard isCurrentLifecycleRun(runID), !Task.isCancelled else { return }

        guard credential.isConfigured else {
            connectionState = .error("API key not configured")
            lastError = ElevenLabsError.apiKeyMissing
            return
        }

        let resolvedCredential: SpeechResolvedCredential
        do {
            try credential.validate(provider: .elevenLabs, capability: .realtime, endpoint: realtimeEndpoint ?? ElevenLabsWebSocket.defaultURL, policy: credentialPolicy)
            try SpeechResolvedCredential.validateSecret(credential.staticAPIKey.isEmpty && credential.kind != .apiKey ? "resolver" : credential.staticAPIKey)
            let task = Task { try await credential.resolved(for: .elevenLabs, capability: .realtime, model: realtimeModelID.rawValue, endpoint: realtimeEndpoint ?? ElevenLabsWebSocket.defaultURL, policy: credentialPolicy) }
            authorizationTask = task
            resolvedCredential = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard isCurrentLifecycleRun(runID), !Task.isCancelled else { return }
            authorizationTask = nil
        } catch {
            guard isCurrentLifecycleRun(runID), !Task.isCancelled, !(error is CancellationError) else { return }
            connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            lastError = SpeechErrorBoundary.safe(error)
            return
        }

        connectionState = .connecting
        partialTranscriptText = ""
        lastError = nil
        
        let hasPermission = await audioManager.requestPermission()
        guard isCurrentLifecycleRun(runID), !Task.isCancelled else { return }
        guard hasPermission else {
            connectionState = .error("Microphone permission denied")
            lastError = ElevenLabsError.permissionDenied
            return
        }


        listeningTask = Task {
            do {
                let messageStream = try await webSocket.connect(
                    credential: resolvedCredential,
                    modelID: realtimeModelID,
                    endpoint: realtimeEndpoint
                )
                guard isCurrentLifecycleRun(runID), !Task.isCancelled else {
                    await webSocket.disconnect()
                    return
                }
                
                var sendTask: Task<Void, Never>?
                
                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID), !Task.isCancelled else { break }
                    
                    if let startedSendTask = handleMessage(message, runID: runID, startsCapture: true) {
                        sendTask = startedSendTask
                    }
                }
                
                sendTask?.cancel()
                
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    lastError = SpeechErrorBoundary.safe(error)
                    connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
                }
            }
            
            await cleanupAfterStop(runID: runID)
        }
    }
    
    /// Stops realtime microphone transcription and disconnects the WebSocket.
    public func stopListening() async {
        authorizationTask?.cancel()
        authorizationTask = nil
        if listeningTask == nil { invalidateLifecycleRun() }

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
                    lastError = SpeechErrorBoundary.safe(error)
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

        case .unknown:
            Self.logger.debug("Ignoring unknown ElevenLabs realtime message")
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
                        lastError = SpeechErrorBoundary.safe(error)
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


    private func configurationDidChange() {
        invalidateLifecycleRun()
        authorizationTask?.cancel()
        authorizationTask = nil
        listeningTask?.cancel()
        listeningTask = nil
        audioManager.stopCapture()
        connectionState = .disconnected
        lastError = nil
        let previous = reconfigurationTask
        reconfigurationTask = Task { [webSocket] in
            await previous?.value
            await webSocket.disconnect()
        }
    }

    /// Replaces authorization and its destination together, cancelling the previous session.
    public func reconfigure(credential: SpeechCredential, realtimeEndpoint: URL? = nil) async {
        configurationDidChange()
        self.credential = credential
        self.realtimeEndpoint = realtimeEndpoint
        await reconfigurationTask?.value
    }

    /// Cancels local work. Ordinary stop retains configured authorization and recordings.
    public func resetSession(discardTranscript: Bool = true, discardRecording: Bool = true) async {
        configurationDidChange()
        await reconfigurationTask?.value
        lastError = nil
        if discardTranscript { clearTranscript() }
        if discardRecording { self.discardRecording() }
    }

    public func clearCredentials() async {
        credential = .apiKey("")
        await resetSession()
    }

    public func discardRecording() { audioManager.discardRecording() }
}
