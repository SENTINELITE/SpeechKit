import Foundation
import SwiftUI

/// The microphone under ``FishAudioRealtimeService``.
///
/// ``AudioCaptureManager`` is the production source. Tests replace it so the
/// whole session lifecycle runs without opening an audio device.
protocol FishAudioRealtimeAudioSource: AnyObject, Sendable {
    var isCapturing: Bool { get }
    var currentLevel: Double { get }
    var recordedWAVData: Data? { get }
    var recordingRetention: SpeechRecordingRetention { get set }
    func discardRecording()
    func setTargetSampleRate(_ targetSampleRate: Double)
    func requestPermission() async -> Bool
    func startCapture() throws -> AsyncStream<Data>
    func stopCapture()
}

extension FishAudioRealtimeAudioSource {
    var recordingRetention: SpeechRecordingRetention { get { .retainUntilDiscarded } set {} }
    func discardRecording() {}
}

extension AudioCaptureManager: FishAudioRealtimeAudioSource {}

/// A SwiftUI-observable Fish Audio realtime transcription service.
///
/// Fish Audio transcribes turn by turn. While a turn is open, its latest live
/// draft is the partial entry; each draft replaces the last. When the turn
/// commits, SpeechKit appends one final entry per speaker in it, with word
/// timings when ``FishAudioRealtimeOptions/timestamps`` is on.
///
/// Every non-empty committed turn is kept, including turns Fish Audio judged
/// not to be the user's, such as another voice in the room. Check
/// ``committedTurns`` or ``turn(for:)`` for each turn's
/// ``FishAudioRealtimeTurn/kind`` to filter them. Turns that are empty or hold
/// only sound tags such as `[cough]` are dropped.
///
/// Fish Audio bills a realtime session for every second it is open, including
/// idle time, so stop listening as soon as you are done.
@Observable
@MainActor
public final class FishAudioRealtimeService {
    /// The current realtime connection state.
    public private(set) var connectionState: SpeechRealtimeConnectionState = .disconnected
    /// The latest partial transcript text: the open turn's latest draft, without speaker tags.
    public private(set) var partialTranscriptText: String = ""
    /// The latest partial transcript entry: the open turn's latest draft.
    ///
    /// Its ``SpeechTranscriptEntry/sourceID`` is the turn index, and its
    /// ``SpeechTranscriptEntry/id`` stays the same for every draft of a turn.
    public private(set) var partialTranscriptEntry: SpeechTranscriptEntry?
    /// The committed transcript entries.
    ///
    /// Each entry's ``SpeechTranscriptEntry/sourceID`` is the index of the
    /// turn it came from. A turn with several speakers produces one entry per speaker.
    public private(set) var transcriptEntries: [SpeechTranscriptEntry] = []
    /// The emitted committed turns, in order, with their kind, reason, and language.
    public private(set) var committedTurns: [FishAudioRealtimeTurn] = []
    /// The most recent realtime error, if any.
    public private(set) var lastError: Error?

    /// The credential used for realtime transcription.
    ///
    /// Fish Audio vendor tokens are unsupported. Custom proxies accept ``SpeechCredential/bearer(_:)``.
    var credential: SpeechCredential { didSet { if oldValue != credential { configurationDidChange() } } }
    /// The configured authorization mode, without exposing its value.
    public var credentialKind: SpeechCredential.Kind { credential.kind }
    public var hasCredential: Bool { credential.isConfigured }
    public func setCredential(_ credential: SpeechCredential) {
        configurationDidChange()
        self.credential = credential
    }

    /// An override for the Fish Audio realtime WebSocket endpoint, or `nil` to use the vendor default.
    public var realtimeEndpoint: URL? { didSet { if oldValue != realtimeEndpoint { configurationDidChange() } } }
    /// Options for the Fish Audio realtime transcription session.
    ///
    /// Changes apply to the next session.
    public var options: FishAudioRealtimeOptions {
        didSet {
            audioSource.setTargetSampleRate(Double(options.sampleRate))
        }
    }

