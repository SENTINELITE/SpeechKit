import Foundation

extension SpeechService {
    public convenience init(relay: SpeechRelay,
        elevenLabs: ElevenLabsConfiguration? = nil, cohere: CohereConfiguration? = nil,
        grok: GrokConfiguration? = nil, aqua: AquaConfiguration? = nil,
        openAI: OpenAIConfiguration? = nil, meta: MetaConfiguration? = nil,
        gemini: GeminiConfiguration? = nil, mistral: MistralConfiguration? = nil,
        fishAudio: FishAudioConfiguration? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys) {
        self.init(elevenLabs: elevenLabs, cohere: cohere, grok: grok, aqua: aqua,
                  openAI: openAI, meta: meta, gemini: gemini, mistral: mistral,
                  fishAudio: fishAudio, credentialPolicy: credentialPolicy)
        self.relay = relay
        self.relaySession = SpeechRelaySession(relay: relay)
    }

    func invalidatePendingOperations() {
        realtimeStartGeneration = UUID()
        realtimeStartTask?.cancel()
        realtimeStartTask = nil
        pendingRealtimeProvider = nil
        fileGeneration = UUID()
        for cancel in fileOperationCancellations.values { cancel() }
        fileOperationCancellations.removeAll()
    }

    func resolvedElevenLabsConfiguration(capability: SpeechCapability) async throws -> ElevenLabsConfiguration? {
        guard elevenLabs != nil || relay != nil else { return nil }
        var config = elevenLabs ?? ElevenLabsConfiguration()
        let credential = config.credential(for: capability)
        let directEndpoint = capability == .fileTranscription ? config.fileEndpoint : config.realtimeEndpoint
        if relay == nil || credential.isConfigured {
            if relay != nil && directEndpoint == nil { throw SpeechFailure(.invalidEndpoint) }
            if credential.kind == .apiKey && credentialPolicy != .allowStaticKeys { throw SpeechFailure(.staticKeysDisallowed) }
            if credentialPolicy == .relayOnly { throw SpeechFailure(.unsupportedAuthentication) }
            config.setCredential(credential)
            return config
        }
        guard let relaySession else { throw SpeechFailure(.invalidEndpoint) }
        let model = capability == .fileTranscription ? config.fileTranscriptionModelID.rawValue : config.realtimeModelID.rawValue
        let route = try await relaySession.route(provider: .elevenLabs, capability: capability, model: model,
                                                  allowVendorTokens: credentialPolicy != .relayOnly)
        try Task.checkCancellation()
        config.setCredential(route.credential)
        if capability == .realtime { config.realtimeEndpoint = route.endpoint }
        else { config.fileEndpoint = route.endpoint }
        return config
    }

    func resolvedOpenAIConfiguration(capability: SpeechCapability) async throws -> OpenAIConfiguration? {
        guard openAI != nil || relay != nil else { return nil }
        var config = openAI ?? OpenAIConfiguration()
        let credential = config.credential(for: capability)
        let directEndpoint = capability == .fileTranscription ? config.fileEndpoint : config.realtimeEndpoint
        if relay == nil || credential.isConfigured {
            if relay != nil && directEndpoint == nil { throw SpeechFailure(.invalidEndpoint) }
            if credential.kind == .apiKey && credentialPolicy != .allowStaticKeys { throw SpeechFailure(.staticKeysDisallowed) }
            if credentialPolicy == .relayOnly { throw SpeechFailure(.unsupportedAuthentication) }
            config.setCredential(credential)
            return config
        }
        guard let relaySession else { throw SpeechFailure(.invalidEndpoint) }
        let model = capability == .fileTranscription ? config.fileTranscriptionModelID.rawValue : config.realtimeTranscriptionModelID.rawValue
        let route = try await relaySession.route(provider: .openAI, capability: capability, model: model,
                                                  allowVendorTokens: credentialPolicy != .relayOnly)
        try Task.checkCancellation()
        config.setCredential(route.credential)
        if capability == .realtime { config.realtimeEndpoint = route.endpoint }
        else { config.fileEndpoint = route.endpoint }
        return config
    }

