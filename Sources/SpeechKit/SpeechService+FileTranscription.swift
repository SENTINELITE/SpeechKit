import Foundation

extension SpeechService {
    /// Transcribes an audio file with a configured provider.
    ///
    /// - Throws: ``SpeechError`` when the provider is missing, options do not match the provider, upload validation fails, or the provider request fails.
    public func transcribeAudioFile(
        provider: SpeechFileTranscriptionProvider,
        file: URL,
        options: SpeechFileTranscriptionOptions? = nil
    ) async throws -> String {
        switch provider {
        case .elevenLabs:
            guard let elevenLabs else {
                throw SpeechError.providerNotConfigured(.elevenLabs)
            }
            try validate(options: options, for: .elevenLabs)
            let resolvedModelID = resolvedElevenLabsModelID(from: options, config: elevenLabs)
            let client = ElevenLabsFileTranscriptionClient(apiKey: elevenLabs.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(file: file, modelID: resolvedModelID)
            } catch {
                throw wrap(error, for: .elevenLabs)
            }

        case .aqua:
            guard let aqua else {
                throw SpeechError.providerNotConfigured(.aqua)
            }
            try validate(options: options, for: .aqua)
            let resolvedOptions = resolvedAquaOptions(from: options, config: aqua)
            let client = AquaFileTranscriptionClient(apiKey: aqua.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
            } catch {
                throw wrap(error, for: .aqua)
            }

        case .cohere:
            guard let cohere else {
                throw SpeechError.providerNotConfigured(.cohere)
            }
            try validate(options: options, for: .cohere)
            let resolvedOptions = resolvedCohereOptions(from: options, config: cohere)
            let client = CohereFileTranscriptionClient(apiKey: cohere.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(
                    file: file,
                    modelID: resolvedOptions.modelID,
                    language: resolvedOptions.language,
                    temperature: resolvedOptions.temperature
                )
            } catch {
                throw wrap(error, for: .cohere)
            }

        case .grok:
            guard let grok else {
                throw SpeechError.providerNotConfigured(.grok)
            }
            try validate(options: options, for: .grok)
            let resolvedOptions = resolvedGrokOptions(from: options, config: grok)
            let client = GrokFileTranscriptionClient(apiKey: grok.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(
                    file: file,
                    options: resolvedOptions
                )
            } catch {
                throw wrap(error, for: .grok)
            }

        case .openAI:
            guard let openAI else {
                throw SpeechError.providerNotConfigured(.openAI)
            }
            try validate(options: options, for: .openAI)
            let resolvedOptions = resolvedOpenAIOptions(from: options, config: openAI)
            let client = OpenAIFileTranscriptionClient(apiKey: openAI.apiKey, urlSession: urlSession)

            do {
                return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
            } catch {
                throw wrap(error, for: .openAI)
            }
        }
    }