    private let audioSource: any FishAudioRealtimeAudioSource
    private let webSocket: FishAudioRealtimeWebSocket
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
    private let gracefulStopTimeout: Duration
    private var gracefulStopTimeoutTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var partialTurnIndex: Int?
    private var turnStartMilliseconds: [Int: Int] = [:]

    /// The committed transcript text joined with spaces.
    public var transcriptText: String {
        transcriptEntries.map(\.text).joined(separator: " ")
    }

    /// The latest normalized microphone input level for the active realtime capture.
    public var realtimeAudioLevel: Double {
        audioSource.currentLevel
    }

    /// Recording retention after a session stops. The default preserves export after stop.
    public var recordingRetention: SpeechRecordingRetention = .retainUntilDiscarded {
        didSet { audioSource.recordingRetention = recordingRetention }
    }

    /// The latest realtime microphone recording as WAV data, if capture has produced audio.
    public var realtimeRecordingData: Data? {
        audioSource.recordedWAVData
    }

    /// Creates a Fish Audio realtime transcription service with a long-lived API key.
    public convenience init(
        apiKey: String = "",
        options: FishAudioRealtimeOptions = FishAudioRealtimeOptions(),
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.init(credential: .apiKey(apiKey), options: options, realtimeEndpoint: realtimeEndpoint, credentialPolicy: credentialPolicy)
    }

    /// Creates a Fish Audio realtime transcription service with any credential.
    public convenience init(
        credential: SpeechCredential,
        options: FishAudioRealtimeOptions = FishAudioRealtimeOptions(),
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.init(
            credential: credential,
            options: options,
            realtimeEndpoint: realtimeEndpoint,
            audioSource: AudioCaptureManager(targetSampleRate: Double(options.sampleRate)),
            webSocket: FishAudioRealtimeWebSocket(),
            credentialPolicy: credentialPolicy
        )
    }

    /// Creates a service with an injected microphone and socket, for tests.
    init(
        credential: SpeechCredential,
        options: FishAudioRealtimeOptions,
        realtimeEndpoint: URL?,
        audioSource: any FishAudioRealtimeAudioSource,
        webSocket: FishAudioRealtimeWebSocket,
        gracefulStopTimeout: Duration = .seconds(5),
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credential = credential
        self.credentialPolicy = credentialPolicy
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
        self.audioSource = audioSource
        self.webSocket = webSocket
        self.gracefulStopTimeout = gracefulStopTimeout
    }

    /// Starts realtime microphone transcription.
    ///
    /// SpeechKit validates ``options`` first, because Fish Audio ends the
    /// session on any invalid setting. It sends `config`, reports
    /// ``SpeechRealtimeConnectionState/connected(sessionID:)`` when Fish Audio
    /// answers with `session_started`, and then starts the microphone.
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
            connectionState = .error("Fish Audio is not configured")
            lastError = FishAudioRealtimeError.apiKeyMissing
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

        // Claim the lifecycle before the first suspension, so a stop during the
        // credential fetch or the permission prompt cancels this start.
        connectionState = .connecting
        lastError = nil
        resetTurnState()

        let resolvedCredential: SpeechResolvedCredential
        do {
            try credential.validate(provider: .fishAudio, capability: .realtime, endpoint: realtimeEndpoint ?? FishAudioRealtimeWebSocket.defaultURL, policy: credentialPolicy)
            try options.validate()
            let task = Task { try await credential.resolved(for: .fishAudio, capability: .realtime, model: FishAudioRealtimeWebSocket.modelID, endpoint: realtimeEndpoint ?? FishAudioRealtimeWebSocket.defaultURL, policy: credentialPolicy) }
            authorizationTask = task
            resolvedCredential = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard isCurrentLifecycleRun(runID), !Task.isCancelled else { return }
            authorizationTask = nil
        } catch {
            guard isCurrentLifecycleRun(runID), !Task.isCancelled, !(error is CancellationError) else { return }
            if isCurrentLifecycleRun(runID) {
                reportFailure(error)
            }
            return
        }
        guard isCurrentLifecycleRun(runID), !Task.isCancelled else { return }

