import Foundation
import OSLog
import SwiftUI

/// Fans one provider event out to every current subscriber.
///
/// The GPT-Live delegation surfaces are exposed as properties that hand back a
/// fresh `AsyncStream` on every read, so two parts of an app can observe the
/// same session. Each stream receives the events that arrive after it is
/// created; nothing is replayed.
@MainActor
final class OpenAILiveEventMulticast<Element: Sendable> {
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    /// Returns a new stream that receives every event from this point on.
    func stream() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    /// Delivers an event to every subscriber.
    func yield(_ element: Element) {
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    /// Finishes every subscriber stream and drops them.
    func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}

/// A SwiftUI-observable OpenAI GPT-Live speech-to-speech conversation service.
///
/// The service owns one GPT-Live WebSocket session and one full-duplex audio
/// engine. Microphone audio streams to OpenAI continuously — GPT-Live manages
/// turn taking itself, so there is no commit and no client voice-activity
/// detection — and assistant audio is queued for playback as it arrives.
/// Transcript fragments from both speakers are grouped into
/// ``SpeechConversationTranscriptEntry`` values that stay open while more
/// fragments can still land in them.
@Observable
@MainActor
public final class OpenAILiveService {
    // MARK: - Published state

    /// The conversation lifecycle state.
    public private(set) var state: SpeechConversationState = .idle

    /// Diagnostics for on-device debugging; filter Console on subsystem `SpeechKit`.
    @ObservationIgnored private static let logger = Logger(subsystem: "SpeechKit", category: "OpenAILive")
    @ObservationIgnored private var sentAudioChunkCount = 0
    @ObservationIgnored private var receivedAudioDeltaCount = 0
    /// The grouped conversation transcript, oldest entry first.
    public private(set) var transcript: [SpeechConversationTranscriptEntry] = []
    /// The in-progress text of the newest open user entry.
    ///
    /// This is a view onto the open entry already present in ``transcript``, not
    /// additional text. Render one or the other.
    public private(set) var partialUserTranscriptText: String = ""
    /// The in-progress text of the newest open assistant entry.
    ///
    /// This is a view onto the open entry already present in ``transcript``, not
    /// additional text. Render one or the other.
    public private(set) var partialAssistantTranscriptText: String = ""
    /// The resolved session configuration reported by OpenAI, once the session starts.
    public private(set) var sessionInfo: OpenAILiveSessionInfo?
    /// The moment the session expires, which GPT-Live reports two hours after it starts.
    public private(set) var expiresAt: Date?
    /// The latest cumulative billed seconds reported by OpenAI.
    ///
    /// GPT-Live sends a snapshot rather than an increment, so this value is
    /// replaced and never summed.
    public private(set) var usageSeconds: Double = 0
    /// How much of the model's context window the session has used, from `0` to `1`.
    ///
    /// GPT-Live omits the field until the session has carried audio, and the
    /// last reported ratio is kept when a later snapshot omits it.
    public private(set) var contextWindowUsageRatio: Double?
    /// A Boolean value that indicates whether OpenAI has stopped listening to the microphone.
    ///
    /// This reflects the provider acknowledgement rather than the local request,
    /// so the UI never shows a mute the provider did not apply.
    public private(set) var isInputMuted: Bool = false
    /// The `event_id` values of context appends the provider has not answered yet.
    ///
    /// GPT-Live only acknowledges pushed context once the session timeline
    /// advances, so an append can stay pending for as long as the session is
    /// silent. A UI can use this to show an "injecting" indicator.
    public private(set) var pendingContextAppendIDs: Set<String> = []
    /// The most recent conversation error, if any.
    public private(set) var lastError: Error?

    // MARK: - Configuration

    /// The credential used for GPT-Live sessions.
    public var credential: SpeechCredential
    /// The OpenAI API key used for GPT-Live sessions.
    ///
    /// Reading this property returns the key for a ``SpeechCredential/apiKey(_:)``
    /// credential and an empty string for a ``SpeechCredential/token(_:)``
    /// credential. Writing it replaces ``credential`` with
    /// ``SpeechCredential/apiKey(_:)``.
    public var apiKey: String {
        get { credential.staticAPIKey }
        set { credential = .apiKey(newValue) }
    }
    /// An override for the GPT-Live WebSocket endpoint, or `nil` to use the vendor default.
    ///
    /// OpenAI publishes no ephemeral client secret for GPT-Live, so pointing
    /// this at your own proxy is the only way to keep the API key off the device.
    public var liveEndpoint: URL?
    /// Options for the GPT-Live session.
    public var options: OpenAILiveSessionOptions

