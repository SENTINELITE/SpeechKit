import Foundation
import SwiftUI

/// A SwiftUI-observable Mistral Voxtral realtime transcription service.
///
/// Mistral sends final text as it arrives, so the partial entry only grows.
/// SpeechKit commits it as a transcript entry when a turn ends (with turn
/// detection), when the speaker changes (with diarization), and when the
/// session stops.
@Observable
@MainActor
public final class MistralRealtimeService {
    /// The current realtime connection state.
    public private(set) var connectionState: SpeechRealtimeConnectionState = .disconnected
    /// The latest partial transcript text.
    public private(set) var partialTranscriptText: String = ""
    /// The latest partial transcript entry.
    public private(set) var partialTranscriptEntry: SpeechTranscriptEntry?
    /// The committed transcript entries.
    public private(set) var transcriptEntries: [SpeechTranscriptEntry] = []
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

    /// An override for the Mistral realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL? { didSet { if oldValue != realtimeEndpoint { configurationDidChange() } } }
    /// Options for the Mistral realtime transcription session.
    public var options: MistralRealtimeOptions {
        didSet {
            audioManager.setTargetSampleRate(Double(options.sampleRate))
        }
    }

    private let audioManager: AudioCaptureManager
    private let webSocket = MistralRealtimeWebSocket()
    private var listeningTask: Task<Void, Never>?
    private var audioSendTask: Task<Void, Never>?
    private var authorizationTask: Task<SpeechResolvedCredential, Error>?
    private var reconfigurationTask: Task<Void, Never>?
    public var credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys {
        didSet { if oldValue != credentialPolicy { configurationDidChange() } }
    }
    private var lifecycleRunID = UUID()
    private var isGracefulStopPending = false
    private var gracefulStopWaiter: CheckedContinuation<Void, Never>?
    private let gracefulStopTimeoutNanoseconds: UInt64 = 3_000_000_000
    private var gracefulStopTimeoutTask: Task<Void, Never>?
    private var turnCommitTask: Task<Void, Never>?
    private var pendingText = ""
    private var entryIndex = 0
    private var currentSpeaker: String?
    private var currentTurnStart: Double?
    private var currentTurnEnd: Double?

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

    /// Creates a Mistral realtime transcription service with a long-lived API key.
    public init(
        apiKey: String = "",
        options: MistralRealtimeOptions = MistralRealtimeOptions(),
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credential = .apiKey(apiKey)
        self.credentialPolicy = credentialPolicy
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
        self.audioManager = AudioCaptureManager(targetSampleRate: Double(options.sampleRate))
    }

    /// Creates a Mistral realtime transcription service with any credential.
    public init(
        credential: SpeechCredential,
        options: MistralRealtimeOptions = MistralRealtimeOptions(),
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credential = credential
        self.credentialPolicy = credentialPolicy
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
        self.audioManager = AudioCaptureManager(targetSampleRate: Double(options.sampleRate))
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
            connectionState = .error("Mistral is not configured")
            lastError = MistralRealtimeError.apiKeyMissing
            return
        }

        do {
            try options.validate()
        } catch {
            guard isCurrentLifecycleRun(runID), !Task.isCancelled, !(error is CancellationError) else { return }
            connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            lastError = SpeechErrorBoundary.safe(error)
            return
        }

        let resolvedCredential: SpeechResolvedCredential
        do {
            try credential.validate(provider: .mistral, capability: .realtime, endpoint: realtimeEndpoint ?? MistralRealtimeWebSocket.defaultURL, policy: credentialPolicy)
            try options.validate()
            let task = Task { try await credential.resolved(for: .mistral, capability: .realtime, model: options.modelID.rawValue, endpoint: realtimeEndpoint ?? MistralRealtimeWebSocket.defaultURL, policy: credentialPolicy) }
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
        lastError = nil
        resetTurnState()

        let hasPermission = await audioManager.requestPermission()
        guard isCurrentLifecycleRun(runID), !Task.isCancelled else { return }
        guard hasPermission else {
            connectionState = .error("Microphone permission denied")
            lastError = SpeechAudioCaptureError.permissionDenied
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

                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID), !Task.isCancelled else { break }

                    if let startedSendTask = handleMessage(message, runID: runID, startsCapture: true) {
                        audioSendTask = startedSendTask
                    }
                }

