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
        if provider == activeRealtimeProvider, realtimeConnectionState.isLifecycleActive {
            return
        }

        if provider != activeRealtimeProvider, realtimeConnectionState.isLifecycleActive {
            await stopListening()
        }
        activeRealtimeProvider = provider
        switch provider {
        case .elevenLabs:
            await startElevenLabsListening()
        case .openAI:
            await startOpenAIListening()
        case .grok:
            await startGrokListening()
        }
    }

    func startElevenLabsListening() async {
        guard let elevenLabs else {
            fallbackConnectionState = .error("ElevenLabs is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.elevenLabs)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        elevenLabsRealtimeService.apiKey = elevenLabs.apiKey
        elevenLabsRealtimeService.realtimeModelID = elevenLabs.realtimeModelID
        await elevenLabsRealtimeService.startListening()
    }

    func startOpenAIListening() async {
        guard let openAI else {
            fallbackConnectionState = .error("OpenAI is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.openAI)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        openAIRealtimeService.apiKey = openAI.apiKey
        openAIRealtimeService.options = resolvedOpenAIRealtimeOptions(from: openAI)
        await openAIRealtimeService.startListening()
    }

    func startGrokListening() async {
        guard let grok else {
            fallbackConnectionState = .error("Grok is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.grok)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        grokRealtimeService.apiKey = grok.apiKey
        grokRealtimeService.options = grok.realtimeOptions
        await grokRealtimeService.startListening()
    }

    /// Stops realtime microphone transcription and disconnects from the active provider.
    public func stopListening() async {
        fallbackConnectionState = nil
        fallbackLastError = nil
        guard realtimeConnectionState.isLifecycleActive else {
            return
        }

        switch activeRealtimeProvider {
        case .elevenLabs:
            await elevenLabsRealtimeService.stopListening()
        case .openAI:
            await openAIRealtimeService.stopListening()
        case .grok:
            await grokRealtimeService.stopListening()
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
        }
    }
}