    func resolvedGrokConfiguration(capability: SpeechCapability) async throws -> GrokConfiguration? {
        guard grok != nil || relay != nil else { return nil }
        var config = grok ?? GrokConfiguration()
        let credential = config.credential(for: capability)
        let directEndpoint = capability == .fileTranscription ? config.fileEndpoint : config.realtimeEndpoint
        if relay == nil || credential.isConfigured {
            if relay != nil && directEndpoint == nil { throw SpeechFailure(.invalidEndpoint) }
            if credential.kind == .apiKey && credentialPolicy != .allowStaticKeys { throw SpeechFailure(.staticKeysDisallowed) }
            if credentialPolicy == .relayOnly { throw SpeechFailure(.unsupportedAuthentication) }
            config.setCredential(credential)
            return config
        }
        guard let relaySession else { throw SpeechFailure(.invalidEndpoint) }
        let model = capability == .fileTranscription ? config.modelID.rawValue : "grok-stt"
        let route = try await relaySession.route(provider: .grok, capability: capability, model: model,
                                                  allowVendorTokens: credentialPolicy != .relayOnly)
        try Task.checkCancellation()
        config.setCredential(route.credential)
        if capability == .realtime { config.realtimeEndpoint = route.endpoint }
        else { config.fileEndpoint = route.endpoint }
        return config
    }

    func resolvedMetaConfiguration(capability: SpeechCapability) async throws -> MetaConfiguration? {
        guard meta != nil || relay != nil else { return nil }
        var config = meta ?? MetaConfiguration()
        let credential = config.credential(for: capability)
        let directEndpoint = capability == .fileTranscription ? config.fileEndpoint : config.realtimeEndpoint
        if relay == nil || credential.isConfigured {
            if relay != nil && directEndpoint == nil { throw SpeechFailure(.invalidEndpoint) }
            if credential.kind == .apiKey && credentialPolicy != .allowStaticKeys { throw SpeechFailure(.staticKeysDisallowed) }
            if credentialPolicy == .relayOnly { throw SpeechFailure(.unsupportedAuthentication) }
            config.setCredential(credential)
            return config
        }
        guard let relaySession else { throw SpeechFailure(.invalidEndpoint) }
        let model = capability == .fileTranscription ? config.modelID.rawValue : config.realtimeOptions.modelID.rawValue
        let route = try await relaySession.route(provider: .meta, capability: capability, model: model,
                                                  allowVendorTokens: credentialPolicy != .relayOnly)
        try Task.checkCancellation()
        config.setCredential(route.credential)
        if capability == .realtime { config.realtimeEndpoint = route.endpoint }
        else { config.fileEndpoint = route.endpoint }
        return config
    }

    func resolvedGeminiConfiguration(capability: SpeechCapability) async throws -> GeminiConfiguration? {
        guard gemini != nil || relay != nil else { return nil }
        var config = gemini ?? GeminiConfiguration()
        let credential = config.credential(for: capability)
        let directEndpoint = capability == .fileTranscription ? config.fileEndpoint : config.realtimeEndpoint
        if relay == nil || credential.isConfigured {
            if relay != nil && directEndpoint == nil { throw SpeechFailure(.invalidEndpoint) }
            if credential.kind == .apiKey && credentialPolicy != .allowStaticKeys { throw SpeechFailure(.staticKeysDisallowed) }
            if credentialPolicy == .relayOnly { throw SpeechFailure(.unsupportedAuthentication) }
            config.setCredential(credential)
            return config
        }
        guard let relaySession else { throw SpeechFailure(.invalidEndpoint) }
        let model = capability == .fileTranscription ? config.fileTranscriptionModelID.rawValue : config.realtimeModelID.rawValue
        let route = try await relaySession.route(provider: .gemini, capability: capability, model: model,
                                                  allowVendorTokens: credentialPolicy != .relayOnly)
        try Task.checkCancellation()
        config.setCredential(route.credential)
        if capability == .realtime { config.realtimeEndpoint = route.endpoint }
        else { config.fileEndpoint = route.endpoint }
        config.routeOriginPolicy = .sameOrigin
        config.filesEndpoint = route.filesEndpoint
        return config
    }

