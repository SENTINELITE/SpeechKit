import AVFoundation
import Foundation
import OSLog
import SwiftUI

/// A SwiftUI-observable ElevenLabs realtime transcription service.
///
/// Scribe v3 Live commits a segment when its turn probability reaches the
/// model's threshold; each commit arrives as a `committed_transcript` and, in
/// a diarized session, is followed by a `diarized_transcript` that SpeechKit
/// resolves into one entry per run of the same speaker. Later
/// `speakers_merged` messages rewrite earlier speaker labels in place, so an
/// entry's ``SpeechTranscriptEntry/speaker`` can change after it was
/// emitted; entries keep their ``SpeechTranscriptEntry/id`` across relabels.
@Observable
@MainActor
public final class ElevenLabsService {

    // MARK: - Public State

    /// The current realtime connection state.
    public private(set) var connectionState: SpeechRealtimeConnectionState = .disconnected
    /// The latest partial transcript text.
    public private(set) var partialTranscriptText: String = ""
    /// The latest partial transcript entry, with draft speaker labels when diarization is on.
    public private(set) var partialTranscriptEntry: SpeechTranscriptEntry?
    /// The committed transcript entries.
    ///
    /// A diarized segment becomes one entry per consecutive run of the same
    /// speaker. Entries share the ``SpeechTranscriptEntry/sourceID``
    /// `segment:N` of the segment they came from.
    public private(set) var transcriptEntries: [SpeechTranscriptEntry] = []
    /// The entities ElevenLabs detected, in the order they arrived.
    public private(set) var entityDetections: [ElevenLabsEntity] = []
    /// The model's confidence that the open turn has ended, from 0 to 1.
    ///
    /// Scribe v3 Live reports it on every partial transcript, whatever the
    /// commit strategy. It resets to `nil` on each commit.
    public private(set) var turnProbability: Double?
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
    /// Options for the ElevenLabs realtime transcription session.
    ///
    /// Changes apply to the next session.
    public var options: ElevenLabsRealtimeOptions

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
    private var segmentEntryIDs: [Int: UUID] = [:]
    private var speakerAliases: [String: String] = [:]
    private var partialEntryID = UUID()
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
        realtimeModelID: ElevenLabsModelID = .scribeV3Live,
        options: ElevenLabsRealtimeOptions = ElevenLabsRealtimeOptions(),
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credential = .apiKey(apiKey)
        self.credentialPolicy = credentialPolicy
        self.realtimeModelID = realtimeModelID
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
    }

    /// Creates an ElevenLabs realtime transcription service with any credential.
    public init(
        credential: SpeechCredential,
        realtimeModelID: ElevenLabsModelID = .scribeV3Live,
        options: ElevenLabsRealtimeOptions = ElevenLabsRealtimeOptions(),
        realtimeEndpoint: URL? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) {
        self.credential = credential
        self.credentialPolicy = credentialPolicy
        self.realtimeModelID = realtimeModelID
        self.options = options
        self.realtimeEndpoint = realtimeEndpoint
    }

    // MARK: - Public Methods

    /// Starts realtime microphone transcription.
    ///
    /// SpeechKit validates ``options`` against ``realtimeModelID`` first,
    /// because ElevenLabs closes the connection on an unsupported combination.
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
        let options = options
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

        do {
            try options.validate(modelID: realtimeModelID)
        } catch {
            guard isCurrentLifecycleRun(runID), !Task.isCancelled, !(error is CancellationError) else { return }
            connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            lastError = SpeechErrorBoundary.safe(error)
            return
        }

        resetSessionState()

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
                    options: options,
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

    /// Commits the open transcript segment now.
    ///
    /// Only meaningful with ``ElevenLabsCommitStrategy/manual``: the other
    /// strategies commit on their own.
    ///
    /// - Throws: ``ElevenLabsError/disconnected`` when no session is open, or
    ///   ``SpeechError/providerFailure(provider:reason:)`` when the session's
    ///   commit strategy is not manual.
    public func commitRealtimeSegment() async throws {
        guard connectionState.isActive else {
            throw ElevenLabsError.disconnected
        }
        guard options.allowsManualCommits(for: realtimeModelID) else {
            throw SpeechError.providerFailure(provider: .elevenLabs, reason: .invalidOptions)
        }
        try await webSocket.send(InputAudioChunk(audioData: Data(), commit: true))
    }

    /// Clears committed and partial realtime transcript text.
    public func clearTranscript() {
        transcriptEntries.removeAll()
        partialTranscriptText = ""
        partialTranscriptEntry = nil
        resetSessionState()
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
            applyPartial(partial)

        case .committedTranscript(let committed):
            applyCommit(text: committed.text, words: nil, segmentIndex: committed.segmentIndex)

        case .committedTranscriptWithTimestamps(let committed):
            applyCommit(text: committed.text, words: committed.words, segmentIndex: committed.segmentIndex)

        case .diarizedTranscript(let diarized):
            applyDiarizedTranscript(diarized)

        case .speakersMerged(let merge):
            applySpeakerMerge(from: merge.fromSpeakerID, to: merge.toSpeakerID)

        case .committedTranscriptEntities(let message):
            entityDetections.append(contentsOf: message.entities)

        case .warning(let notice):
            Self.logger.debug("ElevenLabs realtime warning: \(notice.message ?? "")")

        case .serverError(let serverError):
            // The type is a bounded machine-readable token; the vendor's free
            // text stays in logs and never reaches `lastError`.
            Self.logger.error("ElevenLabs realtime session failed: \(serverError.type)")
            let error = ElevenLabsError.serverError(type: serverError.type)
            lastError = SpeechErrorBoundary.safe(error)
            if connectionState != .stopping {
                connectionState = .error(error.localizedDescription)
            }

        case .unknown:
            Self.logger.debug("Ignoring unknown ElevenLabs realtime message")
        }

        return nil
    }

    // MARK: - Transcript state

    /// Publishes the latest partial, carrying draft speaker labels when diarization is on.
    private func applyPartial(_ partial: PartialTranscript) {
        turnProbability = partial.turnProbability
        partialTranscriptText = partial.text

        let words = (partial.words ?? []).map { word -> SpeechTranscriptWord in
            var transcriptWord = SpeechTranscriptWord(word)
            transcriptWord = relabeledWord(transcriptWord)
            return transcriptWord
        }
        guard !partial.text.isEmpty || !words.isEmpty else {
            partialTranscriptEntry = nil
            return
        }
        partialTranscriptEntry = SpeechTranscriptEntry(
            id: partialEntryID,
            provider: .elevenLabs,
            sourceID: partial.segmentIndex.map { "segment:\($0)" },
            text: partial.text,
            isFinal: false,
            isUtteranceFinal: false,
            words: words
        )
    }

    /// Appends a committed segment at once, so text is never delayed for diarization.
    ///
    /// The entry's `segment:N` source ID lets the matching
    /// `diarized_transcript` replace it with speaker-run entries later.
    private func applyCommit(text: String, words: [ElevenLabsWordTimestamp]?, segmentIndex: Int?) {
        clearPartial()
        turnProbability = nil
        guard !text.isEmpty else { return }

        let sourceID = segmentIndex.map { "segment:\($0)" }
        let transcriptWords = (words ?? []).map { relabeledWord(SpeechTranscriptWord($0)) }
        let entry = SpeechTranscriptEntry(
            provider: .elevenLabs,
            sourceID: sourceID,
            text: text,
            start: transcriptWords.first?.start,
            duration: duration(of: transcriptWords),
            speaker: transcriptWords.first?.speaker,
            words: transcriptWords
        )
        transcriptEntries.append(entry)
        if let segmentIndex {
            segmentEntryIDs[segmentIndex] = entry.id
        }
    }

    /// Replaces a committed segment's placeholder with one entry per run of the same speaker.
    ///
    /// The first run keeps the placeholder entry's `id` so list identity is
    /// stable. A segment whose speakers all stayed `null` becomes a single
    /// entry with words. A `diarized_transcript` for an unknown or
    /// already-resolved segment is dropped.
    private func applyDiarizedTranscript(_ diarized: DiarizedTranscript) {
        guard let entryID = segmentEntryIDs.removeValue(forKey: diarized.segmentIndex),
              let index = transcriptEntries.firstIndex(where: { $0.id == entryID }) else {
            return
        }
        let placeholder = transcriptEntries[index]

        // Split words into consecutive runs of the same speaker, with merges applied.
        var runs: [(speaker: String?, words: [SpeechTranscriptWord])] = []
        for word in diarized.words {
            let speaker = word.speakerID.map(resolveSpeaker)
            let transcriptWord = SpeechTranscriptWord(
                text: word.text,
                start: word.start,
                end: word.end,
                speaker: speaker,
                confidence: word.logprob
            )
            // A spacing token with no speaker belongs to the run it sits in,
            // so it never splits one speaker's words into separate entries.
            let joinsCurrentRun = speaker == nil && word.type == "spacing"
            if let last = runs.last, last.speaker == speaker || joinsCurrentRun {
                runs[runs.count - 1].words.append(transcriptWord)
            } else {
                runs.append((speaker, [transcriptWord]))
            }
        }
        guard !runs.isEmpty else {
            transcriptEntries[index] = SpeechTranscriptEntry(
                id: placeholder.id,
                provider: .elevenLabs,
                sourceID: placeholder.sourceID,
                text: diarized.text,
                timestamp: placeholder.timestamp
            )
            return
        }

        let entries = runs.enumerated().map { runIndex, run in
            SpeechTranscriptEntry(
                id: runIndex == 0 ? placeholder.id : UUID(),
                provider: .elevenLabs,
                sourceID: placeholder.sourceID,
                text: Self.text(of: run.words, fallback: runs.count == 1 ? diarized.text : nil),
                timestamp: placeholder.timestamp,
                start: run.words.lazy.compactMap(\.start).first ?? (runIndex == 0 ? placeholder.start : nil),
                duration: duration(of: run.words),
                speaker: run.speaker,
                words: run.words
            )
        }
        transcriptEntries.replaceSubrange(index...index, with: entries)
    }

    /// Rewrites every earlier `from` label as `to` in stored and partial words.
    ///
    /// Merges chain and IDs are never reused, so each alias resolves to its
    /// final target and entries are rebuilt with their `id` kept.
    private func applySpeakerMerge(from: String, to: String) {
        speakerAliases[from] = to
        for key in speakerAliases.keys {
            speakerAliases[key] = resolveSpeaker(key)
        }

        transcriptEntries = transcriptEntries.map(relabeledEntry)
        if let partial = partialTranscriptEntry {
            partialTranscriptEntry = relabeledEntry(partial)
        }
    }

    /// Follows a speaker alias chain to its final target.
    private func resolveSpeaker(_ speakerID: String) -> String {
        var current = speakerID
        var seen: Set<String> = [current]
        while let next = speakerAliases[current], !seen.contains(next) {
            seen.insert(next)
            current = next
        }
        return current
    }

    private func relabeledEntry(_ entry: SpeechTranscriptEntry) -> SpeechTranscriptEntry {
        SpeechTranscriptEntry(
            id: entry.id,
            provider: entry.provider,
            sourceID: entry.sourceID,
            text: entry.text,
            timestamp: entry.timestamp,
            start: entry.start,
            duration: entry.duration,
            isFinal: entry.isFinal,
            isUtteranceFinal: entry.isUtteranceFinal,
            channelIndex: entry.channelIndex,
            speaker: entry.speaker.map(resolveSpeaker),
            words: entry.words.map(relabeledWord)
        )
    }

    private func relabeledWord(_ word: SpeechTranscriptWord) -> SpeechTranscriptWord {
        SpeechTranscriptWord(
            id: word.id,
            text: word.text,
            start: word.start,
            end: word.end,
            speaker: word.speaker.map(resolveSpeaker),
            confidence: word.confidence
        )
    }

    /// Joins a run's words back into text, keeping `spacing` tokens.
    private static func text(of words: [SpeechTranscriptWord], fallback: String?) -> String {
        let joined = words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? (fallback ?? joined) : joined
    }

    private func duration(of words: [SpeechTranscriptWord]) -> Double? {
        guard let start = words.lazy.compactMap(\.start).first,
              let end = words.reversed().lazy.compactMap(\.end).first,
              end >= start else { return nil }
        return end - start
    }

    private func clearPartial() {
        partialEntryID = UUID()
        partialTranscriptText = ""
        partialTranscriptEntry = nil
    }

    /// Resets the diarization and turn state on start and on clear.
    private func resetSessionState() {
        clearPartial()
        segmentEntryIDs.removeAll()
        speakerAliases.removeAll()
        entityDetections.removeAll()
        turnProbability = nil
    }

    // MARK: - Private Methods

    /// The audio chunk for one frame of microphone data.
    ///
    /// `previous_text` and `keyterm_library` are allowed in the first chunk of a session only.
    func makeInputAudioChunk(audioData: Data, isFirstChunk: Bool) -> InputAudioChunk {
        InputAudioChunk(
            audioData: audioData,
            previousText: isFirstChunk ? options.previousText : nil,
            keytermLibrary: isFirstChunk && !options.keytermLibrary.isEmpty ? options.keytermLibrary : nil
        )
    }

    private func sendAudioChunks(_ stream: AsyncStream<Data>, runID: UUID) async {
        var isFirstChunk = true
        for await audioData in stream {
            if Task.isCancelled { break }
            guard isCurrentLifecycleRun(runID) else { break }

            let chunk = makeInputAudioChunk(audioData: audioData, isFirstChunk: isFirstChunk)
            isFirstChunk = false
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
