import Foundation
import SwiftUI

/// A SwiftUI-observable Meta realtime transcription service.
@Observable
@MainActor
public final class MetaRealtimeService {
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
    /// The Meta API key used for realtime transcription.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// An override for the Meta realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL?
    /// Options for the Meta realtime transcription session.
    public var options: MetaRealtimeOptions {
        didSet {
            audioManager.setTargetSampleRate(Double(options.sampleRate))
        }
    }

    private let audioManager: AudioCaptureManager
    private let webSocket = MetaRealtimeWebSocket()
    private var listeningTask: Task<Void, Never>?
    private var committedFingerprints: Set<String> = []
    private var lifecycleRunID = UUID()
    private var isGracefulStopPending = false
    private var gracefulStopWaiter: CheckedContinuation<Void, Never>?
    private let gracefulStopTimeoutNanoseconds: UInt64 = 2_000_000_000
    private var gracefulStopTimeoutTask: Task<Void, Never>?
    private var currentTurnID: Int?
    private var currentTurnStartMs: Int?
    private var currentTurnEndMs: Int?
    private var currentSpeaker: String?

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

    /// Creates a Meta realtime transcription service with a long-lived API key.
    public init(
        apiKey: String = "",
        options: MetaRealtimeOptions = MetaRealtimeOptions(),
        realtimeEndpoint: URL? = nil
    ) {
        self.credential = .apiKey(apiKey)
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
        self.audioManager = AudioCaptureManager(targetSampleRate: Double(options.sampleRate))
    }

    /// Creates a Meta realtime transcription service with any credential.
    public init(
        credential: SpeechCredential,
        options: MetaRealtimeOptions = MetaRealtimeOptions(),
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
            connectionState = .error("Meta is not configured")
            lastError = MetaRealtimeError.apiKeyMissing
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

        do {
            try options.validate()
        } catch {
            connectionState = .error(error.localizedDescription)
            lastError = error
            return
        }

        let runID = beginLifecycleRun()
        connectionState = .connecting
        partialTranscriptText = ""
        partialTranscriptEntry = nil
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
                var sendTask: Task<Void, Never>?

                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID) else { break }

                    if let startedSendTask = handleMessage(message, runID: runID, startsCapture: true) {
                        sendTask = startedSendTask
                    }
                }

                sendTask?.cancel()
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

    /// Stops realtime microphone transcription and disconnects from Meta.
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
            try await webSocket.sendEndStream()
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
        resetTurnState()
    }

    /// Sets lifecycle state for tests that exercise facade orchestration without opening audio devices.
    func setLifecycleStateForTesting(_ state: SpeechRealtimeConnectionState) {
        connectionState = state
    }

    /// Feeds a realtime message to the state machine for tests that run without opening audio devices.
    func handleMessageForTesting(_ message: MetaRealtimeMessage) {
        _ = handleMessage(message, runID: lifecycleRunID, startsCapture: false)
    }

    /// Applies one server message to the session state machine.
    ///
    /// Returns the audio send task when the message started microphone capture.
    private func handleMessage(
        _ message: MetaRealtimeMessage,
        runID: UUID,
        startsCapture: Bool
    ) -> Task<Void, Never>? {
        switch message {
        case .sessionCreated(let sessionID):
            // Ignore a duplicate acknowledgement: re-running this branch would
            // start a second capture and orphan the running audio send task.
            guard connectionState == .connecting else { return nil }
            connectionState = .connected(sessionID: sessionID ?? "")
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

        case .speechStart(let turnID, let audioProcessedMs):
            currentTurnID = turnID
            currentTurnStartMs = audioProcessedMs
            currentTurnEndMs = nil
            partialTranscriptText = ""
            partialTranscriptEntry = nil

        case .speaker(let label, _):
            currentSpeaker = label

        case .transcript(let transcript):
            handleTranscript(transcript)

        case .speechEnd(let turnID, let audioProcessedMs):
            if let turnID {
                currentTurnID = turnID
            }
            currentTurnEndMs = audioProcessedMs

        case .speechComplete(let turnID, let transcript, let audioProcessedMs):
            commitTurn(turnID: turnID, text: transcript, audioProcessedMs: audioProcessedMs)

        case .audioProgress:
            break

        case .error(let message):
            lastError = MetaRealtimeError.connectionFailed(message)
            connectionState = .error(message)
            finishGracefulStopWaiter()

        case .unknown:
            break
        }

        return nil
    }

    private func handleTranscript(_ transcript: MetaTranscript) {
        if let turnID = transcript.turnID {
            currentTurnID = turnID
        }

        let text = partialText(appending: transcript.transcript)
        guard !text.isEmpty else { return }

        let entry = SpeechTranscriptEntry(
            provider: .meta,
            sourceID: currentTurnID.map(String.init),
            text: text,
            isFinal: transcript.final == true,
            isUtteranceFinal: false,
            speaker: currentSpeaker
        )

        partialTranscriptEntry = entry
        partialTranscriptText = entry.text
    }

    /// Resolves the partial text for a transcript event, honoring the configured partial mode.
    ///
    /// Cumulative partials replace the running text, delta partials extend it.
    private func partialText(appending text: String) -> String {
        guard options.partialMode == .delta else { return text }

        let existing = partialTranscriptText
        guard !existing.isEmpty else { return text }
        guard !text.isEmpty else { return existing }

        let needsSeparator = existing.last?.isWhitespace == false && text.first?.isWhitespace == false
        return needsSeparator ? existing + " " + text : existing + text
    }

    private func commitTurn(turnID: Int?, text: String, audioProcessedMs: Int?) {
        let resolvedTurnID = turnID ?? currentTurnID
        let startMs = currentTurnStartMs
        let endMs = currentTurnEndMs ?? audioProcessedMs
        let duration: Double? = {
            guard let startMs, let endMs, endMs >= startMs else { return nil }
            return Double(endMs - startMs) / 1000
        }()

        let entry = SpeechTranscriptEntry(
            provider: .meta,
            sourceID: resolvedTurnID.map(String.init),
            text: text,
            start: startMs.map { Double($0) / 1000 },
            duration: duration,
            isFinal: true,
            isUtteranceFinal: true,
            speaker: currentSpeaker
        )

        appendCommittedEntryIfNeeded(entry)
        partialTranscriptText = ""
        partialTranscriptEntry = nil
        currentTurnID = nil
        currentTurnStartMs = nil
        currentTurnEndMs = nil
        finishGracefulStopWaiter()
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

        appendCommittedEntryIfNeeded(entry)
        partialTranscriptText = ""
        partialTranscriptEntry = nil
    }

    private func appendCommittedEntryIfNeeded(_ entry: SpeechTranscriptEntry) {
        guard !entry.text.isEmpty else { return }

        let fingerprint = [entry.sourceID ?? "", entry.text].joined(separator: "|")
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

    private func sendAudioChunks(_ stream: AsyncStream<Data>, runID: UUID) async {
        for await audioData in stream {
            if Task.isCancelled { break }
            guard isCurrentLifecycleRun(runID) else { break }

            do {
                try await webSocket.sendAudio(audioData)
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

    private func resetTurnState() {
        currentTurnID = nil
        currentTurnStartMs = nil
        currentTurnEndMs = nil
        currentSpeaker = nil
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
