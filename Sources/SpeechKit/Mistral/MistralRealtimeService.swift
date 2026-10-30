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
    public var credential: SpeechCredential
    /// The Mistral API key used for realtime transcription.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// An override for the Mistral realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL?
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

    /// The latest realtime microphone recording as WAV data, if capture has produced audio.
    public var realtimeRecordingData: Data? {
        audioManager.recordedWAVData
    }

    /// Creates a Mistral realtime transcription service with a long-lived API key.
    public init(
        apiKey: String = "",
        options: MistralRealtimeOptions = MistralRealtimeOptions(),
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = .apiKey(apiKey)
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
        self.audioManager = AudioCaptureManager(targetSampleRate: Double(options.sampleRate))
    }

    /// Creates a Mistral realtime transcription service with any credential.
    public init(
        credential: SpeechCredential,
        options: MistralRealtimeOptions = MistralRealtimeOptions(),
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = credential
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
        self.audioManager = AudioCaptureManager(targetSampleRate: Double(options.sampleRate))
    }

    /// Starts realtime microphone transcription.
    public func startListening() async {
        guard !connectionState.isLifecycleActive else { return }

        guard credential.isConfigured else {
            connectionState = .error("Mistral is not configured")
            lastError = MistralRealtimeError.apiKeyMissing
            return
        }

        do {
            try options.validate()
        } catch {
            connectionState = .error(error.localizedDescription)
            lastError = error
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
        lastError = nil
        resetTurnState()

        let hasPermission = await audioManager.requestPermission()
        guard isCurrentLifecycleRun(runID) else { return }
        guard hasPermission else {
            connectionState = .error("Microphone permission denied")
            lastError = SpeechAudioCaptureError.permissionDenied
            return
        }

        let options = options
        let realtimeEndpoint = realtimeEndpoint

        listeningTask = Task {
            do {
                let messageStream = try await webSocket.connect(
                    credential: resolvedCredential,
                    options: options,
                    endpoint: realtimeEndpoint
                )
                guard isCurrentLifecycleRun(runID) else {
                    await webSocket.disconnect()
                    return
                }

                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID) else { break }

                    if let startedSendTask = handleMessage(message, runID: runID, startsCapture: true) {
                        audioSendTask = startedSendTask
                    }
                }

                finishGracefulStopWaiter()
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    lastError = error
                    connectionState = .error(error.localizedDescription)
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
                    lastError = error
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

        case .error(let message):
            lastError = MistralRealtimeError.connectionFailed(message)
            connectionState = .error(message)
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
                    lastError = error
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
}
