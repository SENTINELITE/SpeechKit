import Foundation
import SwiftUI

/// A SwiftUI-observable Gemini Live realtime transcription service.
@Observable
@MainActor
public final class GeminiRealtimeService {
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
    /// The Google AI API key used for realtime transcription.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// An override for the Google AI realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL?
    /// Options for the Gemini Live realtime transcription session.
    public var options: GeminiRealtimeOptions

    private let audioManager: AudioCaptureManager
    private let webSocket = GeminiLiveWebSocket()
    private var listeningTask: Task<Void, Never>?
    private var committedFingerprints: Set<String> = []
    private var lifecycleRunID = UUID()
    private var isGracefulStopPending = false
    private var gracefulStopWaiter: CheckedContinuation<Void, Never>?
    private let gracefulStopTimeoutNanoseconds: UInt64 = 2_000_000_000
    private var gracefulStopTimeoutTask: Task<Void, Never>?
    private var utteranceCount = 0
    private var currentUtteranceID: String?
    private var currentUtteranceCloseKind = UtteranceCloseKind.open
    private var hasHandledSetupComplete = false

    /// How the current Gemini utterance was committed, which decides whether a late final reuses its id.
    private enum UtteranceCloseKind {
        /// No final entry has been committed for the current utterance yet.
        case open
        /// The partial entry was promoted to a final entry while stopping.
        case partialCommit
        /// Gemini sent a final transcription for the current utterance.
        case finalTranscription
    }

    /// A Boolean value that indicates whether SpeechKit has an open manual activity bracket with Gemini.
    ///
    /// This is only ever `true` when ``GeminiRealtimeOptions/automaticActivityDetection``
    /// is `false`, in which case SpeechKit brackets capture with explicit
    /// `activityStart` and `activityEnd` events.
    private(set) var isManualActivityActive = false

    /// The number of times the service has run the setup-complete start branch for the current session.
    ///
    /// Gemini can repeat a `setupComplete` acknowledgement; the start branch must
    /// only run once so the first audio task is never orphaned.
    private(set) var setupCompleteRunCount = 0

    /// The most recent session resumption handle Gemini sent, stored for a resumable-session follow-up.
    private(set) var sessionResumptionHandle: String?

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

    /// Creates a Gemini Live realtime transcription service with a long-lived API key.
    public init(
        apiKey: String = "",
        options: GeminiRealtimeOptions = GeminiRealtimeOptions(),
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = .apiKey(apiKey)
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
        self.audioManager = AudioCaptureManager(targetSampleRate: Double(options.sampleRate))
    }

    /// Creates a Gemini Live realtime transcription service with any credential.
    ///
    /// A ``SpeechCredential/token(_:)`` credential is sent as a Google
    /// ephemeral token in an `Authorization: Token` header, so the secret never
    /// appears in the socket URL.
    public init(
        credential: SpeechCredential,
        options: GeminiRealtimeOptions = GeminiRealtimeOptions(),
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
            connectionState = .error("Gemini is not configured")
            lastError = GeminiRealtimeError.apiKeyMissing
            return
        }

        let resolvedCredential: SpeechResolvedCredential
        do {
            resolvedCredential = try await credential.resolved()
        } catch {
            reportFailure(error)
            return
        }

        do {
            try options.validate()
        } catch {
            reportFailure(error)
            return
        }