        let hasPermission = await audioSource.requestPermission()
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
                    reportFailure(error)
                }
                finishGracefulStopWaiter()
            }

            await cleanupAfterStop(runID: runID)
        }
    }

    /// Stops realtime microphone transcription and disconnects from Fish Audio.
    ///
    /// SpeechKit sends the audio already captured, then `audio_done`. Fish
    /// Audio commits the open turn and answers with `session_done`. The whole
    /// shutdown has one 5-second deadline, covering the remaining audio,
    /// `audio_done`, and the wait for `session_done`; when it passes, SpeechKit
    /// closes the connection anyway. Concurrent calls share one shutdown.
    public func stopListening() async {
        defer { if recordingRetention == .discardOnStop { discardRecording() } }
        authorizationTask?.cancel()
        authorizationTask = nil
        if listeningTask == nil { invalidateLifecycleRun() }

        if let stopTask {
            await stopTask.value
            return
        }

        guard connectionState.isLifecycleActive || listeningTask != nil || audioSource.isCapturing else {
            connectionState = .disconnected
            return
        }

        let task = Task { @MainActor in
            await performStop()
        }
        stopTask = task
        await task.value
        stopTask = nil
    }

    private func performStop() async {
        let hasSession = listeningTask != nil
        connectionState = .stopping
        audioSource.stopCapture()

        if hasSession {
            isGracefulStopPending = true
            // One deadline for the whole shutdown. Closing the socket also fails
            // any send that is stuck, so nothing below can outlive it.
            gracefulStopTimeoutTask = Task { @MainActor [weak self, webSocket, gracefulStopTimeout] in
                guard (try? await Task.sleep(for: gracefulStopTimeout)) != nil else { return }
                self?.finishGracefulStopWaiter()
                await webSocket.disconnect()
            }

            // Let the chunks already captured reach Fish Audio before `audio_done`.
            await audioSendTask?.value
            audioSendTask = nil

            if isGracefulStopPending {
                do {
                    try await webSocket.send(.audioDone)
                } catch {
                    finishGracefulStopWaiter()
                }
            }

            await waitForGracefulStop()
            gracefulStopTimeoutTask?.cancel()
            gracefulStopTimeoutTask = nil
        }

        // A start still fetching its credential or permission sees the new run ID and gives up.
        invalidateLifecycleRun()
        listeningTask?.cancel()
        listeningTask = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        await webSocket.disconnect()
        audioSource.stopCapture()
        clearPartial()
        connectionState = .disconnected
    }

    /// Clears committed and partial realtime transcript text.
    public func clearTranscript() {
        transcriptEntries.removeAll()
        committedTurns.removeAll()
        resetTurnState()
    }

    /// Returns the committed turn a transcript entry came from.
    public func turn(for entry: SpeechTranscriptEntry) -> FishAudioRealtimeTurn? {
        committedTurns.last { $0.entryIDs.contains(entry.id) }
    }

    /// Tells Fish Audio whether your voice agent's reply is playing.
    ///
    /// In ``FishAudioTurnDetectionMode/auto`` mode, a short acknowledgement
    /// such as "mm-hm" while the agent speaks does not take the turn: it
    /// commits as a ``FishAudioRealtimeTurnKind/backchannel`` turn. Send `true`
    /// when the reply starts playing and `false` when it ends or is
    /// interrupted, and only when the value changes.
    ///
    /// - Throws: ``FishAudioRealtimeError/disconnected`` when no session is open.
    public func agentSpeaking(_ speaking: Bool) async throws {
        try await sendSessionMessage(.agentSpeaking(speaking))
    }

    /// Adds conversation context that helps Fish Audio recognize names and follow-ups.
    ///
    /// Committed user turns are added automatically. Send what the other party
    /// said, such as each line your voice agent speaks, as
    /// ``FishAudioContextRole/assistant`` items.
    ///
    /// - Parameters:
    ///   - items: Up to 32 items of up to 2,000 characters each.
    ///   - resetHistory: Whether to drop the items you added before.
    /// - Throws: ``SpeechError`` when the items are over the limits, or
    ///   ``FishAudioRealtimeError/disconnected`` when no session is open.
    public func addContext(_ items: [FishAudioContextItem], resetHistory: Bool = false) async throws {
        try FishAudioValidation.validateContextItems(items, name: "context items")
        try await sendSessionMessage(.contextAdd(items: items, resetHistory: resetHistory))
    }

    /// Commits the open turn now.
    ///
    /// Use this with ``FishAudioTurnDetectionMode/manual`` mode for
    /// push-to-talk. Fish Audio ignores it when no turn is open.
    ///
    /// - Throws: ``FishAudioRealtimeError/disconnected`` when no session is open.
    public func finalizeTurn() async throws {
        try await sendSessionMessage(.finalize)
    }

    /// Sets lifecycle state for tests that exercise facade orchestration without opening audio devices.
    func setLifecycleStateForTesting(_ state: SpeechRealtimeConnectionState) {
        connectionState = state
    }

    /// Feeds a realtime message to the state machine for tests that run without opening audio devices.
    func handleMessageForTesting(_ message: FishAudioRealtimeServerMessage) {
        _ = handleMessage(message, runID: lifecycleRunID, startsCapture: false)
    }

    private func sendSessionMessage(_ message: FishAudioRealtimeClientMessage) async throws {
        guard connectionState.isActive else {
            throw FishAudioRealtimeError.disconnected
        }
        try await webSocket.send(message)
    }

    /// Applies one server message to the session state machine.
    ///
    /// Returns the audio send task when the message started microphone capture.
    private func handleMessage(
        _ message: FishAudioRealtimeServerMessage,
        runID: UUID,
        startsCapture: Bool
    ) -> Task<Void, Never>? {
        switch message {
        case .sessionStarted(let sessionID, let requestID):
            guard connectionState == .connecting else { return nil }
            connectionState = .connected(sessionID: sessionID ?? requestID ?? "")
            guard startsCapture else { return nil }
            do {
                let audioStream = try audioSource.startCapture()
                connectionState = .listening
                let chunkByteCount = options.chunkByteCount
                return Task {
                    await sendAudioChunks(audioStream, chunkByteCount: chunkByteCount, runID: runID)
                }
            } catch {
                if isCurrentLifecycleRun(runID) {
                    abortSession(error: SpeechRealtimeErrorRedaction.redacted(error), state: .error("Failed to start audio capture"))
                }
                return nil
            }

        case .speechStart(let turnIndex, let audioMilliseconds):
            turnStartMilliseconds[turnIndex] = audioMilliseconds

        case .draft(let draft):
            applyDraft(draft)

        case .committed(let commit):
            applyCommit(commit)

        case .error(let serverError):
            if serverError.errorType == "server_restarting" {
                // Recoverable in Fish Audio's terms, but the session closes: a new one is needed.
                lastError = FishAudioRealtimeError.serverRestarting
                if connectionState != .stopping {
                    connectionState = .error(FishAudioRealtimeError.serverRestarting.localizedDescription)
                }
            } else {
                let error = FishAudioRealtimeError.serverError(
                    code: serverError.code
                )
                lastError = SpeechErrorBoundary.safe(error)
                // During a stop, keep draining: Fish Audio can still commit the
                // open turn (as with `max_duration_exceeded`) before it closes.
                if !serverError.recoverable, connectionState != .stopping {
                    connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
                }
            }

        case .sessionDone:
            finishGracefulStopWaiter()

        case .userTurnTaken, .eagerEndOfTurn, .turnResumed, .userBackchannel,
             .vad, .eotProbability, .progress, .configured, .unknown:
            break
        }

        return nil
    }

    private func applyDraft(_ draft: FishAudioRealtimeDraft) {
        let parts = FishAudioRealtimeMapping.speakerParts(in: draft.text)
        let text = parts.map(\.text).joined(separator: " ")
        guard !text.isEmpty else {
            if partialTurnIndex == draft.turnIndex {
                clearPartial()
            }
            return
        }

        // Keep the entry identity for every draft of a turn, so a list shows one row that updates.
        let id = partialTurnIndex == draft.turnIndex ? (partialTranscriptEntry?.id ?? UUID()) : UUID()
        partialTurnIndex = draft.turnIndex
        partialTranscriptText = text
        partialTranscriptEntry = SpeechTranscriptEntry(
            id: id,
            provider: .fishAudio,
            sourceID: String(draft.turnIndex),
            text: text,
            start: turnStartMilliseconds[draft.turnIndex].map { Double($0) / 1000 },
            isFinal: false,
            isUtteranceFinal: false,
            speaker: parts.first?.speaker
        )
    }

    private func applyCommit(_ commit: FishAudioRealtimeCommit) {
        if partialTurnIndex == commit.turnIndex {
            clearPartial()
        }
        let startMilliseconds = commit.audioStartMilliseconds ?? turnStartMilliseconds[commit.turnIndex]
        turnStartMilliseconds[commit.turnIndex] = nil

        let entries = FishAudioRealtimeMapping.entries(for: commit, fallbackStartMilliseconds: startMilliseconds)
        guard !entries.isEmpty else { return }

        transcriptEntries.append(contentsOf: entries)
        committedTurns.append(FishAudioRealtimeTurn(
            turnIndex: commit.turnIndex,
            kind: commit.turnKind,
            text: commit.text,
            reason: commit.reason,
            isDegraded: commit.degraded,
            language: commit.language,
            languageCode: commit.languageCode,
            start: startMilliseconds.map { Double($0) / 1000 },
            end: commit.audioEndMilliseconds.map { Double($0) / 1000 },
            entryIDs: entries.map(\.id)
        ))
    }

    private func clearPartial() {
        partialTurnIndex = nil
        partialTranscriptText = ""
        partialTranscriptEntry = nil
    }

    /// Waits until `session_done`, the end of the stream, or the shutdown deadline.
    private func waitForGracefulStop() async {
        guard isGracefulStopPending else { return }

        // Stay on the main actor for the whole wait, as MistralRealtimeService does.
        await withCheckedContinuation { continuation in
            gracefulStopWaiter = continuation
        }
    }

    private func finishGracefulStopWaiter() {
        isGracefulStopPending = false
        gracefulStopWaiter?.resume()
        gracefulStopWaiter = nil
    }

    /// Sends captured audio in 100 ms messages, as Fish Audio recommends, and flushes the remainder when capture ends.
    private func sendAudioChunks(_ stream: AsyncStream<Data>, chunkByteCount: Int, runID: UUID) async {
        var buffer = Data()

        func send(_ chunk: Data) async -> Bool {
            do {
                try await webSocket.send(.audio(chunk))
                return true
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    lastError = SpeechRealtimeErrorRedaction.redacted(error)
                }
                return false
            }
        }

        for await audioData in stream {
            if Task.isCancelled { return }
            guard isCurrentLifecycleRun(runID) else { return }

            buffer.append(audioData)
            while buffer.count >= chunkByteCount {
                let chunk = Data(buffer.prefix(chunkByteCount))
                buffer = Data(buffer.dropFirst(chunkByteCount))
                guard await send(chunk) else { return }
            }
        }

        if !buffer.isEmpty, !Task.isCancelled, isCurrentLifecycleRun(runID) {
            _ = await send(buffer)
        }
    }

    /// Ends the session at once, keeping the error: an open socket keeps billing.
    private func abortSession(error: Error, state: SpeechRealtimeConnectionState) {
        lastError = SpeechErrorBoundary.safe(error)
        connectionState = state
        invalidateLifecycleRun()
        listeningTask?.cancel()
        listeningTask = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        audioSource.stopCapture()
        clearPartial()
        finishGracefulStopWaiter()
        Task { [webSocket] in
            await webSocket.disconnect()
        }
    }

    /// Publishes a caught error with any credential-bearing URL stripped out.
    private func reportFailure(_ error: Error) {
        let redacted = SpeechRealtimeErrorRedaction.redacted(error)
        lastError = redacted
        connectionState = .error(redacted.localizedDescription)
    }

    private func cleanupAfterStop(runID: UUID) async {
        guard isCurrentLifecycleRun(runID) else { return }
        audioSource.stopCapture()
        audioSendTask?.cancel()
        audioSendTask = nil
        await webSocket.disconnect()
        clearPartial()
        if connectionState.isLifecycleActive {
            connectionState = .disconnected
        }
    }

    private func resetTurnState() {
        clearPartial()
        turnStartMilliseconds.removeAll()
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
        audioSource.stopCapture()
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

    public func discardRecording() { audioSource.discardRecording() }

}

