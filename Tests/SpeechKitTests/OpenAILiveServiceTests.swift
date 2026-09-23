import Foundation
import Testing
@testable import SpeechKit

/// One captured GPT-Live transcript fragment.
private struct LiveFragment {
    let role: SpeechConversationRole
    let delta: String
    let start: Int
    let end: Int
}

/// The fragment sequence captured from gpt-live-1 on 2026-09-15, where the model
/// began answering before the user finished the question.
private let capturedLiveFragments: [LiveFragment] = [
    LiveFragment(role: .user, delta: "Hello", start: 600, end: 800),
    LiveFragment(role: .user, delta: " there", start: 1000, end: 1200),
    LiveFragment(role: .user, delta: ". What is", start: 1400, end: 1600),
    LiveFragment(role: .user, delta: " the", start: 1600, end: 1800),
    LiveFragment(role: .user, delta: " capital", start: 2000, end: 2200),
    LiveFragment(role: .user, delta: " of", start: 2200, end: 2400),
    LiveFragment(role: .assistant, delta: "Paris.", start: 2600, end: 2800),
    LiveFragment(role: .user, delta: " France", start: 2800, end: 3000),
    LiveFragment(role: .user, delta: "?", start: 3000, end: 3200)
]

@MainActor
private func replayCapturedFragments(into service: OpenAILiveService) {
    for fragment in capturedLiveFragments {
        let delta = OpenAILiveTranscriptDelta(
            delta: fragment.delta,
            startMilliseconds: fragment.start,
            endMilliseconds: fragment.end,
            eventID: nil
        )
        switch fragment.role {
        case .user:
            service.handleMessageForTesting(.inputTranscriptDelta(delta))
        case .assistant:
            service.handleMessageForTesting(.outputTranscriptDelta(delta))
        }
    }
}

private func liveSessionInfo(id: String, expiresAt: Date? = nil) -> OpenAILiveSessionInfo {
    OpenAILiveSessionInfo(
        id: id,
        expiresAt: expiresAt,
        model: "gpt-live-1",
        voice: .marin,
        status: "active"
    )
}

@Suite("OpenAI GPT-Live service")
struct OpenAILiveServiceTests {
    // MARK: - Session handshake

    @MainActor
    @Test("session started moves connecting to active and publishes the expiry")
    func sessionStartedActivatesSession() {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.connecting)
        let expiresAt = Date(timeIntervalSince1970: 1789518426)

        service.handleMessageForTesting(.sessionStarted(liveSessionInfo(id: "live_1", expiresAt: expiresAt)))

        #expect(service.state == .active(sessionID: "live_1"))
        #expect(service.sessionInfo?.id == "live_1")
        #expect(service.expiresAt == expiresAt)
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("a duplicate session started acknowledgement is ignored")
    func duplicateSessionStartedIsIgnored() {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(.sessionStarted(liveSessionInfo(id: "live_1")))
        service.handleMessageForTesting(.sessionStarted(liveSessionInfo(id: "live_2")))

        #expect(service.state == .active(sessionID: "live_1"))
        #expect(service.sessionInfo?.id == "live_1")
    }

    @MainActor
    @Test("session started is ignored while idle")
    func sessionStartedIsIgnoredWhileIdle() {
        let service = OpenAILiveService(apiKey: "sk-live")

        service.handleMessageForTesting(.sessionStarted(liveSessionInfo(id: "live_1")))

        #expect(service.state == .idle)
    }

    // MARK: - Transcript