    // MARK: - Internals

    @ObservationIgnored private let socket = OpenAILiveWebSocket()
    @ObservationIgnored private let engine = SpeechDuplexAudioEngine()
    @ObservationIgnored private let delegationMulticast = OpenAILiveEventMulticast<OpenAILiveDelegationRequest>()
    @ObservationIgnored private let responseMulticast = OpenAILiveEventMulticast<OpenAILiveResponseEvent>()
    @ObservationIgnored private let contextMulticast = OpenAILiveEventMulticast<OpenAILiveContextEvent>()

    @ObservationIgnored private var assembler = SpeechConversationTranscriptAssembler()
    @ObservationIgnored private var conversationTask: Task<Void, Never>?
    @ObservationIgnored private var audioSendTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSessionUpdates: [String: CheckedContinuation<Void, Error>] = [:]
    @ObservationIgnored private var pendingSessionUpdateTimeouts: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var closeWaiter: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var closeTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleRunID = UUID()

    /// Whether this session may touch the microphone.
    ///
    /// Only a session opened through ``start()`` starts the duplex engine, so
    /// tests that drive ``handleMessageForTesting(_:)`` never open an audio device.
    @ObservationIgnored private var isAudioCaptureEnabled = false

    /// How long ``updateDelegation(_:)`` waits for `session.updated`, in seconds.
    ///
    /// GPT-Live answers a `session.update` in about 50 ms, so this is a
    /// backstop rather than a normal wait.
    private static let sessionUpdateTimeout: TimeInterval = 10

    /// Skips outbound socket writes so tests can drive acknowledgement routing without a live session.
    @ObservationIgnored var isSocketWriteSuppressedForTesting = false

    // MARK: - Derived state

    /// The latest normalized microphone level, between `0` and `1`.
    public var inputLevel: Double {
        engine.inputLevel
    }

    /// The latest normalized assistant playback level, between `0` and `1`.
    public var outputLevel: Double {
        engine.outputLevel
    }

    /// A Boolean value that indicates whether assistant audio is still queued for playback.
    ///
    /// GPT-Live sends no end-of-turn event, so scheduled-but-unplayed audio is
    /// the only signal that the assistant is still talking.
    public var assistantIsSpeaking: Bool {
        engine.isPlaybackPending
    }

    /// The duration of assistant audio that is scheduled but not finished, in seconds.
    public var pendingAssistantAudioSeconds: Double {
        engine.pendingPlaybackSeconds
    }

    /// The captured microphone audio as WAV data, or `nil` when nothing was captured.
    public var recordedWAVData: Data? {
        engine.recordedWAVData
    }

    /// The user side of the transcript, joined with spaces.
    public var userTranscriptText: String {
        joinedTranscriptText(for: .user)
    }

    /// The assistant side of the transcript, joined with spaces.
    public var assistantTranscriptText: String {
        joinedTranscriptText(for: .assistant)
    }

    /// Requests from GPT-Live for the app to answer a turn itself.
    ///
    /// Every read returns a new stream that receives the requests arriving after
    /// it is created. Only a session with ``OpenAILiveDelegation/client``
    /// delegation produces them.
    public var delegationRequests: AsyncStream<OpenAILiveDelegationRequest> {
        delegationMulticast.stream()
    }

    /// Nested Responses events produced by a delegated backend.
    ///
    /// Every read returns a new stream that receives the events arriving after
    /// it is created. Only a session with ``OpenAILiveDelegation/responses(_:)``
    /// delegation produces them.
    public var responseEvents: AsyncStream<OpenAILiveResponseEvent> {
        responseMulticast.stream()
    }

    /// Acknowledgements and rejections for context pushed with the append methods.
    ///
    /// Every read returns a new stream that receives the events arriving after
    /// it is created. Appends are fire-and-forget because GPT-Live withholds
    /// `*.appended` until the session timeline advances, so this stream is how
    /// an app learns that pushed context landed.
    public var contextEvents: AsyncStream<OpenAILiveContextEvent> {
        contextMulticast.stream()
    }