    func resolvedMistralConfiguration(capability: SpeechCapability) async throws -> MistralConfiguration? {
        guard mistral != nil || relay != nil else { return nil }
        var config = mistral ?? MistralConfiguration()
        let credential = config.credential(for: capability)
        let directEndpoint = capability == .fileTranscription ? config.fileEndpoint : config.realtimeEndpoint
        if relay == nil || credential.isConfigured {
            if relay != nil && directEndpoint == nil { throw SpeechFailure(.invalidEndpoint) }
            if credential.kind == .apiKey && credentialPolicy != .allowStaticKeys { throw SpeechFailure(.staticKeysDisallowed) }
            if credentialPolicy == .relayOnly { throw SpeechFailure(.unsupportedAuthentication) }
            config.setCredential(credential)
            return config
        }
        guard let relaySession else { throw SpeechFailure(.invalidEndpoint) }
        let model = capability == .fileTranscription ? config.fileTranscriptionModelID.rawValue : config.realtimeOptions.modelID.rawValue
        let route = try await relaySession.route(provider: .mistral, capability: capability, model: model,
                                                  allowVendorTokens: credentialPolicy != .relayOnly)
        try Task.checkCancellation()
        config.setCredential(route.credential)
        if capability == .realtime { config.realtimeEndpoint = route.endpoint }
        else { config.fileEndpoint = route.endpoint }
        return config
    }

    func resolvedFishAudioConfiguration(capability: SpeechCapability) async throws -> FishAudioConfiguration? {
        guard fishAudio != nil || relay != nil else { return nil }
        var config = fishAudio ?? FishAudioConfiguration()
        let credential = config.credential(for: capability)
        let directEndpoint = capability == .fileTranscription ? config.fileEndpoint : config.realtimeEndpoint
        if relay == nil || credential.isConfigured {
            if relay != nil && directEndpoint == nil { throw SpeechFailure(.invalidEndpoint) }
            if credential.kind == .apiKey && credentialPolicy != .allowStaticKeys { throw SpeechFailure(.staticKeysDisallowed) }
            if credentialPolicy == .relayOnly { throw SpeechFailure(.unsupportedAuthentication) }
            config.setCredential(credential)
            return config
        }
        guard let relaySession else { throw SpeechFailure(.invalidEndpoint) }
        let model = capability == .fileTranscription ? config.fileTranscriptionModelID.rawValue : "transcribe-stream-1"
        let route = try await relaySession.route(provider: .fishAudio, capability: capability, model: model,
                                                  allowVendorTokens: credentialPolicy != .relayOnly)
        try Task.checkCancellation()
        config.setCredential(route.credential)
        if capability == .realtime { config.realtimeEndpoint = route.endpoint }
        else { config.fileEndpoint = route.endpoint }
        return config
    }

    func resolvedCohereConfiguration(capability: SpeechCapability) async throws -> CohereConfiguration? {
        guard cohere != nil || relay != nil else { return nil }
        var config = cohere ?? CohereConfiguration()
        let credential = config.credential(for: capability)
        let directEndpoint = config.fileEndpoint
        if relay == nil || credential.isConfigured {
            if relay != nil && directEndpoint == nil { throw SpeechFailure(.invalidEndpoint) }
            if credential.kind == .apiKey && credentialPolicy != .allowStaticKeys { throw SpeechFailure(.staticKeysDisallowed) }
            if credentialPolicy == .relayOnly { throw SpeechFailure(.unsupportedAuthentication) }
            config.setCredential(credential)
            return config
        }
        guard let relaySession else { throw SpeechFailure(.invalidEndpoint) }
        let model = capability == .fileTranscription ? config.modelID.rawValue : ""
        let route = try await relaySession.route(provider: .cohere, capability: capability, model: model,
                                                  allowVendorTokens: credentialPolicy != .relayOnly)
        try Task.checkCancellation()
        config.setCredential(route.credential)
        config.fileEndpoint = route.endpoint
        return config
    }

    func resolvedAquaConfiguration(capability: SpeechCapability) async throws -> AquaConfiguration? {
        guard aqua != nil || relay != nil else { return nil }
        var config = aqua ?? AquaConfiguration()
        let credential = config.credential(for: capability)
        let directEndpoint = config.fileEndpoint
        if relay == nil || credential.isConfigured {
            if relay != nil && directEndpoint == nil { throw SpeechFailure(.invalidEndpoint) }
            if credential.kind == .apiKey && credentialPolicy != .allowStaticKeys { throw SpeechFailure(.staticKeysDisallowed) }
            if credentialPolicy == .relayOnly { throw SpeechFailure(.unsupportedAuthentication) }
            config.setCredential(credential)
            return config
        }
        guard let relaySession else { throw SpeechFailure(.invalidEndpoint) }
        let model = capability == .fileTranscription ? config.modelID.rawValue : ""
        let route = try await relaySession.route(provider: .aqua, capability: capability, model: model,
                                                  allowVendorTokens: credentialPolicy != .relayOnly)
        try Task.checkCancellation()
        config.setCredential(route.credential)
        config.fileEndpoint = route.endpoint
        return config
    }

}