    @MainActor
    @Test("transcript deltas group into interleaved user and assistant entries")
    func transcriptDeltasGroupByRole() {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))

        replayCapturedFragments(into: service)

        #expect(service.transcript.count == 2)
        #expect(service.transcript[0].role == .user)
        #expect(service.transcript[0].text == "Hello there. What is the capital of France?")
        #expect(service.transcript[1].role == .assistant)
        #expect(service.transcript[1].text == "Paris.")
        #expect(service.partialUserTranscriptText == "Hello there. What is the capital of France?")
        #expect(service.partialAssistantTranscriptText == "Paris.")
        #expect(service.userTranscriptText == "Hello there. What is the capital of France?")
        #expect(service.assistantTranscriptText == "Paris.")
    }

    @MainActor
    @Test("clearing the transcript empties entries and partials")
    func clearTranscriptEmptiesEntriesAndPartials() {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))
        replayCapturedFragments(into: service)

        service.clearTranscript()

        #expect(service.transcript.isEmpty)
        #expect(service.partialUserTranscriptText.isEmpty)
        #expect(service.partialAssistantTranscriptText.isEmpty)
    }

    // MARK: - Usage

    @MainActor
    @Test("usage seconds are a snapshot rather than a running sum")
    func usageSecondsAreASnapshot() {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))

        service.handleMessageForTesting(.usageUpdated(OpenAILiveUsage(seconds: 7, contextWindowUsageRatio: nil)))
        service.handleMessageForTesting(.usageUpdated(OpenAILiveUsage(seconds: 7, contextWindowUsageRatio: 0.25)))

        #expect(service.usageSeconds == 7)
        #expect(service.contextWindowUsageRatio == 0.25)
    }

    // MARK: - Mute

    @MainActor
    @Test("mute state follows the provider acknowledgement")
    func muteStateFollowsAcknowledgement() {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))

        service.handleMessageForTesting(.inputAudioMuted)
        #expect(service.isInputMuted)

        service.handleMessageForTesting(.inputAudioUnmuted)
        #expect(service.isInputMuted == false)
    }

    @MainActor
    @Test("muting without an active session throws")
    func muteWithoutActiveSessionThrows() async {
        let service = OpenAILiveService(apiKey: "sk-live")

        await #expect(throws: SpeechConversationError.notActive) {
            try await service.muteInput()
        }
    }

    // MARK: - Close

    @MainActor
    @Test("session closed ends the session with its reason, seconds, and closed entries")
    func sessionClosedEndsTheSession() {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))
        replayCapturedFragments(into: service)

        service.handleMessageForTesting(
            .sessionClosed(OpenAILiveSessionClosed(reason: .closeRequested, seconds: 7, session: nil))
        )

        #expect(service.state == .ended(reason: .closeRequested, seconds: 7))
        #expect(service.usageSeconds == 7)
        #expect(service.transcript.allSatisfy { $0.isOpen == false })
        #expect(service.partialUserTranscriptText.isEmpty)
        #expect(service.partialAssistantTranscriptText.isEmpty)
    }

    // MARK: - Errors

    @MainActor
    @Test("an error before the session starts rejects the session")
    func errorBeforeSessionStartRejectsTheSession() {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(
            .error(
                OpenAILiveErrorPayload(
                    type: "invalid_request_error",
                    code: "forbidden",
                    message: "Voice session access denied.",
                    param: nil,
                    clientEventID: nil
                )
            )
        )

        #expect(service.state == .error("Voice session access denied."))
        #expect(
            service.lastError as? OpenAILiveError
                == .sessionRejected(code: "forbidden", message: "Voice session access denied.")
        )
    }

    @MainActor
    @Test("an error after the session starts keeps the session active")
    func errorAfterSessionStartKeepsTheSessionActive() {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))

        service.handleMessageForTesting(
            .error(
                OpenAILiveErrorPayload(
                    type: "server_error",
                    code: "content_filter",
                    message: "Response cut short.",
                    param: nil,
                    clientEventID: nil
                )
            )
        )

        #expect(service.state == .active(sessionID: "live_1"))
        #expect(service.lastError as? OpenAILiveError == .connectionFailed("Response cut short."))
    }

    // MARK: - Context injection

    @MainActor
    @Test("a context append returns its event id and stays pending until the provider answers")
    func contextAppendReturnsEventIDAndStaysPending() async throws {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.isSocketWriteSuppressedForTesting = true
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))

        let eventID = try await service.appendInstructions("Speak slowly.")

        #expect(eventID.hasPrefix("spk_instructions_"))
        #expect(service.pendingContextAppendIDs == [eventID])
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("an acknowledgement clears the pending append and reaches a context subscriber")
    func contextAppendedReachesSubscriber() async throws {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.isSocketWriteSuppressedForTesting = true
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))
        var events = service.contextEvents.makeAsyncIterator()

        let eventID = try await service.appendThinking("The user is on the billing screen.")
        service.handleMessageForTesting(
            .contextAppended(
                OpenAILiveContextAppended(
                    kind: .thinking,
                    clientEventID: eventID,
                    startMilliseconds: 4200,
                    endMilliseconds: 4200
                )
            )
        )

        let event = await events.next()
        #expect(
            event == .appended(
                kind: .thinking,
                clientEventID: eventID,
                startMilliseconds: 4200,
                endMilliseconds: 4200
            )
        )
        #expect(service.pendingContextAppendIDs.isEmpty)
    }

    @MainActor
    @Test("an error carrying the client event id rejects the matching append")
    func contextAppendRejectionReachesSubscriber() async throws {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.isSocketWriteSuppressedForTesting = true
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))
        var events = service.contextEvents.makeAsyncIterator()

        let eventID = try await service.appendCommentary("The order shipped.")
        service.handleMessageForTesting(
            .error(
                OpenAILiveErrorPayload(
                    type: "invalid_request_error",
                    code: "invalid_value",
                    message: "Too long.",
                    param: "content",
                    clientEventID: eventID
                )
            )
        )

        let event = await events.next()
        #expect(event == .rejected(clientEventID: eventID, code: "invalid_value", message: "Too long."))
        #expect(service.pendingContextAppendIDs.isEmpty)
        #expect(service.state == .active(sessionID: "live_1"))
        #expect(
            service.lastError as? OpenAILiveError
                == .commandRejected(clientEventID: eventID, code: "invalid_value", message: "Too long.")
        )
    }

    @MainActor
    @Test("an incomplete context injection while ending is not a session error")
    func contextInjectionIncompleteWhileEndingIsBenign() async throws {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.isSocketWriteSuppressedForTesting = true
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))
        var events = service.contextEvents.makeAsyncIterator()
        let eventID = try await service.appendInstructions("Speak slowly.")
        service.setLifecycleStateForTesting(.ending)

        service.handleMessageForTesting(
            .error(
                OpenAILiveErrorPayload(
                    type: "server_error",
                    code: "context_injection_incomplete",
                    message: "Context injection did not complete before the session closed.",
                    param: nil,
                    clientEventID: eventID
                )
            )
        )

        let event = await events.next()
        #expect(
            event == .rejected(
                clientEventID: eventID,
                code: "context_injection_incomplete",
                message: "Context injection did not complete before the session closed."
            )
        )
        #expect(service.pendingContextAppendIDs.isEmpty)
        #expect(service.state == .ending)
        #expect(service.lastError == nil)
    }

    @MainActor
    @Test("appending context without an active session throws")
    func contextAppendWithoutActiveSessionThrows() async {
        let service = OpenAILiveService(apiKey: "sk-live")

        await #expect(throws: SpeechConversationError.notActive) {
            _ = try await service.appendCommentary("The order shipped.")
        }
    }

    @MainActor
    @Test("ending a session clears every pending context append")
    func sessionEndClearsPendingContextAppends() async throws {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.isSocketWriteSuppressedForTesting = true
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))
        _ = try await service.appendInstructions("Speak slowly.")

        service.handleMessageForTesting(
            .sessionClosed(OpenAILiveSessionClosed(reason: .content, seconds: 3, session: nil))
        )

        #expect(service.pendingContextAppendIDs.isEmpty)
    }

    // MARK: - Delegation

    @MainActor
    @Test("a delegation request reaches a subscriber")
    func delegationRequestReachesSubscriber() async {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))
        var requests = service.delegationRequests.makeAsyncIterator()

        service.handleMessageForTesting(
            .delegationCreated(OpenAILiveDelegationRequest(id: "del_1", target: "client"))
        )

        let request = await requests.next()
        #expect(request?.id == "del_1")
        #expect(request?.target == "client")
    }

    @MainActor
    @Test("a delegated response event reaches a subscriber")
    func responseEventReachesSubscriber() async {
        let service = OpenAILiveService(apiKey: "sk-live")
        service.setLifecycleStateForTesting(.active(sessionID: "live_1"))
        var events = service.responseEvents.makeAsyncIterator()

        service.handleMessageForTesting(
            .responseEvent(
                OpenAILiveResponseEvent(
                    delegationID: "del_1",
                    eventType: "response.completed",
                    raw: ["type": "response.completed"]
                )
            )
        )

        let event = await events.next()
        #expect(event?.eventType == "response.completed")
        #expect(event?.delegationID == "del_1")
    }
}
