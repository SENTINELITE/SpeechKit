import Foundation
import SwiftUI

/// A SwiftUI-observable OpenAI realtime transcription service.
@Observable
@MainActor
public final class OpenAIRealtimeService {
    /// The current realtime connection state.
    public private(set) var connectionState: SpeechRealtimeConnectionState = .disconnected
    /// The latest partial transcript text.
    public private(set) var partialTranscriptText: String = ""
    /// The committed transcript entries.
    public private(set) var transcriptEntries: [SpeechTranscriptEntry] = []
    /// Detected languages keyed by the completed OpenAI Realtime item identifier.
    public private(set) var detectedLanguagesByItemID: [String: [OpenAITranscriptionLanguage]] = [:]
    /// The most recent realtime error, if any.
    public private(set) var lastError: Error?

    /// The credential used for realtime transcription.
    var credential: SpeechCredential { didSet { if oldValue != credential { configurationDidChange() } } }
    /// The configured authorization mode, without exposing its value.
    public var credentialKind: SpeechCredential.Kind { credential.kind }
    public var hasCredential: Bool { credential.isConfigured }
    public func setCredential(_ credential: SpeechCredential) {
        configurationDidChange()
        self.credential = credential
    }

    /// An override for the OpenAI realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL? { didSet { if oldValue != realtimeEndpoint { configurationDidChange() } } }
    /// Options for the OpenAI realtime transcription session.
    public var options: OpenAIRealtimeSessionOptions

    private let audioManager = AudioCaptureManager(targetSampleRate: 24000)
    private let webSocket = OpenAIRealtimeWebSocket()
    private var listeningTask: Task<Void, Never>?
    private var partialsByItemID: [String: String] = [:]
    private var commitTask: Task<Void, Never>?
    private var authorizationTask: Task<SpeechResolvedCredential, Error>?
    private var reconfigurationTask: Task<Void, Never>?
    public var credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys {
        didSet { if oldValue != credentialPolicy { configurationDidChange() } }
    }
    private var lifecycleRunID = UUID()

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

    /// Creates an OpenAI realtime transcription service with a long-lived API key.
    public init(
        apiKey: String = "",
        options: OpenAIRealtimeSessionOptions = OpenAIRealtimeSessionOptions(),
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credential = .apiKey(apiKey)
        self.credentialPolicy = credentialPolicy
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
    }

    /// Creates an OpenAI realtime transcription service with any credential.
    public init(
        credential: SpeechCredential,
        options: OpenAIRealtimeSessionOptions = OpenAIRealtimeSessionOptions(),
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credential = credential
        self.credentialPolicy = credentialPolicy
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
    }

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
        let options = options
        let realtimeEndpoint = realtimeEndpoint
        connectionState = .connecting
        let teardown = reconfigurationTask
        await teardown?.value
        guard isCurrentLifecycleRun(runID), !Task.isCancelled else { return }

        guard credential.isConfigured else {
            connectionState = .error("OpenAI is not configured")
            lastError = OpenAIError.apiKeyMissing
            return
        }

        let resolvedCredential: SpeechResolvedCredential
        do {
            try credential.validate(provider: .openAI, capability: .realtime, endpoint: realtimeEndpoint ?? OpenAIRealtimeWebSocket.defaultURL, policy: credentialPolicy)
            try options.validate()
            let task = Task { try await credential.resolved(for: .openAI, capability: .realtime, model: options.transcriptionModelID.rawValue, endpoint: realtimeEndpoint ?? OpenAIRealtimeWebSocket.defaultURL, policy: credentialPolicy) }
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
            lastError = OpenAIError.permissionDenied
            return
        }


        listeningTask = Task {
            do {
                let messageStream = try await webSocket.connect(
                    credential: resolvedCredential,
                    options: options,
                    endpoint: realtimeEndpoint
                )
                guard isCurrentLifecycleRun(runID), !Task.isCancelled else {
                    await webSocket.disconnect()
                    return
                }
                let audioStream = try audioManager.startCapture()
                guard isCurrentLifecycleRun(runID), !Task.isCancelled else {
                    audioManager.stopCapture()
                    await webSocket.disconnect()
                    return
                }
                connectionState = .listening

                let sendTask = Task {
                    await sendAudioChunks(audioStream, runID: runID)
                }
                let commitTask = makeCommitTask(interval: options.commitInterval, runID: runID)
                self.commitTask = commitTask

                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID), !Task.isCancelled else { break }

                    switch message {
                    case .sessionCreated(let sessionID), .sessionUpdated(let sessionID):
                        if let sessionID, !connectionState.isListening {
                            connectionState = .connected(sessionID: sessionID)
                        }

                    case .transcriptionDelta(let delta):
                        let key = delta.itemID ?? "current"
                        partialsByItemID[key, default: ""] += delta.delta
                        partialTranscriptText = partialsByItemID[key, default: ""]

                    case .transcriptionCompleted(let completed):
                        if let itemID = completed.itemID, let languages = completed.languages {
                            detectedLanguagesByItemID[itemID] = languages
                        }
                        let text = completed.transcript.isEmpty
                            ? partialsByItemID[completed.itemID ?? "current", default: ""]
                            : completed.transcript
                        if !text.isEmpty {
                            transcriptEntries.append(
                                SpeechTranscriptEntry(
                                    provider: .openAI,
                                    sourceID: completed.itemID,
                                    text: text
                                )
                            )
                            partialsByItemID[completed.itemID ?? "current"] = nil
                            partialTranscriptText = ""
                        }

                    case .error:
                        lastError = SpeechFailure(.server)
                        connectionState = .error("The realtime session failed.")

                    case .unknown:
                        break
                    }
                }

                sendTask.cancel()
                commitTask?.cancel()
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    lastError = SpeechErrorBoundary.safe(error)
                    connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
                }
            }

            await cleanupAfterStop(runID: runID)
        }
    }

    /// Stops realtime microphone transcription and disconnects from OpenAI.
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
        commitTask?.cancel()
        commitTask = nil

        do {
            try await webSocket.commitInputAudioBuffer()
        } catch {
            // Ignore errors when stopping.
        }

        await webSocket.disconnect()
        audioManager.stopCapture()
        connectionState = .disconnected
    }

    /// Clears committed and partial realtime transcript text.
    public func clearTranscript() {
        transcriptEntries.removeAll()
        detectedLanguagesByItemID.removeAll()
        partialTranscriptText = ""
        partialsByItemID.removeAll()
    }

    /// Sets lifecycle state for tests that exercise facade orchestration without opening audio devices.
    func setLifecycleStateForTesting(_ state: SpeechRealtimeConnectionState) {
        connectionState = state
    }

    private func sendAudioChunks(_ stream: AsyncStream<Data>, runID: UUID) async {
        for await audioData in stream {
            if Task.isCancelled { break }
            guard isCurrentLifecycleRun(runID) else { break }

            do {
                try await webSocket.send(OpenAIInputAudioBufferAppendMessage(audioData: audioData))
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

    private func makeCommitTask(interval: TimeInterval, runID: UUID) -> Task<Void, Never>? {
        guard interval > 0 else { return nil }

        return Task {
            let nanoseconds = UInt64(interval * 1_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                if Task.isCancelled { break }
                guard await MainActor.run(body: { isCurrentLifecycleRun(runID) }) else { break }
                try? await webSocket.commitInputAudioBuffer()
            }
        }
    }

    private func cleanupAfterStop(runID: UUID) async {
        guard isCurrentLifecycleRun(runID) else { return }
        commitTask?.cancel()
        commitTask = nil
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