// MARK: - Mapping

/// Maps Fish Audio realtime turns onto ``SpeechTranscriptEntry`` values.
enum FishAudioRealtimeMapping {
    /// A run of turn text attributed to one speaker.
    struct SpeakerPart: Equatable {
        /// The speaker label, such as `"speaker:0"`, or `nil` for text before the first tag or with diarization off.
        let speaker: String?
        /// The text, trimmed, with whitespace collapsed. Sound tags are kept.
        let text: String
    }

    private static let speakerTagPattern = #"<\|speaker:([^|>]*)\|>"#
    private static let soundTagPattern = #"\[[^\[\]]*\]"#

    /// Splits turn text on `<|speaker:N|>` tags, dropping empty parts.
    static func speakerParts(in text: String) -> [SpeakerPart] {
        guard let regex = try? NSRegularExpression(pattern: speakerTagPattern) else {
            return [SpeakerPart(speaker: nil, text: normalizedWhitespace(text))].filter { !$0.text.isEmpty }
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var parts: [SpeakerPart] = []
        var cursor = 0
        var speaker: String?

        func appendPart(upTo location: Int) {
            let segment = normalizedWhitespace(nsText.substring(with: NSRange(location: cursor, length: location - cursor)))
            if !segment.isEmpty {
                parts.append(SpeakerPart(speaker: speaker, text: segment))
            }
        }

        for match in matches {
            appendPart(upTo: match.range.location)
            speaker = "speaker:" + nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            cursor = match.range.location + match.range.length
        }
        appendPart(upTo: nsText.length)
        return parts
    }

    /// A Boolean value that indicates whether text holds anything besides speaker tags, sound tags, and whitespace.
    static func hasWords(_ text: String) -> Bool {
        let stripped = text
            .replacingOccurrences(of: speakerTagPattern, with: " ", options: .regularExpression)
            .replacingOccurrences(of: soundTagPattern, with: " ", options: .regularExpression)
        return !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Builds the final entries for a committed turn: none for an empty or tag-only turn, otherwise one per speaker part.
    ///
    /// A single part spans the whole turn. When a turn is split, words are
    /// handed to each part in order by its word count, and each part's
    /// timing comes from its words, falling back to the turn's bounds for the
    /// first and last part.
    static func entries(
        for commit: FishAudioRealtimeCommit,
        fallbackStartMilliseconds: Int? = nil
    ) -> [SpeechTranscriptEntry] {
        guard hasWords(commit.text) else { return [] }
        let parts = speakerParts(in: commit.text)
        guard !parts.isEmpty else { return [] }

        let turnStart = (commit.audioStartMilliseconds ?? fallbackStartMilliseconds).map { Double($0) / 1000 }
        let turnEnd = commit.audioEndMilliseconds.map { Double($0) / 1000 }
        // A degraded commit carries its last draft's text and no usable timing.
        let words = commit.degraded ? [] : (commit.words ?? [])
        let wordGroups = distribute(words, across: parts)

        return parts.enumerated().map { index, part in
            let partWords = transcriptWords(wordGroups[index], text: part.text, speaker: part.speaker)
            let isFirst = index == 0
            let isLast = index == parts.count - 1
            let start = parts.count == 1 ? turnStart : (partWords.first?.start ?? (isFirst ? turnStart : nil))
            let end = parts.count == 1 ? turnEnd : (partWords.last?.end ?? (isLast ? turnEnd : nil))
            let duration: Double? = {
                guard let start, let end, end >= start else { return nil }
                return end - start
            }()

            return SpeechTranscriptEntry(
                provider: .fishAudio,
                sourceID: String(commit.turnIndex),
                text: part.text,
                start: start,
                duration: duration,
                isFinal: true,
                isUtteranceFinal: true,
                speaker: part.speaker,
                words: partWords
            )
        }
    }

    /// How far past the last aligned character SpeechKit looks for the next word, in characters.
    static let alignmentWindow = 24

    /// Hands timed words to the speaker parts they belong to.
    ///
    /// The parts' spoken text, lowercased with punctuation, whitespace, and
    /// sound tags removed, is joined into one character sequence, and each
    /// word is found in it by its characters, a little ahead of the previous
    /// match. This works when one text token holds several timed words, as
    /// with Chinese and Japanese. A word found inside a part goes to that
    /// part. A word that cannot be found, for example because Fish Audio
    /// normalised it, goes to the part of its neighbours only when the
    /// aligned words on both sides belong to the same part; otherwise it is
    /// left out rather than given to the wrong speaker.
    static func distribute(_ words: [FishAudioRealtimeWord], across parts: [SpeakerPart]) -> [[FishAudioRealtimeWord]] {
        guard parts.count > 1 else { return [words] }

        var characters: [Character] = []
        var partEnds: [Int] = []
        for part in parts {
            let key = FishAudioTranscriptMapping.punctuatedTokens(from: part.text).map(\.key).joined()
            characters.append(contentsOf: key)
            partEnds.append(characters.count)
        }
        func part(containing range: Range<Int>) -> Int? {
            guard let index = partEnds.firstIndex(where: { range.lowerBound < $0 }) else { return nil }
            return range.upperBound <= partEnds[index] ? index : nil
        }

        var assignments: [Int?] = []
        var cursor = 0
        for word in words {
            let key = Array(FishAudioTranscriptMapping.isCueTag(word.text) ? "" : FishAudioTranscriptMapping.matchKey(word.text))
            var assigned: Int?
            if !key.isEmpty, cursor + key.count <= characters.count {
                let lastStart = min(cursor + alignmentWindow, characters.count - key.count)
                if let start = (cursor...lastStart).first(where: { characters[$0..<($0 + key.count)].elementsEqual(key) }) {
                    let range = start..<(start + key.count)
                    assigned = part(containing: range)
                    cursor = range.upperBound
                }
            }
            assignments.append(assigned)
        }

        // Settle unaligned words by their aligned neighbours.
        for index in assignments.indices where assignments[index] == nil {
            let previous = assignments[..<index].last(where: { $0 != nil }) ?? 0
            let next = assignments[(index + 1)...].first(where: { $0 != nil }) ?? (parts.count - 1)
            if previous == next {
                assignments[index] = previous
            }
        }

        var groups = Array(repeating: [FishAudioRealtimeWord](), count: parts.count)
        for (word, assignment) in zip(words, assignments) {
            if let assignment {
                groups[assignment].append(word)
            }
        }
        return groups
    }

    /// Converts words from milliseconds to seconds and copies punctuation from the part text where tokens match.
    private static func transcriptWords(_ words: [FishAudioRealtimeWord], text: String, speaker: String?) -> [SpeechTranscriptWord] {
        let segments = words.map { word in
            FishAudioTranscriptionSegment(
                text: word.text,
                start: word.startMilliseconds.map { Double($0) / 1000 },
                end: word.endMilliseconds.map { Double($0) / 1000 }
            )
        }
        return FishAudioTranscriptMapping.words(segments: segments, speakerTurns: [], fallbackText: text).map { word in
            SpeechTranscriptWord(text: word.text, start: word.start, end: word.end, speaker: speaker)
        }
    }

    private static func normalizedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

}