    // MARK: - Initializers

    /// Creates a GPT-Live conversation service with a long-lived API key.
    public init(
        apiKey: String = "",
        options: OpenAILiveSessionOptions = OpenAILiveSessionOptions(),
        liveEndpoint: URL? = nil
    ) {
        self.credential = .apiKey(apiKey)
        self.options = options
        self.liveEndpoint = liveEndpoint
    }

    /// Creates a GPT-Live conversation service with any credential.
    public init(
        credential: SpeechCredential,
        options: OpenAILiveSessionOptions = OpenAILiveSessionOptions(),
        liveEndpoint: URL? = nil
    ) {
        self.credential = credential
        self.options = options
        self.liveEndpoint = liveEndpoint
    }

    // MARK: - Lifecycle

    /// Opens a GPT-Live session and starts the full-duplex audio loop.
    ///
    /// Calling this while a session is connecting, active, or ending does nothing.
    public func start() async {
        guard !state.isLifecycleActive else { return }

        guard credential.isConfigured else {
            state = .error("OpenAI is not configured")
            lastError = OpenAILiveError.apiKeyMissing
            return
        }

        let resolvedCredential: SpeechResolvedCredential
        do {
            resolvedCredential = try await credential.resolved()
        } catch {
            publishFailure(error)
            return
        }

        let runID = beginLifecycleRun()
        state = .connecting
        lastError = nil
        sessionInfo = nil
        expiresAt = nil
        usageSeconds = 0
        contextWindowUsageRatio = nil
        isInputMuted = false
        partialUserTranscriptText = ""
        partialAssistantTranscriptText = ""
        assembler.turnGapMilliseconds = options.turnGapMilliseconds

        let hasPermission = await engine.requestPermission()
        guard isCurrentLifecycleRun(runID) else { return }
        guard hasPermission else {
            state = .error("Microphone permission denied")
            lastError = OpenAILiveError.permissionDenied
            return
        }

        isAudioCaptureEnabled = true
        let options = options
        let liveEndpoint = liveEndpoint

        conversationTask = Task {
            do {
                let messages = try await socket.connect(
                    credential: resolvedCredential,
                    options: options,
                    endpoint: liveEndpoint
                )
                guard isCurrentLifecycleRun(runID) else {
                    await socket.disconnect()
                    return
                }

                for try await message in messages {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID) else { break }
                    handle(message)
                }

                if isCurrentLifecycleRun(runID), state.isLifecycleActive {
                    finishSession(reason: .connectionLost, seconds: usageSeconds)
                }
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    publishFailure(error)
                }
            }

