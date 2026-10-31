import Foundation

extension SpeechService {
    func withFileOperation<T: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        let id = UUID()
        let generation = fileGeneration
        let task = Task { try await operation() }
        fileOperationCancellations[id] = { task.cancel() }
        defer { fileOperationCancellations[id] = nil }
        return try await withTaskCancellationHandler {
            do {
                let result = try await task.value
                guard generation == fileGeneration else { throw CancellationError() }
                try Task.checkCancellation()
                return result
            } catch is CancellationError { throw CancellationError() }
            catch let error as SpeechError {
                guard generation == fileGeneration, !Task.isCancelled, !task.isCancelled else { throw CancellationError() }
                throw error
            }
            catch {
                guard generation == fileGeneration, !Task.isCancelled, !task.isCancelled else { throw CancellationError() }
                throw SpeechErrorBoundary.safe(error)
            }
        } onCancel: { task.cancel() }
    }

    /// Stops all local operations. This does not revoke credentials or delete vendor data.
    public func resetSession(discardTranscript: Bool = true, discardRecording: Bool = true) async {
        invalidatePendingOperations()
        await relaySession?.reset()
        fileGeneration = UUID()
        for cancel in fileOperationCancellations.values { cancel() }
        fileOperationCancellations.removeAll()
        await elevenLabsRealtimeService.resetSession(discardTranscript: discardTranscript, discardRecording: discardRecording)
        await openAIRealtimeService.resetSession(discardTranscript: discardTranscript, discardRecording: discardRecording)
        await grokRealtimeService.resetSession(discardTranscript: discardTranscript, discardRecording: discardRecording)
        await metaRealtimeService.resetSession(discardTranscript: discardTranscript, discardRecording: discardRecording)
        await geminiRealtimeService.resetSession(discardTranscript: discardTranscript, discardRecording: discardRecording)
        await mistralRealtimeService.resetSession(discardTranscript: discardTranscript, discardRecording: discardRecording)
        await fishAudioRealtimeService.resetSession(discardTranscript: discardTranscript, discardRecording: discardRecording)
        #if !os(watchOS)
        if #available(iOS 26, macOS 26, visionOS 26, *), let service = appleRealtimeServiceStorage as? AppleSpeechService {
            await service.stopListening()
            if discardTranscript { service.clearTranscript() }
            if discardRecording { service.discardRecording() }
        }
        #endif
        fallbackLastError = nil
        fallbackConnectionState = nil
    }

    /// Releases configured credentials and SDK-owned resolver captures.
    /// Preserves persisted App Attest key identifiers. Use an account-scoped relay for sign-in,
    /// or stop operations and call `SpeechRelay.resetAppAttestKey()` before changing accounts.
    public func clearCredentials() async {
        await resetSession()
        relay = nil
        relaySession = nil
        elevenLabs = nil
        openAI = nil
        grok = nil
        meta = nil
        gemini = nil
        mistral = nil
        fishAudio = nil
        cohere = nil
        aqua = nil
        await elevenLabsRealtimeService.clearCredentials()
        await openAIRealtimeService.clearCredentials()
        await grokRealtimeService.clearCredentials()
        await metaRealtimeService.clearCredentials()
        await geminiRealtimeService.clearCredentials()
        await mistralRealtimeService.clearCredentials()
        await fishAudioRealtimeService.clearCredentials()
    }

    /// Discards SDK-owned in-memory recordings. Caller-owned files are untouched.
    public func discardRecording() {
        elevenLabsRealtimeService.discardRecording()
        openAIRealtimeService.discardRecording()
        grokRealtimeService.discardRecording()
        metaRealtimeService.discardRecording()
        geminiRealtimeService.discardRecording()
        mistralRealtimeService.discardRecording()
        fishAudioRealtimeService.discardRecording()
        #if !os(watchOS)
        if #available(iOS 26, macOS 26, visionOS 26, *), let service = appleRealtimeServiceStorage as? AppleSpeechService {
            service.discardRecording()
        }
        #endif
    }
}