        let runID = beginLifecycleRun()
        connectionState = .connecting
        partialTranscriptText = ""
        partialTranscriptEntry = nil
        lastError = nil
        sessionResumptionHandle = nil
        isManualActivityActive = false
        hasHandledSetupComplete = false
        setupCompleteRunCount = 0
        resetUtteranceTracking()

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
                var sendTask: Task<Void, Never>?

                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID) else { break }

                    if let startedSendTask = await handle(message, runID: runID, startsCapture: true) {
                        sendTask = startedSendTask
                    }
                }

                sendTask?.cancel()
                finishGracefulStopWaiter()
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    reportFailure(error)
                }
                finishGracefulStopWaiter()
            }

            await cleanupAfterStop(runID: runID)
        }
    }

    /// Stops realtime microphone transcription and disconnects from Gemini.
    public func stopListening() async {
        guard connectionState.isLifecycleActive || listeningTask != nil || audioManager.isCapturing else {
            connectionState = .disconnected
            return
        }

        connectionState = .stopping
        audioManager.stopCapture()
        commitPartialTranscriptBeforeStop()
        isGracefulStopPending = true

        do {
            if isManualActivityActive {
                isManualActivityActive = false
                try await webSocket.sendActivityEnd()
            }
            try await webSocket.sendAudioStreamEnd()
        } catch {
            finishGracefulStopWaiter()
        }

        await waitForGracefulStop()
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
        partialTranscriptText = ""
        partialTranscriptEntry = nil
        committedFingerprints.removeAll()
        resetUtteranceTracking()
    }

    /// Sets lifecycle state for tests that exercise facade orchestration without opening audio devices.
    func setLifecycleStateForTesting(_ state: SpeechRealtimeConnectionState) {
        connectionState = state
    }

    /// Applies a decoded Gemini Live message without opening audio devices, for tests.
    func handleMessageForTesting(_ message: GeminiLiveMessage) async {
        _ = await handle(message, runID: lifecycleRunID, startsCapture: false)
    }

    /// Applies a decoded Gemini Live message to the service state.
    ///
    /// - Returns: The audio streaming task when this message started microphone capture.
    private func handle(
        _ message: GeminiLiveMessage,
        runID: UUID,
        startsCapture: Bool
    ) async -> Task<Void, Never>? {
        switch message {
        case .setupComplete:
            // Gemini can repeat the acknowledgement; running the start branch a
            // second time would orphan the first audio task.
            guard !hasHandledSetupComplete else { return nil }
            hasHandledSetupComplete = true
            setupCompleteRunCount += 1

            connectionState = .connected(sessionID: sessionResumptionHandle ?? "")
            guard startsCapture else {
                // Simulated setup for tests: record the manual activity bracket
                // without opening audio devices or touching the socket.
                connectionState = .listening
                isManualActivityActive = !options.automaticActivityDetection
                return nil
            }

            let audioStream: AsyncStream<Data>
            do {
                audioStream = try audioManager.startCapture()
            } catch {
                if isCurrentLifecycleRun(runID) {
                    lastError = SpeechRealtimeErrorRedaction.redacted(error)
                    connectionState = .error("Failed to start audio capture")
                }
                return nil
            }

            connectionState = .listening

            if !options.automaticActivityDetection {
                do {
                    try await webSocket.sendActivityStart()
                    isManualActivityActive = true
                } catch {
                    audioManager.stopCapture()
                    if isCurrentLifecycleRun(runID) {
                        lastError = SpeechRealtimeErrorRedaction.redacted(error)
                        connectionState = .error("Failed to start manual activity")
                    }
                    return nil
                }
            }

            return Task {
                await sendAudioChunks(audioStream, runID: runID)
            }

        case .sessionResumptionUpdate(let handle, _):
            sessionResumptionHandle = handle

        case .interimTranscription(let text):
            let entry = makeEntry(
                text: text,
                sourceID: utteranceIDForInterim(),
                isFinal: false,
                isUtteranceFinal: false
            )
            partialTranscriptEntry = entry
            partialTranscriptText = entry.text

        case .finalTranscription(let text):
            let entry = makeEntry(
                text: text,
                sourceID: utteranceIDForFinal(),
                isFinal: true,
                isUtteranceFinal: true
            )
            currentUtteranceCloseKind = .finalTranscription
            appendCommittedEntryIfNeeded(entry)
            partialTranscriptText = ""
            partialTranscriptEntry = nil
            finishGracefulStopWaiter()

        case .goAway(let timeLeft):
            let reason = timeLeft.map { "\($0) remaining" } ?? "the connection is closing"
            lastError = GeminiRealtimeError.sessionEnding(reason)
            commitPartialTranscriptBeforeStop()
            stopGracefullyAfterSessionEnd()

        case .error(let message):
            lastError = GeminiRealtimeError.connectionFailed(message)
            connectionState = .error(message)
            finishGracefulStopWaiter()

        case .turnComplete, .usageMetadata, .unknown:
            break
        }

        return nil
    }

    private func stopGracefullyAfterSessionEnd() {
        guard connectionState.isLifecycleActive, connectionState != .stopping else { return }
        Task { [weak self] in
            await self?.stopListening()
        }
    }

    private func commitPartialTranscriptBeforeStop() {
        guard let partialEntry = partialTranscriptEntry else { return }

        let entry = SpeechTranscriptEntry(
            provider: partialEntry.provider,
            sourceID: partialEntry.sourceID,
            text: partialEntry.text,
            timestamp: partialEntry.timestamp,
            start: partialEntry.start,
            duration: partialEntry.duration,
            isFinal: true,
            isUtteranceFinal: true,
            channelIndex: partialEntry.channelIndex,
            speaker: partialEntry.speaker,
            words: partialEntry.words
        )

        currentUtteranceCloseKind = .partialCommit
        appendCommittedEntryIfNeeded(entry)
        partialTranscriptText = ""
        partialTranscriptEntry = nil
    }

    private func appendCommittedEntryIfNeeded(_ entry: SpeechTranscriptEntry) {
        guard !entry.text.isEmpty else { return }

        let sourceID = entry.sourceID ?? ""
        let start = entry.start.map { String($0) } ?? ""
        let duration = entry.duration.map { String($0) } ?? ""
        let channelIndex = entry.channelIndex.map { String($0) } ?? ""
        let fingerprint = [sourceID, entry.text, start, duration, channelIndex].joined(separator: "|")

        guard !committedFingerprints.contains(fingerprint) else { return }
        committedFingerprints.insert(fingerprint)
        transcriptEntries.append(entry)
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

    private func makeEntry(
        text: String,
        sourceID: String,
        isFinal: Bool,
        isUtteranceFinal: Bool
    ) -> SpeechTranscriptEntry {
        SpeechTranscriptEntry(
            provider: .gemini,
            sourceID: sourceID,
            text: text,
            isFinal: isFinal,
            isUtteranceFinal: isUtteranceFinal
        )
    }

    /// Returns the utterance id for an interim transcription.
    ///
    /// A new interim after a committed final starts the next utterance.
    private func utteranceIDForInterim() -> String {
        guard let currentUtteranceID, currentUtteranceCloseKind == .open else {
            return beginNextUtterance()
        }
        return currentUtteranceID
    }

    /// Returns the utterance id for a final transcription.
    ///
    /// Gemini Live sends no utterance identifier, so SpeechKit tracks one itself
    /// to keep two identical utterances apart. A final that follows a partial for
    /// the current utterance — including a partial already promoted by
    /// ``commitPartialTranscriptBeforeStop()`` — reuses that id so the late
    /// duplicate is suppressed.
    private func utteranceIDForFinal() -> String {
        switch currentUtteranceCloseKind {
        case .open, .partialCommit:
            return currentUtteranceID ?? beginNextUtterance()
        case .finalTranscription:
            return beginNextUtterance()
        }
    }

    private func beginNextUtterance() -> String {
        utteranceCount += 1
        let identifier = "utterance-\(utteranceCount)"
        currentUtteranceID = identifier
        currentUtteranceCloseKind = .open
        return identifier
    }

    private func resetUtteranceTracking() {
        utteranceCount = 0
        currentUtteranceID = nil
        currentUtteranceCloseKind = .open
    }

    /// Publishes a caught error with any credential-bearing URL stripped out.
    private func reportFailure(_ error: Error) {
        let redacted = SpeechRealtimeErrorRedaction.redacted(error)
        lastError = redacted
        connectionState = .error(redacted.localizedDescription)
    }

    private func sendAudioChunks(_ stream: AsyncStream<Data>, runID: UUID) async {
        for await audioData in stream {
            if Task.isCancelled { break }
            guard isCurrentLifecycleRun(runID) else { break }

            do {
                try await webSocket.sendAudio(audioData)
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    await MainActor.run {
                        lastError = SpeechRealtimeErrorRedaction.redacted(error)
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