            await teardown(runID: runID)
        }
    }

    /// Closes the GPT-Live session gracefully and stops the audio loop.
    ///
    /// The provider is asked to close and the receive loop keeps running until
    /// `session.closed` arrives or ``OpenAILiveSessionOptions/closeTimeout``
    /// elapses. Calling this without a live session leaves the state untouched.
    public func end() async {
        guard state.isLifecycleActive else { return }

        state = .ending
        do {
            try await socket.requestClose()
        } catch {
            // A socket that is already gone still needs the local teardown below.
        }

        let didClose = await waitForSessionClosed(timeout: options.closeTimeout)
        if !didClose {
            lastError = OpenAILiveError.closeTimedOut
            closeTranscript()
            state = .ended(reason: .unknown, seconds: usageSeconds)
        }

        invalidateLifecycleRun()
        conversationTask?.cancel()
        conversationTask = nil
        audioSendTask?.cancel()
        audioSendTask = nil
        isAudioCaptureEnabled = false
        cancelPendingCommands()
        finishDelegationStreams()
        engine.stop()
        await socket.disconnect()
    }

    // MARK: - Session control

    /// Asks OpenAI to stop listening to the microphone without ending the session.
    ///
    /// ``isInputMuted`` only changes once the provider acknowledges the request.
    ///
    /// - Throws: ``SpeechConversationError/notActive`` when no session is active,
    ///   or the redacted transport error when the request cannot be sent.
    public func muteInput() async throws {
        try await sendSessionControl { try await $0.sendInputAudioMute() }
    }

    /// Asks OpenAI to listen to the microphone again.
    ///
    /// - Throws: ``SpeechConversationError/notActive`` when no session is active,
    ///   or the redacted transport error when the request cannot be sent.
    public func unmuteInput() async throws {
        try await sendSessionControl { try await $0.sendInputAudioUnmute() }
    }

    /// Drops assistant audio that is queued but not yet heard, for a barge-in.
    public func flushAssistantAudio() {
        engine.flushPlayback()
    }

    /// Records a failed command so a non-throwing caller still surfaces it.
    ///
    /// - Parameter error: The error a mute, unmute, or context command threw.
    func recordCommandFailure(_ error: Error) {
        lastError = SpeechRealtimeErrorRedaction.redacted(error)
    }

    /// Clears the grouped transcript and both partial texts.
    public func clearTranscript() {
        assembler.reset()
        transcript = []
        partialUserTranscriptText = ""
        partialAssistantTranscriptText = ""
    }

    // MARK: - Context injection

    /// Pushes trusted app directives into the running session.
    ///
    /// - Parameters:
    ///   - content: The directive text. OpenAI caps it at roughly 500 tokens.
    ///   - delegationID: The delegation the directive belongs to, or `nil` for the whole session.
    /// - Returns: The `event_id` that identifies the append on ``contextEvents``.
    /// - Throws: ``SpeechConversationError/notActive`` when no session is active,
    ///   or the redacted transport error when the event cannot be sent.
    @discardableResult
    public func appendInstructions(_ content: String, delegationID: String? = nil) async throws -> String {
        try await appendContext(kind: .instructions, content: content, delegationID: delegationID)
    }

    /// Pushes quiet factual context into the running session.
    ///
    /// GPT-Live never speaks thinking content aloud.
    ///
    /// - Parameters:
    ///   - content: The context text. OpenAI caps it at roughly 500 tokens.
    ///   - delegationID: The delegation the context belongs to, or `nil` for the whole session.
    /// - Returns: The `event_id` that identifies the append on ``contextEvents``.
    /// - Throws: ``SpeechConversationError/notActive`` when no session is active,
    ///   or the redacted transport error when the event cannot be sent.
    @discardableResult
    public func appendThinking(_ content: String, delegationID: String? = nil) async throws -> String {
        try await appendContext(kind: .thinking, content: content, delegationID: delegationID)
    }

    /// Pushes content the model may paraphrase aloud into the running session.
    ///
    /// - Parameters:
    ///   - content: The commentary text. OpenAI caps it at roughly 500 tokens.
    ///   - delegationID: The delegation the commentary belongs to, or `nil` for the whole session.
    /// - Returns: The `event_id` that identifies the append on ``contextEvents``.
    /// - Throws: ``SpeechConversationError/notActive`` when no session is active,
    ///   or the redacted transport error when the event cannot be sent.
    @discardableResult
    public func appendCommentary(_ content: String, delegationID: String? = nil) async throws -> String {
        try await appendContext(kind: .commentary, content: content, delegationID: delegationID)
    }

    // MARK: - Delegation

    /// Replaces the Responses delegation settings of the running session.
    ///
    /// `delegation.responses` is the only mutable part of a GPT-Live session.
    ///
    /// - Parameter delegation: The new backend model settings.
    /// - Throws: ``SpeechConversationError/notActive`` when no session is active,
    ///   or the redacted transport error when the request cannot be sent.
    public func updateDelegation(_ delegation: OpenAILiveResponsesDelegation) async throws {
        guard state.isActive else { throw SpeechConversationError.notActive }

        let eventID = Self.makeEventID(prefix: "update")
        let message = OpenAILiveSessionUpdateMessage(responses: delegation, eventID: eventID)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // `session.updated` can land before the write returns, so the
            // continuation is registered first.
            pendingSessionUpdates[eventID] = continuation
            pendingSessionUpdateTimeouts[eventID] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.sessionUpdateTimeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.rejectPendingSessionUpdate(
                    eventID: eventID,
                    error: SpeechConversationError.commandRejected(
                        code: "timeout",
                        message: "OpenAI did not acknowledge session.update."
                    )
                )
            }

            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.write { try await $0.send(message) }
                } catch {
                    let redacted = SpeechRealtimeErrorRedaction.redacted(error)
                    self.lastError = redacted
                    self.rejectPendingSessionUpdate(eventID: eventID, error: redacted)
                }
            }
        }
    }

    /// Forwards a raw Responses item to the delegated backend.
    ///
    /// The item passes through untouched, so any Responses shape works without
    /// SpeechKit modelling it.
    ///
    /// - Parameters:
    ///   - item: The Responses item JSON.
    ///   - delegationID: The delegation the item belongs to, or `nil` for the whole session.
    /// - Throws: ``SpeechConversationError/notActive`` when no session is active,
    ///   or the redacted transport error when the request cannot be sent.
    public func createResponseItem(_ item: OpenAIJSONValue, delegationID: String? = nil) async throws {
        let message = OpenAILiveResponseItemCreateMessage(item: item, delegationID: delegationID)
        try await sendSessionControl { try await $0.send(message) }
    }

    /// Asks the delegated backend to answer over the items queued so far.
    ///
    /// GPT-Live takes no parameters here and rejects any it does not expect, so
    /// the request content belongs on ``createResponseItem(_:delegationID:)``.
    ///
    /// - Parameter delegationID: The delegation that should answer, or `nil` for the whole session.
    /// - Throws: ``SpeechConversationError/notActive`` when no session is active,
    ///   or the redacted transport error when the request cannot be sent.
    public func createResponse(delegationID: String? = nil) async throws {
        let message = OpenAILiveResponseCreateMessage(delegationID: delegationID)
        try await sendSessionControl { try await $0.send(message) }
    }

    // MARK: - Test seams

    /// Sets lifecycle state for tests that exercise message handling without opening audio devices.
    func setLifecycleStateForTesting(_ state: SpeechConversationState) {
        self.state = state
    }

    /// Routes a decoded server event through the same handler the receive loop uses.
    func handleMessageForTesting(_ message: OpenAILiveMessage) {
        handle(message)
    }

    // MARK: - Message handling

    private func handle(_ message: OpenAILiveMessage) {
        if case .outputAudioDelta = message {} else {
            Self.logger.info("received \(String(describing: message).prefix(160), privacy: .public)")
        }
        switch message {
        case .sessionStarted(let info):
            // Only the first acknowledgement counts; GPT-Live repeats the
            // session snapshot on later events.
            guard case .connecting = state else { return }
            sessionInfo = info
            expiresAt = info.expiresAt
            Self.logger.info("session.started \(info.id, privacy: .public)")
            startAudioLoop()
            state = .active(sessionID: info.id)

        case .sessionUpdated(let info, let clientEventID):
            sessionInfo = info
            if let expiresAt = info.expiresAt {
                self.expiresAt = expiresAt
            }
            if let clientEventID {
                resolvePendingSessionUpdate(eventID: clientEventID)
            }

        case .outputAudioDelta(let audio):
            receivedAudioDeltaCount += 1
            if receivedAudioDeltaCount == 1 || receivedAudioDeltaCount % 25 == 0 {
                Self.logger.info("output audio delta #\(self.receivedAudioDeltaCount, privacy: .public): \(audio.count, privacy: .public) bytes")
            }
            engine.enqueuePlayback(audio)

        case .inputTranscriptDelta(let delta):
            appendTranscript(role: .user, delta: delta)

        case .outputTranscriptDelta(let delta):
            appendTranscript(role: .assistant, delta: delta)

        case .inputAudioMuted:
            isInputMuted = true

        case .inputAudioUnmuted:
            isInputMuted = false

        case .contextAppended(let appended):
            guard let clientEventID = appended.clientEventID else { return }
            pendingContextAppendIDs.remove(clientEventID)
            contextMulticast.yield(
                .appended(
                    kind: appended.kind,
                    clientEventID: clientEventID,
                    startMilliseconds: appended.startMilliseconds,
                    endMilliseconds: appended.endMilliseconds
                )
            )

        case .delegationCreated(let request):
            delegationMulticast.yield(request)

        case .responseEvent(let event):
            responseMulticast.yield(event)

        case .usageUpdated(let usage):
            usageSeconds = usage.seconds
            if let ratio = usage.contextWindowUsageRatio {
                contextWindowUsageRatio = ratio
            }

        case .sessionClosed(let closed):
            if let session = closed.session {
                sessionInfo = session
            }
            finishSession(reason: closed.reason, seconds: closed.seconds)
            scheduleTeardown()

        case .error(let payload):
            handleErrorPayload(payload)

        case .unknown:
            break
        }
    }

    private func handleErrorPayload(_ payload: OpenAILiveErrorPayload) {
        if let clientEventID = payload.clientEventID {
            if pendingSessionUpdates[clientEventID] != nil {
                rejectPendingSessionUpdate(
                    eventID: clientEventID,
                    error: SpeechConversationError.commandRejected(code: payload.code, message: payload.message)
                )
                return
            }

            if pendingContextAppendIDs.remove(clientEventID) != nil {
                contextMulticast.yield(
                    .rejected(clientEventID: clientEventID, code: payload.code, message: payload.message)
                )
                // GPT-Live reports `context_injection_incomplete` for every
                // unacknowledged append as the session closes. That is the
                // normal outcome of a short session, not a session error.
                if case .ending = state {} else {
                    lastError = SpeechRealtimeErrorRedaction.redacted(
                        OpenAILiveError.commandRejected(
                            clientEventID: clientEventID,
                            code: payload.code,
                            message: payload.message
                        )
                    )
                }
                return
            }
        }

        switch state {
        case .active, .ending:
            // Moderation can cut speech short without closing the socket, so an
            // error after the session started is reported but not fatal.
            lastError = SpeechRealtimeErrorRedaction.redacted(
                OpenAILiveError.connectionFailed(payload.message)
            )
        case .idle, .connecting, .ended, .error:
            lastError = SpeechRealtimeErrorRedaction.redacted(
                OpenAILiveError.sessionRejected(code: payload.code, message: payload.message)
            )
            state = .error(payload.message)
        }
    }

    private func appendTranscript(role: SpeechConversationRole, delta: OpenAILiveTranscriptDelta) {
        transcript = assembler.append(
            role: role,
            delta: delta.delta,
            startMilliseconds: delta.startMilliseconds,
            endMilliseconds: delta.endMilliseconds,
            provider: .openAI
        )
        partialUserTranscriptText = assembler.partialText(for: .user)
        partialAssistantTranscriptText = assembler.partialText(for: .assistant)
    }

    private func finishSession(reason: SpeechConversationEndReason, seconds: Double?) {
        if let seconds {
            usageSeconds = seconds
        }
        closeTranscript()
        state = .ended(reason: reason, seconds: seconds ?? usageSeconds)
        cancelPendingCommands()
        resumeCloseWaiter(didClose: true)
    }

    private func closeTranscript() {
        assembler.closeOpenEntries()
        transcript = assembler.entries
        partialUserTranscriptText = ""
        partialAssistantTranscriptText = ""
    }

    // MARK: - Audio

    private func startAudioLoop() {
        guard isAudioCaptureEnabled, !engine.isRunning else { return }

        engine.setSampleRate(Double(options.audioFormat.sampleRate))

        let audioStream: AsyncStream<Data>
        do {
            audioStream = try engine.start()
        } catch {
            Self.logger.error("duplex engine failed to start: \(error.localizedDescription, privacy: .public)")
            publishError(error)
            return
        }
        sentAudioChunkCount = 0

        let runID = lifecycleRunID
        audioSendTask = Task { [weak self] in
            for await chunk in audioStream {
                if Task.isCancelled { break }
                guard let self, self.isCurrentLifecycleRun(runID) else { break }
                do {
                    try await self.socket.sendInputAudio(chunk)
                    self.sentAudioChunkCount += 1
                    if self.sentAudioChunkCount == 1 || self.sentAudioChunkCount % 50 == 0 {
                        Self.logger.info("sent audio chunk #\(self.sentAudioChunkCount, privacy: .public): \(chunk.count, privacy: .public) bytes")
                    }
                } catch {
                    Self.logger.error("audio send failed: \(error.localizedDescription, privacy: .public)")
                    if !Task.isCancelled, self.isCurrentLifecycleRun(runID) {
                        self.publishError(error)
                    }
                    break
                }
            }
            Self.logger.info("audio send loop ended after \(self?.sentAudioChunkCount ?? -1, privacy: .public) chunks")
        }
    }

    // MARK: - Commands

    private func appendContext(
        kind: OpenAILiveContextKind,
        content: String,
        delegationID: String?
    ) async throws -> String {
        guard state.isActive else { throw SpeechConversationError.notActive }

        let eventID = Self.makeEventID(prefix: kind.rawValue)
        let message = OpenAILiveContextAppendMessage(
            kind: kind,
            content: content,
            delegationID: delegationID,
            eventID: eventID
        )

        // The append is tracked before the write because GPT-Live can
        // acknowledge it while the write is still in flight.
        pendingContextAppendIDs.insert(eventID)
        do {
            try await write { try await $0.send(message) }
        } catch {
            pendingContextAppendIDs.remove(eventID)
            let redacted = SpeechRealtimeErrorRedaction.redacted(error)
            lastError = redacted
            throw redacted
        }
        return eventID
    }

    private func sendSessionControl(
        _ send: (OpenAILiveWebSocket) async throws -> Void
    ) async throws {
        guard state.isActive else { throw SpeechConversationError.notActive }

        do {
            try await write(send)
        } catch {
            let redacted = SpeechRealtimeErrorRedaction.redacted(error)
            lastError = redacted
            throw redacted
        }
    }

    /// The single outbound write path, so tests can drive event routing without a socket.
    private func write(_ send: (OpenAILiveWebSocket) async throws -> Void) async throws {
        guard !isSocketWriteSuppressedForTesting else { return }
        try await send(socket)
    }

    /// Builds a client event identifier that is recognizable in a provider trace.
    private static func makeEventID(prefix: String) -> String {
        "spk_\(prefix)_\(UUID().uuidString)"
    }

    private func resolvePendingSessionUpdate(eventID: String) {
        pendingSessionUpdateTimeouts.removeValue(forKey: eventID)?.cancel()
        guard let continuation = pendingSessionUpdates.removeValue(forKey: eventID) else { return }
        continuation.resume()
    }

    private func rejectPendingSessionUpdate(eventID: String, error: Error) {
        pendingSessionUpdateTimeouts.removeValue(forKey: eventID)?.cancel()
        guard let continuation = pendingSessionUpdates.removeValue(forKey: eventID) else { return }
        continuation.resume(throwing: error)
    }

    private func cancelPendingCommands() {
        pendingContextAppendIDs.removeAll()

        for task in pendingSessionUpdateTimeouts.values {
            task.cancel()
        }
        pendingSessionUpdateTimeouts.removeAll()

        let continuations = pendingSessionUpdates.values
        pendingSessionUpdates.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: SpeechConversationError.notActive)
        }
    }

    // MARK: - Close handshake

    private func waitForSessionClosed(timeout: TimeInterval) async -> Bool {
        if case .ended = state { return true }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            closeWaiter = continuation
            closeTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.resumeCloseWaiter(didClose: false)
            }
        }
    }

    private func resumeCloseWaiter(didClose: Bool) {
        closeTimeoutTask?.cancel()
        closeTimeoutTask = nil
        guard let waiter = closeWaiter else { return }
        closeWaiter = nil
        waiter.resume(returning: didClose)
    }

    // MARK: - Teardown

    private func scheduleTeardown() {
        let runID = lifecycleRunID
        Task { [weak self] in
            await self?.teardown(runID: runID)
        }
    }

    private func teardown(runID: UUID) async {
        guard isCurrentLifecycleRun(runID) else { return }

        audioSendTask?.cancel()
        audioSendTask = nil
        isAudioCaptureEnabled = false
        cancelPendingCommands()
        finishDelegationStreams()
        engine.stop()
        await socket.disconnect()
    }

    /// Finishes every delegation and response subscriber stream.
    ///
    /// Both surfaces describe one session, so a stream taken out during a
    /// session ends with it rather than silently going quiet.
    private func finishDelegationStreams() {
        delegationMulticast.finish()
        responseMulticast.finish()
        contextMulticast.finish()
    }

    // MARK: - Helpers

    private func joinedTranscriptText(for role: SpeechConversationRole) -> String {
        transcript
            .filter { $0.role == role }
            .map(\.displayText)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func publishError(_ error: Error) {
        lastError = SpeechRealtimeErrorRedaction.redacted(error)
    }

    private func publishFailure(_ error: Error) {
        let redacted = SpeechRealtimeErrorRedaction.redacted(error)
        lastError = redacted
        state = .error(redacted.localizedDescription)
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
