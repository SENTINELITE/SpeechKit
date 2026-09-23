import Foundation

extension SpeechService {
    // MARK: - State

    /// The current speech-to-speech conversation state.
    public var conversationState: SpeechConversationState {
        if let fallbackConversationState {
            return fallbackConversationState
        }
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.state
        }
    }

    /// The grouped conversation transcript, oldest entry first.
    public var conversationTranscript: [SpeechConversationTranscriptEntry] {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.transcript
        }
    }

    /// The in-progress text of the newest open user entry.
    ///
    /// This is a view onto the open entry already present in
    /// ``conversationTranscript``, not additional text. Render one or the other.
    public var partialUserTranscriptText: String {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.partialUserTranscriptText
        }
    }

    /// The in-progress text of the newest open assistant entry.
    ///
    /// This is a view onto the open entry already present in
    /// ``conversationTranscript``, not additional text. Render one or the other.
    public var partialAssistantTranscriptText: String {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.partialAssistantTranscriptText
        }
    }

    /// The user side of the conversation transcript, joined with spaces.
    public var userTranscriptText: String {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.userTranscriptText
        }
    }

    /// The assistant side of the conversation transcript, joined with spaces.
    public var assistantTranscriptText: String {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.assistantTranscriptText
        }
    }

    /// The whole conversation as role-prefixed lines, oldest entry first.
    ///
    /// Each line reads `You: …` or `Assistant: …`, which suits a share sheet or
    /// a copy button. Open entries are included as they stand.
    public var conversationTranscriptText: String {
        conversationTranscript
            .map { entry in
                let prefix = entry.role == .user ? "You" : "Assistant"
                return "\(prefix): \(entry.displayText)"
            }
            .joined(separator: "\n")
    }

    /// The latest normalized microphone level for the active conversation, between `0` and `1`.
    public var conversationInputLevel: Double {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.inputLevel
        }
    }

    /// The latest normalized assistant playback level, between `0` and `1`.
    public var conversationOutputLevel: Double {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.outputLevel
        }
    }

    /// A Boolean value that indicates whether the provider has stopped listening to the microphone.
    public var isConversationInputMuted: Bool {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.isInputMuted
        }
    }

    /// A Boolean value that indicates whether assistant audio is still queued for playback.
    public var assistantIsSpeaking: Bool {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.assistantIsSpeaking
        }
    }

    /// The latest cumulative billed seconds reported by the conversation provider.
    ///
    /// Providers report a snapshot rather than an increment, so this value is
    /// replaced and never summed.
    public var conversationUsageSeconds: Double {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.usageSeconds
        }
    }

    /// How much of the model's context window the conversation has used, from `0` to `1`.
    public var conversationContextUsageRatio: Double? {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.contextWindowUsageRatio
        }
    }

    /// The moment the conversation session expires, when the provider reports one.
    public var conversationExpiresAt: Date? {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.expiresAt
        }
    }

    /// The captured conversation microphone audio as WAV data, if capture produced audio.
    public var conversationRecordingData: Data? {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.recordedWAVData
        }
    }

    /// The `event_id` values of context appends the provider has not answered yet.
    ///
    /// Outcomes arrive on ``OpenAILiveService/contextEvents``.
    public var conversationPendingContextAppendIDs: Set<String> {
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.pendingContextAppendIDs
        }
    }

    /// The OpenAI GPT-Live service behind the conversation facade.
    ///
    /// This exposes the OpenAI-specific delegation and context surfaces that
    /// have no provider-neutral twin yet:
    /// ``OpenAILiveService/delegationRequests``,
    /// ``OpenAILiveService/responseEvents``,
    /// ``OpenAILiveService/contextEvents``,
    /// ``OpenAILiveService/updateDelegation(_:)``,
    /// ``OpenAILiveService/createResponseItem(_:delegationID:)``, and
    /// ``OpenAILiveService/createResponse(delegationID:)``.
    ///
    /// Its credential, endpoint, and options are overwritten from ``openAI``
    /// every time ``startConversation(provider:)`` runs, so configure those
    /// through ``OpenAIConfiguration`` rather than on the service.
    public var openAILive: OpenAILiveService {
        openAILiveService
    }

    /// The most recent conversation error, if any.
    public var conversationLastError: Error? {
        if let fallbackConversationError {
            return fallbackConversationError
        }
        switch activeConversationProvider {
        case .openAI:
            return openAILiveService.lastError
        }
    }

    // MARK: - Lifecycle

    /// Starts a full-duplex speech-to-speech conversation with a configured provider.
    ///
    /// A conversation and a realtime transcription session would fight over the
    /// microphone, so this refuses with
    /// ``SpeechConversationError/microphoneBusy`` while a transcription session
    /// is in its lifecycle. Credential, endpoint, and options are re-read from
    /// the provider configuration immediately before the session opens.
    ///
    /// - Parameter provider: The conversation provider to use.
    public func startConversation(provider: SpeechConversationProvider = .openAI) async {
        if provider == activeConversationProvider, conversationState.isLifecycleActive {
            return
        }

        if provider != activeConversationProvider, conversationState.isLifecycleActive {
            await endConversation()
        }
        activeConversationProvider = provider

        guard !realtimeConnectionState.isLifecycleActive else {
            fallbackConversationState = .error(SpeechConversationError.microphoneBusy.localizedDescription)
            fallbackConversationError = SpeechConversationError.microphoneBusy
            return
        }

        switch provider {
        case .openAI:
            await startOpenAIConversation()
        }
    }

    func startOpenAIConversation() async {
        guard let openAI else {
            fallbackConversationState = .error("OpenAI is not configured")
            fallbackConversationError = SpeechConversationError.providerNotConfigured(.openAI)
            return
        }

        fallbackConversationState = nil
        fallbackConversationError = nil
        openAILiveService.credential = openAI.resolvedLiveCredential
        openAILiveService.liveEndpoint = openAI.liveEndpoint
        openAILiveService.options = openAI.live
        await openAILiveService.start()
    }

    /// Ends the active speech-to-speech conversation.
    public func endConversation() async {
        fallbackConversationState = nil
        fallbackConversationError = nil

        switch activeConversationProvider {
        case .openAI:
            await openAILiveService.end()
        }
    }

    // MARK: - Session control

    /// Asks the provider to stop listening to the microphone without ending the conversation.
    ///
    /// - Throws: ``SpeechConversationError/notActive`` when no conversation is
    ///   active, or the provider transport error when the request cannot be sent.
    public func muteConversationInput() async throws {
        switch activeConversationProvider {
        case .openAI:
            try await openAILiveService.muteInput()
        }
    }

    /// Asks the provider to listen to the microphone again.
    ///
    /// - Throws: ``SpeechConversationError/notActive`` when no conversation is
    ///   active, or the provider transport error when the request cannot be sent.
    public func unmuteConversationInput() async throws {
        switch activeConversationProvider {
        case .openAI:
            try await openAILiveService.unmuteInput()
        }
    }

    /// Mutes or unmutes microphone input without throwing.
    ///
    /// This is the binding-friendly form of ``muteConversationInput()`` and
    /// ``unmuteConversationInput()``. A failure lands in ``conversationLastError``
    /// instead of being thrown, and ``isConversationInputMuted`` changes only when
    /// the provider acknowledges the request.
    ///
    /// - Parameter isMuted: `true` to stop sending microphone audio.
    public func setConversationInputMuted(_ isMuted: Bool) async {
        do {
            if isMuted {
                try await muteConversationInput()
            } else {
                try await unmuteConversationInput()
            }
        } catch {
            switch activeConversationProvider {
            case .openAI:
                openAILiveService.recordCommandFailure(error)
            }
        }
    }

    /// Drops assistant audio that is queued but not yet heard, for a barge-in.
    public func flushAssistantAudio() {
        switch activeConversationProvider {
        case .openAI:
            openAILiveService.flushAssistantAudio()
        }
    }

    /// Clears the conversation transcript and both partial texts.
    public func clearConversationTranscript() {
        fallbackConversationState = nil
        fallbackConversationError = nil

        switch activeConversationProvider {
        case .openAI:
            openAILiveService.clearTranscript()
        }
    }

    // MARK: - Context injection

    /// Pushes trusted app directives into the running conversation.
    ///
    /// The call returns once the event is on the wire. The provider only
    /// acknowledges pushed context after the session timeline advances, so the
    /// outcome arrives on ``OpenAILiveService/contextEvents``.
    ///
    /// - Parameters:
    ///   - content: The directive text.
    ///   - delegationID: The delegation the directive belongs to, or `nil` for the whole session.
    /// - Returns: The `event_id` that identifies the append.
    /// - Throws: ``SpeechConversationError/notActive`` when no conversation is
    ///   active, or the provider transport error when the event cannot be sent.
    @discardableResult
    public func appendConversationInstructions(
        _ content: String,
        delegationID: String? = nil
    ) async throws -> String {
        switch activeConversationProvider {
        case .openAI:
            return try await openAILiveService.appendInstructions(content, delegationID: delegationID)
        }
    }

    /// Pushes quiet factual context into the running conversation.
    ///
    /// The provider never speaks thinking content aloud. The outcome arrives on
    /// ``OpenAILiveService/contextEvents``.
    ///
    /// - Parameters:
    ///   - content: The context text.
    ///   - delegationID: The delegation the context belongs to, or `nil` for the whole session.
    /// - Returns: The `event_id` that identifies the append.
    /// - Throws: ``SpeechConversationError/notActive`` when no conversation is
    ///   active, or the provider transport error when the event cannot be sent.
    @discardableResult
    public func appendConversationThinking(
        _ content: String,
        delegationID: String? = nil
    ) async throws -> String {
        switch activeConversationProvider {
        case .openAI:
            return try await openAILiveService.appendThinking(content, delegationID: delegationID)
        }
    }

    /// Pushes content the model may paraphrase aloud into the running conversation.
    ///
    /// The outcome arrives on ``OpenAILiveService/contextEvents``.
    ///
    /// - Parameters:
    ///   - content: The commentary text.
    ///   - delegationID: The delegation the commentary belongs to, or `nil` for the whole session.
    /// - Returns: The `event_id` that identifies the append.
    /// - Throws: ``SpeechConversationError/notActive`` when no conversation is
    ///   active, or the provider transport error when the event cannot be sent.
    @discardableResult
    public func appendConversationCommentary(
        _ content: String,
        delegationID: String? = nil
    ) async throws -> String {
        switch activeConversationProvider {
        case .openAI:
            return try await openAILiveService.appendCommentary(content, delegationID: delegationID)
        }
    }
}