    /// Transcribes a security-scoped audio file URL with a configured provider.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, the provider is missing, options do not match the provider, upload validation fails, or the provider request fails.
    public func transcribeAudioFile(
        provider: SpeechFileTranscriptionProvider,
        securityScopedURL: URL,
        options: SpeechFileTranscriptionOptions? = nil
    ) async throws -> String {
        let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw SpeechError.providerFailure(provider: provider, reason: "Failed to access security-scoped resource.")
        }
        defer { securityScopedURL.stopAccessingSecurityScopedResource() }
        return try await transcribeAudioFile(provider: provider, file: securityScopedURL, options: options)
    }

    /// Transcribes an audio file with Aqua and returns Aqua's detailed response.
    ///
    /// - Throws: ``SpeechError`` when Aqua is missing, upload validation fails, or the provider request fails.
    public func transcribeAquaAudioFile(
        file: URL,
        options: AquaFileTranscriptionOptions? = nil
    ) async throws -> AquaFileTranscriptionResponse {
        guard let aqua else {
            throw SpeechError.providerNotConfigured(.aqua)
        }

        let client = AquaFileTranscriptionClient(apiKey: aqua.apiKey, urlSession: urlSession)
        let resolvedOptions = options ?? AquaFileTranscriptionOptions(
            modelID: aqua.modelID,
            language: aqua.language
        )

        do {
            return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
        } catch {
            throw wrap(error, for: .aqua)
        }
    }

    /// Transcribes a security-scoped audio file URL with Aqua and returns Aqua's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Aqua is missing, upload validation fails, or the provider request fails.
    public func transcribeAquaAudioFile(
        securityScopedURL: URL,
        options: AquaFileTranscriptionOptions? = nil
    ) async throws -> AquaFileTranscriptionResponse {
        let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw SpeechError.providerFailure(provider: .aqua, reason: "Failed to access security-scoped resource.")
        }
        defer { securityScopedURL.stopAccessingSecurityScopedResource() }
        return try await transcribeAquaAudioFile(file: securityScopedURL, options: options)
    }

    /// Transcribes an audio file with Grok and returns Grok's detailed response.
    ///
    /// - Throws: ``SpeechError`` when Grok is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeGrokAudioFile(
        file: URL,
        options: GrokFileTranscriptionOptions? = nil
    ) async throws -> GrokFileTranscriptionResponse {
        guard let grok else {
            throw SpeechError.providerNotConfigured(.grok)
        }

        let client = GrokFileTranscriptionClient(apiKey: grok.apiKey, urlSession: urlSession)
        let resolvedOptions = options ?? GrokFileTranscriptionOptions(
            modelID: grok.modelID,
            language: grok.language,
            format: grok.format,
            multichannel: grok.multichannel,
            diarize: grok.diarize,
            timestampGranularities: grok.timestampGranularities,
            timeoutInterval: grok.timeoutInterval
        )

        do {
            return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
        } catch {
            throw wrap(error, for: .grok)
        }
    }

    /// Transcribes a security-scoped audio file URL with Grok and returns Grok's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Grok is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeGrokAudioFile(
        securityScopedURL: URL,
        options: GrokFileTranscriptionOptions? = nil
    ) async throws -> GrokFileTranscriptionResponse {
        let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw SpeechError.providerFailure(provider: .grok, reason: "Failed to access security-scoped resource.")
        }
        defer { securityScopedURL.stopAccessingSecurityScopedResource() }
        return try await transcribeGrokAudioFile(file: securityScopedURL, options: options)
    }

    /// Transcribes an audio file with OpenAI and returns OpenAI's detailed response.
    ///
    /// - Throws: ``SpeechError`` when OpenAI is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeOpenAIAudioFile(
        file: URL,
        options: OpenAIFileTranscriptionOptions? = nil
    ) async throws -> OpenAIFileTranscriptionResponse {
        guard let openAI else {
            throw SpeechError.providerNotConfigured(.openAI)
        }

        let client = OpenAIFileTranscriptionClient(apiKey: openAI.apiKey, urlSession: urlSession)
        let resolvedOptions = options ?? OpenAIFileTranscriptionOptions(
            modelID: openAI.fileTranscriptionModelID,
            language: openAI.language,
            prompt: openAI.prompt,
            temperature: openAI.temperature,
            diarizationChunkingStrategy: openAI.diarizationChunkingStrategy,
            knownSpeakers: openAI.knownSpeakers,
            timeoutInterval: openAI.timeoutInterval
        )

        do {
            return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
        } catch {
            throw wrap(error, for: .openAI)
        }
    }

    /// Transcribes a security-scoped audio file URL with OpenAI and returns OpenAI's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, OpenAI is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeOpenAIAudioFile(
        securityScopedURL: URL,
        options: OpenAIFileTranscriptionOptions? = nil
    ) async throws -> OpenAIFileTranscriptionResponse {
        let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw SpeechError.providerFailure(provider: .openAI, reason: "Failed to access security-scoped resource.")
        }
        defer { securityScopedURL.stopAccessingSecurityScopedResource() }
        return try await transcribeOpenAIAudioFile(file: securityScopedURL, options: options)
    }

    func validate(options: SpeechFileTranscriptionOptions?, for provider: SpeechFileTranscriptionProvider) throws {
        guard let options else { return }
        guard options.provider == provider else {
            throw SpeechError.invalidOptionsForProvider(expected: provider, received: options.provider)
        }
    }

    func resolvedElevenLabsModelID(
        from options: SpeechFileTranscriptionOptions?,
        config: ElevenLabsConfiguration
    ) -> ElevenLabsModelID {
        guard case .elevenLabs(let modelID) = options else {
            return config.fileTranscriptionModelID
        }
        return modelID ?? config.fileTranscriptionModelID
    }

    func resolvedAquaOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: AquaConfiguration
    ) -> AquaFileTranscriptionOptions {
        guard case .aqua(let modelID, let language) = options else {
            return AquaFileTranscriptionOptions(modelID: config.modelID, language: config.language)
        }

        return AquaFileTranscriptionOptions(
            modelID: modelID ?? config.modelID,
            language: language ?? config.language
        )
    }

    func resolvedCohereOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: CohereConfiguration
    ) -> (modelID: CohereModelID, language: CohereLanguage, temperature: Double?) {
        guard case .cohere(let modelID, let language, let temperature) = options else {
            return (config.modelID, config.language, config.temperature)
        }

        return (
            modelID ?? config.modelID,
            language ?? config.language,
            temperature ?? config.temperature
        )
    }

    func resolvedGrokOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: GrokConfiguration
    ) -> GrokFileTranscriptionOptions {
        guard case .grok(
            let modelID,
            let language,
            let format,
            let multichannel,
            let channels,
            let diarize,
            let timestampGranularities,
            let audioFormat,
            let sampleRate,
            let timeoutInterval
        ) = options else {
            return GrokFileTranscriptionOptions(
                modelID: config.modelID,
                language: config.language,
                format: config.format,
                multichannel: config.multichannel,
                channels: nil,
                diarize: config.diarize,
                timestampGranularities: config.timestampGranularities,
                audioFormat: nil,
                sampleRate: nil,
                timeoutInterval: config.timeoutInterval
            )
        }

        return GrokFileTranscriptionOptions(
            modelID: modelID ?? config.modelID,
            language: language ?? config.language,
            format: format ?? config.format,
            multichannel: multichannel ?? config.multichannel,
            channels: channels,
            diarize: diarize ?? config.diarize,
            timestampGranularities: timestampGranularities ?? config.timestampGranularities,
            audioFormat: audioFormat,
            sampleRate: sampleRate,
            timeoutInterval: timeoutInterval ?? config.timeoutInterval
        )
    }

    func resolvedOpenAIOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: OpenAIConfiguration
    ) -> OpenAIFileTranscriptionOptions {
        guard case .openAI(
            let modelID,
            let language,
            let prompt,
            let temperature,
            let includeLogprobs,
            let timestampGranularities,
            let diarizationChunkingStrategy,
            let knownSpeakers,
            let timeoutInterval
        ) = options else {
            return OpenAIFileTranscriptionOptions(
                modelID: config.fileTranscriptionModelID,
                language: config.language,
                prompt: config.prompt,
                temperature: config.temperature,
                diarizationChunkingStrategy: config.diarizationChunkingStrategy,
                knownSpeakers: config.knownSpeakers,
                timeoutInterval: config.timeoutInterval
            )
        }

        return OpenAIFileTranscriptionOptions(
            modelID: modelID ?? config.fileTranscriptionModelID,
            language: language ?? config.language,
            prompt: prompt ?? config.prompt,
            temperature: temperature ?? config.temperature,
            includeLogprobs: includeLogprobs ?? false,
            timestampGranularities: timestampGranularities ?? [],
            diarizationChunkingStrategy: diarizationChunkingStrategy ?? config.diarizationChunkingStrategy,
            knownSpeakers: knownSpeakers ?? config.knownSpeakers,
            timeoutInterval: timeoutInterval ?? config.timeoutInterval
        )
    }

    func wrap(_ error: Error, for provider: SpeechFileTranscriptionProvider) -> SpeechError {
        if let speechError = error as? SpeechError {
            return speechError
        }

        if let urlError = error as? URLError {
            if urlError.code == .timedOut {
                return .providerFailure(provider: provider, reason: "The request timed out. Try a shorter audio file or increase the provider timeout.")
            }
            return .providerFailure(provider: provider, reason: urlError.localizedDescription)
        }

        if let elevenLabsError = error as? ElevenLabsError {
            switch elevenLabsError {
            case .decodingFailed(let reason):
                return .decodingFailed(provider: provider, reason: reason)
            case .uploadFailed(let reason), .connectionFailed(let reason):
                return .uploadFailed(provider: provider, reason: reason)
            default:
                return .providerFailure(provider: provider, reason: elevenLabsError.localizedDescription)
            }
        }

        return .providerFailure(provider: provider, reason: error.localizedDescription)
    }
}
