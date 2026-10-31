import Foundation

extension SpeechService {
    /// The current realtime connection state.
    public var realtimeConnectionState: SpeechRealtimeConnectionState {
        if let fallbackConnectionState {
            return fallbackConnectionState
        }
        switch activeRealtimeProvider {
        case .elevenLabs:
            return elevenLabsRealtimeService.connectionState
        case .openAI:
            return openAIRealtimeService.connectionState
        case .grok:
            return grokRealtimeService.connectionState
        case .meta:
            return metaRealtimeService.connectionState
        case .gemini:
            return geminiRealtimeService.connectionState
        case .mistral:
            return mistralRealtimeService.connectionState
        case .fishAudio:
            return fishAudioRealtimeService.connectionState
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                return appleSpeechService.connectionState
            }
            return .error(SpeechError.appleSpeechUnavailable.localizedDescription)
        #endif
        }
    }

    /// The current realtime connection state.
    public var connectionState: SpeechRealtimeConnectionState {
        realtimeConnectionState
    }

    /// The latest partial realtime transcript text.
    public var partialTranscriptText: String {
        switch activeRealtimeProvider {
        case .elevenLabs:
            return elevenLabsRealtimeService.partialTranscriptText
        case .openAI:
            return openAIRealtimeService.partialTranscriptText
        case .grok:
            return grokRealtimeService.partialTranscriptText
        case .meta:
            return metaRealtimeService.partialTranscriptText
        case .gemini:
            return geminiRealtimeService.partialTranscriptText
        case .mistral:
            return mistralRealtimeService.partialTranscriptText
        case .fishAudio:
            return fishAudioRealtimeService.partialTranscriptText
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                return appleSpeechService.partialTranscriptText
            }
            return ""
        #endif
        }
    }

    /// The latest partial realtime transcript entry.
    public var partialTranscriptEntry: SpeechTranscriptEntry? {
        switch activeRealtimeProvider {
        case .elevenLabs:
            guard !elevenLabsRealtimeService.partialTranscriptText.isEmpty else { return nil }
            return SpeechTranscriptEntry(
                provider: .elevenLabs,
                text: elevenLabsRealtimeService.partialTranscriptText,
                isFinal: false,
                isUtteranceFinal: false
            )
        case .openAI:
            guard !openAIRealtimeService.partialTranscriptText.isEmpty else { return nil }
            return SpeechTranscriptEntry(
                provider: .openAI,
                text: openAIRealtimeService.partialTranscriptText,
                isFinal: false,
                isUtteranceFinal: false
            )
        case .grok:
            return grokRealtimeService.partialTranscriptEntry
        case .meta:
            return metaRealtimeService.partialTranscriptEntry
        case .gemini:
            return geminiRealtimeService.partialTranscriptEntry
        case .mistral:
            return mistralRealtimeService.partialTranscriptEntry
        case .fishAudio:
            return fishAudioRealtimeService.partialTranscriptEntry
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                return appleSpeechService.partialTranscriptEntry
            }
            return nil
        #endif
        }
    }

    /// The latest normalized microphone input level for the active realtime provider.
    public var realtimeAudioLevel: Double {
        switch activeRealtimeProvider {
        case .elevenLabs:
            return elevenLabsRealtimeService.realtimeAudioLevel
        case .openAI:
            return openAIRealtimeService.realtimeAudioLevel
        case .grok:
            return grokRealtimeService.realtimeAudioLevel
        case .meta:
            return metaRealtimeService.realtimeAudioLevel
        case .gemini:
            return geminiRealtimeService.realtimeAudioLevel
        case .mistral:
            return mistralRealtimeService.realtimeAudioLevel
        case .fishAudio:
            return fishAudioRealtimeService.realtimeAudioLevel
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                return appleSpeechService.realtimeAudioLevel
            }
            return 0
        #endif
        }
    }

    /// The latest realtime microphone recording as WAV data, if capture has produced audio.
    public var realtimeRecordingData: Data? {
        switch activeRealtimeProvider {
        case .elevenLabs:
            return elevenLabsRealtimeService.realtimeRecordingData
        case .openAI:
            return openAIRealtimeService.realtimeRecordingData
        case .grok:
            return grokRealtimeService.realtimeRecordingData
        case .meta:
            return metaRealtimeService.realtimeRecordingData
        case .gemini:
            return geminiRealtimeService.realtimeRecordingData
        case .mistral:
            return mistralRealtimeService.realtimeRecordingData
        case .fishAudio:
            return fishAudioRealtimeService.realtimeRecordingData
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                return appleSpeechService.realtimeRecordingData
            }
            return nil
        #endif
        }
    }

    /// The committed realtime transcript entries.
    public var transcriptEntries: [SpeechTranscriptEntry] {
        switch activeRealtimeProvider {
        case .elevenLabs:
            return elevenLabsRealtimeService.transcriptEntries
        case .openAI:
            return openAIRealtimeService.transcriptEntries
        case .grok:
            return grokRealtimeService.transcriptEntries
        case .meta:
            return metaRealtimeService.transcriptEntries
        case .gemini:
            return geminiRealtimeService.transcriptEntries
        case .mistral:
            return mistralRealtimeService.transcriptEntries
        case .fishAudio:
            return fishAudioRealtimeService.transcriptEntries
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                return appleSpeechService.transcriptEntries
            }
            return []
        #endif
        }
    }

    /// The most recent realtime transcription error, if any.
    public var lastError: Error? {
        if let fallbackLastError {
            return fallbackLastError
        }
        switch activeRealtimeProvider {
        case .elevenLabs:
            return elevenLabsRealtimeService.lastError
        case .openAI:
            return openAIRealtimeService.lastError
        case .grok:
            return grokRealtimeService.lastError
        case .meta:
            return metaRealtimeService.lastError
        case .gemini:
            return geminiRealtimeService.lastError
        case .mistral:
            return mistralRealtimeService.lastError
        case .fishAudio:
            return fishAudioRealtimeService.lastError
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                return appleSpeechService.lastError
            }
            return SpeechError.appleSpeechUnavailable
        #endif
        }
    }

    /// The committed realtime transcript text joined with spaces.
    public var transcriptText: String {
        transcriptEntries.map(\.text).joined(separator: " ")
    }

    /// Starts realtime microphone transcription with the configured ElevenLabs provider.
    public func startListening() async {
        await startListening(provider: .elevenLabs)
    }

    /// Starts realtime microphone transcription with a configured provider.
    public func startListening(provider: SpeechRealtimeProvider) async {
        if (pendingRealtimeProvider == provider || (provider == activeRealtimeProvider && realtimeConnectionState.isLifecycleActive)) { return }
        if pendingRealtimeProvider != nil || realtimeConnectionState.isLifecycleActive { await stopListening() }
        let generation = UUID()
        realtimeStartGeneration = generation
        activeRealtimeProvider = provider
        pendingRealtimeProvider = provider
        let task = Task { [self] in await startRealtimeProvider(provider) }
        realtimeStartTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if generation == realtimeStartGeneration {
            pendingRealtimeProvider = nil
            realtimeStartTask = nil
        }
    }

    private func startRealtimeProvider(_ provider: SpeechRealtimeProvider) async {
        switch provider {
        case .elevenLabs:
            await startElevenLabsListening()
        case .openAI:
            await startOpenAIListening()
        case .grok:
            await startGrokListening()
        case .meta:
            await startMetaListening()
        case .gemini:
            await startGeminiListening()
        case .mistral:
            await startMistralListening()
        case .fishAudio:
            await startFishAudioListening()
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                await startAppleListening()
            } else {
                fallbackConnectionState = .error(SpeechError.appleSpeechUnavailable.localizedDescription)
                fallbackLastError = SpeechError.appleSpeechUnavailable
            }
        #endif
        }
    }

    func startElevenLabsListening() async {
        let generation = realtimeStartGeneration
        let resolved: ElevenLabsConfiguration?
        do { resolved = try await resolvedElevenLabsConfiguration(capability: .realtime) }
        catch {
            guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
            fallbackLastError = SpeechErrorBoundary.safe(error)
            fallbackConnectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            return
        }
        guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
        guard let elevenLabs = resolved else {
            fallbackConnectionState = .error("ElevenLabs is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.elevenLabs)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        elevenLabsRealtimeService.credential = elevenLabs.credential
        elevenLabsRealtimeService.realtimeEndpoint = elevenLabs.realtimeEndpoint
        elevenLabsRealtimeService.realtimeModelID = elevenLabs.realtimeModelID
        await elevenLabsRealtimeService.startListening()
    }

    func startOpenAIListening() async {
        let generation = realtimeStartGeneration
        let resolved: OpenAIConfiguration?
        do { resolved = try await resolvedOpenAIConfiguration(capability: .realtime) }
        catch {
            guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
            fallbackLastError = SpeechErrorBoundary.safe(error)
            fallbackConnectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            return
        }
        guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
        guard let openAI = resolved else {
            fallbackConnectionState = .error("OpenAI is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.openAI)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        openAIRealtimeService.credential = openAI.credential
        openAIRealtimeService.realtimeEndpoint = openAI.realtimeEndpoint
        openAIRealtimeService.options = resolvedOpenAIRealtimeOptions(from: openAI)
        await openAIRealtimeService.startListening()
    }

    func startGrokListening() async {
        let generation = realtimeStartGeneration
        let resolved: GrokConfiguration?
        do { resolved = try await resolvedGrokConfiguration(capability: .realtime) }
        catch {
            guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
            fallbackLastError = SpeechErrorBoundary.safe(error)
            fallbackConnectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            return
        }
        guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
        guard let grok = resolved else {
            fallbackConnectionState = .error("Grok is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.grok)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        grokRealtimeService.credential = grok.credential
        grokRealtimeService.realtimeEndpoint = grok.realtimeEndpoint
        grokRealtimeService.options = grok.realtimeOptions
        await grokRealtimeService.startListening()
    }

    func startMetaListening() async {
        let generation = realtimeStartGeneration
        let resolved: MetaConfiguration?
        do { resolved = try await resolvedMetaConfiguration(capability: .realtime) }
        catch {
            guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
            fallbackLastError = SpeechErrorBoundary.safe(error)
            fallbackConnectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            return
        }
        guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
        guard let meta = resolved else {
            fallbackConnectionState = .error("Meta is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.meta)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        metaRealtimeService.credential = meta.credential
        metaRealtimeService.realtimeEndpoint = meta.realtimeEndpoint
        metaRealtimeService.options = meta.realtimeOptions
        await metaRealtimeService.startListening()
    }

    func startGeminiListening() async {
        let generation = realtimeStartGeneration
        let resolved: GeminiConfiguration?
        do { resolved = try await resolvedGeminiConfiguration(capability: .realtime) }
        catch {
            guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
            fallbackLastError = SpeechErrorBoundary.safe(error)
            fallbackConnectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            return
        }
        guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
        guard let gemini = resolved else {
            fallbackConnectionState = .error("Gemini is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.gemini)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        geminiRealtimeService.credential = gemini.credential
        geminiRealtimeService.realtimeEndpoint = gemini.realtimeEndpoint
        geminiRealtimeService.options = resolvedGeminiRealtimeOptions(from: gemini)
        await geminiRealtimeService.startListening()
    }

    func startMistralListening() async {
        let generation = realtimeStartGeneration
        let resolved: MistralConfiguration?
        do { resolved = try await resolvedMistralConfiguration(capability: .realtime) }
        catch {
            guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
            fallbackLastError = SpeechErrorBoundary.safe(error)
            fallbackConnectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            return
        }
        guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
        guard let mistral = resolved else {
            fallbackConnectionState = .error("Mistral is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.mistral)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        mistralRealtimeService.credential = mistral.credential
        mistralRealtimeService.realtimeEndpoint = mistral.realtimeEndpoint
        mistralRealtimeService.options = mistral.realtimeOptions
        await mistralRealtimeService.startListening()
    }

    func startFishAudioListening() async {
        let generation = realtimeStartGeneration
        let resolved: FishAudioConfiguration?
        do { resolved = try await resolvedFishAudioConfiguration(capability: .realtime) }
        catch {
            guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
            fallbackLastError = SpeechErrorBoundary.safe(error)
            fallbackConnectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            return
        }
        guard generation == realtimeStartGeneration, !Task.isCancelled else { return }
        guard let fishAudio = resolved else {
            fallbackConnectionState = .error("Fish Audio is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.fishAudio)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        fishAudioRealtimeService.credential = fishAudio.credential
        fishAudioRealtimeService.realtimeEndpoint = fishAudio.realtimeEndpoint
        fishAudioRealtimeService.options = fishAudio.realtimeOptions
        await fishAudioRealtimeService.startListening()
    }

    /// Stops realtime microphone transcription and disconnects from the active provider.
    public func stopListening() async {
        realtimeStartGeneration = UUID()
        realtimeStartTask?.cancel()
        realtimeStartTask = nil
        pendingRealtimeProvider = nil
        fallbackConnectionState = nil
        fallbackLastError = nil

        switch activeRealtimeProvider {
        case .elevenLabs:
            await elevenLabsRealtimeService.stopListening()
        case .openAI:
            await openAIRealtimeService.stopListening()
        case .grok:
            await grokRealtimeService.stopListening()
        case .meta:
            await metaRealtimeService.stopListening()
        case .gemini:
            await geminiRealtimeService.stopListening()
        case .mistral:
            await mistralRealtimeService.stopListening()
        case .fishAudio:
            await fishAudioRealtimeService.stopListening()
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                await appleSpeechService.stopListening()
            }
        #endif
        }
    }

    /// Clears committed and partial realtime transcript text.
    public func clearTranscript() {
        fallbackConnectionState = nil
        fallbackLastError = nil
        switch activeRealtimeProvider {
        case .elevenLabs:
            elevenLabsRealtimeService.clearTranscript()
        case .openAI:
            openAIRealtimeService.clearTranscript()
        case .grok:
            grokRealtimeService.clearTranscript()
        case .meta:
            metaRealtimeService.clearTranscript()
        case .gemini:
            geminiRealtimeService.clearTranscript()
        case .mistral:
            mistralRealtimeService.clearTranscript()
        case .fishAudio:
            fishAudioRealtimeService.clearTranscript()
        #if !os(watchOS)
        case .apple:
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                appleSpeechService.clearTranscript()
            }
        #endif
        }
    }
}