                finishGracefulStopWaiter()
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    lastError = SpeechErrorBoundary.safe(error)
                    connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
                }
                finishGracefulStopWaiter()
            }

            await cleanupAfterStop(runID: runID)
        }
    }

    /// Stops realtime microphone transcription and disconnects from Mistral.
    ///
    /// SpeechKit tells Mistral the audio has ended and waits briefly for the
    /// last text before committing it.
    public func stopListening() async {
        authorizationTask?.cancel()
        authorizationTask = nil
        if listeningTask == nil { invalidateLifecycleRun() }

        guard connectionState.isLifecycleActive || listeningTask != nil || audioManager.isCapturing else {
            connectionState = .disconnected
            return
        }

        connectionState = .stopping
        audioManager.stopCapture()
        // Let the chunks already captured reach Mistral before the end marker.
        await audioSendTask?.value
        audioSendTask = nil
        isGracefulStopPending = true

        do {
            try await webSocket.sendAudioEnd()
        } catch {
            finishGracefulStopWaiter()
        }

        await waitForGracefulStop()
        commitPendingText()
        invalidateLifecycleRun()
        listeningTask?.cancel()
        listeningTask = nil
        await webSocket.disconnect()
        audioManager.stopCapture()
        connectionState = .disconnected
    }

    /// Clears committed and partial realtime transcript text.
    public func clearTranscript() {
        transcriptEntries.removeAll()
        resetTurnState()
    }

    /// Sets lifecycle state for tests that exercise facade orchestration without opening audio devices.
    func setLifecycleStateForTesting(_ state: SpeechRealtimeConnectionState) {
        connectionState = state
    }

    /// Feeds a realtime message to the state machine for tests that run without opening audio devices.
    func handleMessageForTesting(_ message: MistralRealtimeMessage) {
        _ = handleMessage(message, runID: lifecycleRunID, startsCapture: false)
    }

    /// Applies one server message to the session state machine.
    ///
    /// Returns the audio send task when the message started microphone capture.
    private func handleMessage(
        _ message: MistralRealtimeMessage,
        runID: UUID,
        startsCapture: Bool
    ) -> Task<Void, Never>? {
        switch message {
        case .sessionCreated(let requestID):
            guard connectionState == .connecting else { return nil }
            connectionState = .connected(sessionID: requestID ?? "")

        case .sessionUpdated:
            // Only the first confirmation starts capture: a second one would
            // start another capture and orphan the running audio send task.
            guard case .connected = connectionState, startsCapture else { return nil }
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

        case .textDelta(let text):
            appendPendingText(text)

        case .segment(let text, let speakerID):
            if speakerID != currentSpeaker {
                commitPendingText()
                currentSpeaker = speakerID
            }
            appendPendingText(text)

        case .turnStart(let timeSeconds):
            // The text of a turn trails its `turn.end`, so the previous turn is
            // only complete once the next one starts.
            commitPendingText()
            currentTurnStart = timeSeconds
            currentTurnEnd = nil

        case .turnEnd(let timeSeconds, _):
            currentTurnEnd = timeSeconds
            scheduleTurnCommit()

        case .turnEagerEnd, .turnResume:
            break

        case .done:
            commitPendingText()
            finishGracefulStopWaiter()

        case .error:
            lastError = SpeechFailure(.server)
            connectionState = .error("The realtime session failed.")
            finishGracefulStopWaiter()

        case .unknown:
            break
        }

        return nil
    }

    private func appendPendingText(_ text: String) {
        guard !text.isEmpty else { return }
        // Deltas carry their own spacing and punctuation, so they are appended as-is.
        pendingText += text
        let trimmed = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        partialTranscriptText = trimmed
        partialTranscriptEntry = SpeechTranscriptEntry(
            provider: .mistral,
            sourceID: String(entryIndex),
            text: trimmed,
            start: currentTurnStart,
            isFinal: true,
            isUtteranceFinal: false,
            speaker: currentSpeaker
        )
    }

    private func commitPendingText() {
        turnCommitTask?.cancel()
        turnCommitTask = nil

        let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = ""
        partialTranscriptText = ""
        partialTranscriptEntry = nil

        let start = currentTurnStart
        let duration: Double? = {
            guard let start, let end = currentTurnEnd, end >= start else { return nil }
            return end - start
        }()
        currentTurnStart = nil
        currentTurnEnd = nil

        guard !text.isEmpty else { return }
        transcriptEntries.append(
            SpeechTranscriptEntry(
                provider: .mistral,
                sourceID: String(entryIndex),
                text: text,
                start: start,
                duration: duration,
                isFinal: true,
                isUtteranceFinal: true,
                speaker: currentSpeaker
            )
        )
        entryIndex += 1
    }

    /// Commits the ended turn once its trailing text has had time to arrive.
    ///
    /// Mistral delivers the last words of a turn after `turn.end`, roughly one
    /// streaming delay later. A following `turn.start` commits sooner.
    private func scheduleTurnCommit() {
        turnCommitTask?.cancel()
        let delayMilliseconds = UInt64(options.targetStreamingDelayMilliseconds ?? 480) + 400
        turnCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayMilliseconds * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.commitPendingText()
        }
    }

    private func waitForGracefulStop() async {
        guard isGracefulStopPending else { return }

        // Stay on the main actor for the whole wait. A detached child task that
        // captured `self` was rejected as a data race by the Xcode 26.2 compiler.
        await withCheckedContinuation { continuation in
            gracefulStopWaiter = continuation
            gracefulStopTimeoutTask = Task { @MainActor [weak self, gracefulStopTimeoutNanoseconds] in
                try? await Task.sleep(nanoseconds: gracefulStopTimeoutNanoseconds)
                guard !Task.isCancelled else { return }
                self?.finishGracefulStopWaiter()
            }
        }

        gracefulStopTimeoutTask?.cancel()
        gracefulStopTimeoutTask = nil
    }

    private func finishGracefulStopWaiter() {
        isGracefulStopPending = false
        gracefulStopWaiter?.resume()
        gracefulStopWaiter = nil
    }

    private func sendAudioChunks(_ stream: AsyncStream<Data>, runID: UUID) async {
        for await audioData in stream {
            if Task.isCancelled { break }
            guard isCurrentLifecycleRun(runID) else { break }

            do {
                try await webSocket.sendAudio(audioData)
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    lastError = SpeechErrorBoundary.safe(error)
                }
                break
            }
        }
    }

    private func cleanupAfterStop(runID: UUID) async {
        guard isCurrentLifecycleRun(runID) else { return }
        audioManager.stopCapture()
        audioSendTask?.cancel()
        audioSendTask = nil
        await webSocket.disconnect()
        commitPendingText()
        if connectionState.isLifecycleActive {
            connectionState = .disconnected
        }
    }

    private func resetTurnState() {
        turnCommitTask?.cancel()
        turnCommitTask = nil
        pendingText = ""
        partialTranscriptText = ""
        partialTranscriptEntry = nil
        currentSpeaker = nil
        currentTurnStart = nil
        currentTurnEnd = nil
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
