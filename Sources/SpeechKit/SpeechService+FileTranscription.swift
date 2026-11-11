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
        return try await withFileOperation { [self] in
            switch provider {
            case .elevenLabs:
                guard let elevenLabs = try await resolvedElevenLabsConfiguration(capability: .fileTranscription) else {
                    throw SpeechError.providerNotConfigured(.elevenLabs)
                }
                try validate(options: options, for: .elevenLabs)
                let resolvedOptions = resolvedElevenLabsOptions(from: options, config: elevenLabs)
                let client = ElevenLabsFileTranscriptionClient(
                    credential: elevenLabs.credential,
                    endpoint: elevenLabs.fileEndpoint,
                    urlSession: urlSession
                )

                do {
                    return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
                } catch {
                    throw wrap(error, for: .elevenLabs)
                }

            case .aqua:
                guard let aqua = try await resolvedAquaConfiguration(capability: .fileTranscription) else {
                    throw SpeechError.providerNotConfigured(.aqua)
                }
                try validate(options: options, for: .aqua)
                let resolvedOptions = resolvedAquaOptions(from: options, config: aqua)
                let client = AquaFileTranscriptionClient(credential: aqua.credential, endpoint: aqua.fileEndpoint, urlSession: urlSession)

                do {
                    return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
                } catch {
                    throw wrap(error, for: .aqua)
                }

            case .cohere:
                guard let cohere = try await resolvedCohereConfiguration(capability: .fileTranscription) else {
                    throw SpeechError.providerNotConfigured(.cohere)
                }
                try validate(options: options, for: .cohere)
                let resolvedOptions = resolvedCohereOptions(from: options, config: cohere)
                let client = CohereFileTranscriptionClient(
                    credential: cohere.credential, endpoint: cohere.fileEndpoint, urlSession: urlSession)

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
                guard let grok = try await resolvedGrokConfiguration(capability: .fileTranscription) else {
                    throw SpeechError.providerNotConfigured(.grok)
                }
                try validate(options: options, for: .grok)
                let resolvedOptions = resolvedGrokOptions(from: options, config: grok)
                let client = GrokFileTranscriptionClient(credential: grok.credential, endpoint: grok.fileEndpoint, urlSession: urlSession)

                do {
                    return try await client.transcribeAudioFile(
                        file: file,
                        options: resolvedOptions
                    )
                } catch {
                    throw wrap(error, for: .grok)
                }

            case .openAI:
                guard let openAI = try await resolvedOpenAIConfiguration(capability: .fileTranscription) else {
                    throw SpeechError.providerNotConfigured(.openAI)
                }
                try validate(options: options, for: .openAI)
                let resolvedOptions = resolvedOpenAIOptions(from: options, config: openAI)
                let client = OpenAIFileTranscriptionClient(
                    credential: openAI.credential, endpoint: openAI.fileEndpoint, urlSession: urlSession)

                do {
                    return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
                } catch {
                    throw wrap(error, for: .openAI)
                }

            case .meta:
                guard let meta = try await resolvedMetaConfiguration(capability: .fileTranscription) else {
                    throw SpeechError.providerNotConfigured(.meta)
                }
                try validate(options: options, for: .meta)
                let resolvedOptions = resolvedMetaOptions(from: options, config: meta)
                let client = MetaFileTranscriptionClient(credential: meta.credential, endpoint: meta.fileEndpoint, urlSession: urlSession)

                do {
                    return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
                } catch {
                    throw wrap(error, for: .meta)
                }

            case .gemini:
                guard let gemini = try await resolvedGeminiConfiguration(capability: .fileTranscription) else {
                    throw SpeechError.providerNotConfigured(.gemini)
                }
                try validate(options: options, for: .gemini)
                let resolvedOptions = resolvedGeminiOptions(from: options, config: gemini)
                let client = GeminiFileTranscriptionClient(
                    credential: gemini.credential,
                    endpoint: gemini.fileEndpoint,
                    filesEndpoint: gemini.filesEndpoint,
                    routeOriginPolicy: gemini.routeOriginPolicy,
                    urlSession: urlSession
                )

                do {
                    return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
                } catch {
                    throw wrap(error, for: .gemini)
                }

            case .mistral:
                guard let mistral = try await resolvedMistralConfiguration(capability: .fileTranscription) else {
                    throw SpeechError.providerNotConfigured(.mistral)
                }
                try validate(options: options, for: .mistral)
                let resolvedOptions = resolvedMistralOptions(from: options, config: mistral)
                let client = MistralFileTranscriptionClient(
                    credential: mistral.credential,
                    endpoint: mistral.fileEndpoint,
                    urlSession: urlSession
                )

                do {
                    return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
                } catch {
                    throw wrap(error, for: .mistral)
                }

            case .fishAudio:
                guard let fishAudio = try await resolvedFishAudioConfiguration(capability: .fileTranscription) else {
                    throw SpeechError.providerNotConfigured(.fishAudio)
                }
                try validate(options: options, for: .fishAudio)
                let resolvedOptions = resolvedFishAudioOptions(from: options, config: fishAudio)
                let client = FishAudioFileTranscriptionClient(
                    credential: fishAudio.credential,
                    endpoint: fishAudio.fileEndpoint,
                    urlSession: urlSession
                )

                do {
                    return try await client.transcribeAudioFile(file: file, options: resolvedOptions)
                } catch {
                    throw wrap(error, for: .fishAudio)
                }

            #if !os(watchOS)
                case .apple:
                    if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                        guard let apple else {
                            throw SpeechError.providerNotConfigured(.apple)
                        }
                        try validate(options: options, for: .apple)
                        let resolvedOptions = resolvedAppleOptions(from: options)
                        let client = AppleSpeechFileTranscriptionClient()

                        do {
                            return try await client.transcribeAudioFile(
                                file: file,
                                configuration: apple,
                                options: resolvedOptions
                            )
                        } catch {
                            throw wrap(error, for: .apple)
                        }
                    } else {
                        throw SpeechError.appleSpeechUnavailable
                    }
            #endif
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
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: provider, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeAudioFile(provider: provider, file: securityScopedURL, options: options)
        }
    }

    /// Transcribes an audio file with ElevenLabs and returns ElevenLabs's detailed response.
    ///
    /// Set ``ElevenLabsFileTranscriptionOptions/diarize`` to label each word
    /// with its speaker, and ``ElevenLabsFileTranscriptionOptions/entityDetection``
    /// to collect detected entities.
    ///
    /// - Throws: ``SpeechError`` when ElevenLabs is missing, option validation fails, or the provider request fails.
    public func transcribeElevenLabsAudioFile(
        file: URL,
        options: ElevenLabsFileTranscriptionOptions? = nil
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            guard let elevenLabs = try await resolvedElevenLabsConfiguration(capability: .fileTranscription) else {
                throw SpeechError.providerNotConfigured(.elevenLabs)
            }

            let resolvedOptions = options ?? resolvedElevenLabsOptions(from: nil, config: elevenLabs)
            return try await transcribeElevenLabsAudioFileDetailed(file: file, options: resolvedOptions, config: elevenLabs)
        }
    }

    /// Transcribes an audio file with ElevenLabs and returns ElevenLabs's detailed response.
    ///
    /// This overload keeps the model-only call shape; use the `options:` overload for the full option set.
    ///
    /// - Throws: ``SpeechError`` when ElevenLabs is missing, option validation fails, or the provider request fails.
    public func transcribeElevenLabsAudioFile(
        file: URL,
        modelID: ElevenLabsModelID?
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            guard let elevenLabs = try await resolvedElevenLabsConfiguration(capability: .fileTranscription) else {
                throw SpeechError.providerNotConfigured(.elevenLabs)
            }
            var options = resolvedElevenLabsOptions(from: nil, config: elevenLabs)
            if let modelID {
                options.modelID = modelID
            }
            return try await transcribeElevenLabsAudioFileDetailed(file: file, options: options, config: elevenLabs)
        }
    }

    /// Transcribes a security-scoped audio file URL with ElevenLabs and returns ElevenLabs's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, ElevenLabs is missing, option validation fails, or the provider request fails.
    public func transcribeElevenLabsAudioFile(
        securityScopedURL: URL,
        options: ElevenLabsFileTranscriptionOptions? = nil
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: .elevenLabs, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeElevenLabsAudioFile(file: securityScopedURL, options: options)
        }
    }

    /// Transcribes a security-scoped audio file URL with ElevenLabs and returns ElevenLabs's detailed response.
    ///
    /// This overload keeps the model-only call shape; use the `options:` overload for the full option set.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, ElevenLabs is missing, option validation fails, or the provider request fails.
    public func transcribeElevenLabsAudioFile(
        securityScopedURL: URL,
        modelID: ElevenLabsModelID?
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: .elevenLabs, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeElevenLabsAudioFile(file: securityScopedURL, modelID: modelID)
        }
    }

    /// Runs a detailed ElevenLabs upload inside an active file operation.
    private func transcribeElevenLabsAudioFileDetailed(
        file: URL,
        options: ElevenLabsFileTranscriptionOptions,
        config: ElevenLabsConfiguration
    ) async throws -> ElevenLabsFileTranscriptionResponse {
        let client = ElevenLabsFileTranscriptionClient(
            credential: config.credential,
            endpoint: config.fileEndpoint,
            urlSession: urlSession
        )
        do {
            return try await client.transcribeAudioFileDetailed(file: file, options: options)
        } catch {
            throw wrap(error, for: .elevenLabs)
        }
    }

    /// Transcribes an audio file with Aqua and returns Aqua's detailed response.
    ///
    /// - Throws: ``SpeechError`` when Aqua is missing, upload validation fails, or the provider request fails.
    public func transcribeAquaAudioFile(
        file: URL,
        options: AquaFileTranscriptionOptions? = nil
    ) async throws -> AquaFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            guard let aqua = try await resolvedAquaConfiguration(capability: .fileTranscription) else {
                throw SpeechError.providerNotConfigured(.aqua)
            }

            let client = AquaFileTranscriptionClient(credential: aqua.credential, endpoint: aqua.fileEndpoint, urlSession: urlSession)
            let resolvedOptions =
                options
                ?? AquaFileTranscriptionOptions(
                    modelID: aqua.modelID,
                    language: aqua.language
                )

            do {
                return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
            } catch {
                throw wrap(error, for: .aqua)
            }
        }
    }

    /// Transcribes a security-scoped audio file URL with Aqua and returns Aqua's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Aqua is missing, upload validation fails, or the provider request fails.
    public func transcribeAquaAudioFile(
        securityScopedURL: URL,
        options: AquaFileTranscriptionOptions? = nil
    ) async throws -> AquaFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: .aqua, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeAquaAudioFile(file: securityScopedURL, options: options)
        }
    }

    /// Transcribes an audio file with Grok and returns Grok's detailed response.
    ///
    /// - Throws: ``SpeechError`` when Grok is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeGrokAudioFile(
        file: URL,
        options: GrokFileTranscriptionOptions? = nil
    ) async throws -> GrokFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            guard let grok = try await resolvedGrokConfiguration(capability: .fileTranscription) else {
                throw SpeechError.providerNotConfigured(.grok)
            }

            let client = GrokFileTranscriptionClient(credential: grok.credential, endpoint: grok.fileEndpoint, urlSession: urlSession)
            let resolvedOptions =
                options
                ?? GrokFileTranscriptionOptions(
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
    }

    /// Transcribes a security-scoped audio file URL with Grok and returns Grok's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Grok is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeGrokAudioFile(
        securityScopedURL: URL,
        options: GrokFileTranscriptionOptions? = nil
    ) async throws -> GrokFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: .grok, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeGrokAudioFile(file: securityScopedURL, options: options)
        }
    }

    /// Transcribes an audio file with OpenAI and returns OpenAI's detailed response.
    ///
    /// - Throws: ``SpeechError`` when OpenAI is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeOpenAIAudioFile(
        file: URL,
        options: OpenAIFileTranscriptionOptions? = nil
    ) async throws -> OpenAIFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            guard let openAI = try await resolvedOpenAIConfiguration(capability: .fileTranscription) else {
                throw SpeechError.providerNotConfigured(.openAI)
            }

            let client = OpenAIFileTranscriptionClient(credential: openAI.credential, endpoint: openAI.fileEndpoint, urlSession: urlSession)
            let resolvedOptions =
                options
                ?? OpenAIFileTranscriptionOptions(
                    modelID: openAI.fileTranscriptionModelID,
                    language: openAI.language,
                    languages: openAI.languages,
                    prompt: openAI.prompt,
                    keywords: openAI.keywords,
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
    }

    /// Transcribes a security-scoped audio file URL with OpenAI and returns OpenAI's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, OpenAI is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeOpenAIAudioFile(
        securityScopedURL: URL,
        options: OpenAIFileTranscriptionOptions? = nil
    ) async throws -> OpenAIFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: .openAI, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeOpenAIAudioFile(file: securityScopedURL, options: options)
        }
    }

    /// Transcribes an audio file with Meta and returns Meta's detailed response.
    ///
    /// - Throws: ``SpeechError`` when Meta is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeMetaAudioFile(
        file: URL,
        options: MetaFileTranscriptionOptions? = nil
    ) async throws -> MetaFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            guard let meta = try await resolvedMetaConfiguration(capability: .fileTranscription) else {
                throw SpeechError.providerNotConfigured(.meta)
            }

            let client = MetaFileTranscriptionClient(credential: meta.credential, endpoint: meta.fileEndpoint, urlSession: urlSession)
            let resolvedOptions =
                options
                ?? MetaFileTranscriptionOptions(
                    modelID: meta.modelID,
                    mode: meta.mode,
                    languageBias: meta.languageBias,
                    keywords: meta.keywords,
                    timeoutInterval: meta.timeoutInterval
                )

            do {
                return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
            } catch {
                throw wrap(error, for: .meta)
            }
        }
    }

    /// Transcribes a security-scoped audio file URL with Meta and returns Meta's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Meta is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeMetaAudioFile(
        securityScopedURL: URL,
        options: MetaFileTranscriptionOptions? = nil
    ) async throws -> MetaFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: .meta, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeMetaAudioFile(file: securityScopedURL, options: options)
        }
    }

    /// Transcribes an audio file with Gemini and returns Gemini's detailed response.
    ///
    /// - Throws: ``SpeechError`` when Gemini is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeGeminiAudioFile(
        file: URL,
        options: GeminiFileTranscriptionOptions? = nil
    ) async throws -> GeminiFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            guard let gemini = try await resolvedGeminiConfiguration(capability: .fileTranscription) else {
                throw SpeechError.providerNotConfigured(.gemini)
            }

            let client = GeminiFileTranscriptionClient(
                credential: gemini.credential,
                endpoint: gemini.fileEndpoint,
                filesEndpoint: gemini.filesEndpoint,
                    routeOriginPolicy: gemini.routeOriginPolicy,
                urlSession: urlSession
            )
            let resolvedOptions =
                options
                ?? GeminiFileTranscriptionOptions(
                    modelID: gemini.fileTranscriptionModelID,
                    languageCodes: gemini.languageCodes,
                    customVocabulary: gemini.customVocabulary,
                    mode: gemini.mode,
                    diarize: gemini.diarize,
                    timestampGranularities: gemini.timestampGranularities,
                    uploadStrategy: gemini.uploadStrategy,
                    processingMode: gemini.processingMode,
                    timeoutInterval: gemini.timeoutInterval
                )

            do {
                return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
            } catch {
                throw wrap(error, for: .gemini)
            }
        }
    }

    /// Transcribes a security-scoped audio file URL with Gemini and returns Gemini's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Gemini is missing, upload validation fails, option validation fails, or the provider request fails.
    public func transcribeGeminiAudioFile(
        securityScopedURL: URL,
        options: GeminiFileTranscriptionOptions? = nil
    ) async throws -> GeminiFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: .gemini, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeGeminiAudioFile(file: securityScopedURL, options: options)
        }
    }

    /// Transcribes an audio file with Mistral and returns Mistral's detailed response.
    ///
    /// Set ``MistralFileTranscriptionOptions/diarize`` to label each segment
    /// with its speaker.
    ///
    /// - Throws: ``SpeechError`` when Mistral is missing, option validation fails, or the provider request fails.
    public func transcribeMistralAudioFile(
        file: URL,
        options: MistralFileTranscriptionOptions? = nil
    ) async throws -> MistralFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            guard let mistral = try await resolvedMistralConfiguration(capability: .fileTranscription) else {
                throw SpeechError.providerNotConfigured(.mistral)
            }

            let client = MistralFileTranscriptionClient(
                credential: mistral.credential,
                endpoint: mistral.fileEndpoint,
                urlSession: urlSession
            )
            let resolvedOptions = options ?? resolvedMistralOptions(from: nil, config: mistral)

            do {
                return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
            } catch {
                throw wrap(error, for: .mistral)
            }
        }
    }

    /// Transcribes a security-scoped audio file URL with Mistral and returns Mistral's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Mistral is missing, option validation fails, or the provider request fails.
    public func transcribeMistralAudioFile(
        securityScopedURL: URL,
        options: MistralFileTranscriptionOptions? = nil
    ) async throws -> MistralFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: .mistral, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeMistralAudioFile(file: securityScopedURL, options: options)
        }
    }

    /// Transcribes an audio file with Fish Audio and returns Fish Audio's detailed response.
    ///
    /// The response keeps Fish Audio's raw text, segments, and speaker turns.
    /// Use ``FishAudioFileTranscriptionResponse/transcriptText`` for text
    /// without speaker markers, and ``FishAudioFileTranscriptionResponse/words``
    /// for punctuated words labelled with their speaker.
    ///
    /// Fish Audio rejects AIFF and CAF audio and files longer than 60 minutes,
    /// so SpeechKit checks both before uploading.
    ///
    /// - Throws: ``SpeechError`` when Fish Audio is missing, option or file validation fails, or the provider request fails.
    public func transcribeFishAudioAudioFile(
        file: URL,
        options: FishAudioFileTranscriptionOptions? = nil
    ) async throws -> FishAudioFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            guard let fishAudio = try await resolvedFishAudioConfiguration(capability: .fileTranscription) else {
                throw SpeechError.providerNotConfigured(.fishAudio)
            }

            let client = FishAudioFileTranscriptionClient(
                credential: fishAudio.credential,
                endpoint: fishAudio.fileEndpoint,
                urlSession: urlSession
            )
            let resolvedOptions = options ?? resolvedFishAudioOptions(from: nil, config: fishAudio)

            do {
                return try await client.transcribeAudioFileDetailed(file: file, options: resolvedOptions)
            } catch {
                throw wrap(error, for: .fishAudio)
            }
        }
    }

    /// Transcribes a security-scoped audio file URL with Fish Audio and returns Fish Audio's detailed response.
    ///
    /// - Throws: ``SpeechError`` when the file cannot be accessed, Fish Audio is missing, option or file validation fails, or the provider request fails.
    public func transcribeFishAudioAudioFile(
        securityScopedURL: URL,
        options: FishAudioFileTranscriptionOptions? = nil
    ) async throws -> FishAudioFileTranscriptionResponse {
        return try await withFileOperation { [self] in
            let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
            guard didStartAccess else {
                throw SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)
            }
            defer { securityScopedURL.stopAccessingSecurityScopedResource() }
            return try await transcribeFishAudioAudioFile(file: securityScopedURL, options: options)
        }
    }

    func validate(options: SpeechFileTranscriptionOptions?, for provider: SpeechFileTranscriptionProvider) throws {
        guard let options else { return }
        guard options.provider == provider else {
            throw SpeechError.invalidOptionsForProvider(expected: provider, received: options.provider)
        }
    }

    /// The ElevenLabs file options a request implies.
    ///
    /// ``ElevenLabsConfiguration/fileTranscriptionModelID`` is the single
    /// source of truth for the model; every other field merges the request's
    /// overrides over ``ElevenLabsConfiguration/fileOptions``.
    func resolvedElevenLabsOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: ElevenLabsConfiguration
    ) -> ElevenLabsFileTranscriptionOptions {
        var resolved = config.fileOptions
        resolved.modelID = config.fileTranscriptionModelID
        guard
            case .elevenLabs(
                let modelID,
                let language,
                let secondaryLanguages,
                let numbersFormat,
                let diarize,
                let speakerCount,
                let diarizationThreshold,
                let keyterms,
                let tagAudioEvents,
                let noVerbatim,
                let entityDetection,
                let timeoutInterval
            ) = options
        else {
            return resolved
        }

        resolved.modelID = modelID ?? config.fileTranscriptionModelID
        resolved.language = language ?? resolved.language
        resolved.secondaryLanguages = secondaryLanguages ?? resolved.secondaryLanguages
        resolved.numbersFormat = numbersFormat ?? resolved.numbersFormat
        resolved.diarize = diarize ?? resolved.diarize
        resolved.speakerCount = speakerCount ?? resolved.speakerCount
        resolved.diarizationThreshold = diarizationThreshold ?? resolved.diarizationThreshold
        resolved.keyterms = keyterms ?? resolved.keyterms
        resolved.tagAudioEvents = tagAudioEvents ?? resolved.tagAudioEvents
        resolved.noVerbatim = noVerbatim ?? resolved.noVerbatim
        resolved.entityDetection = entityDetection ?? resolved.entityDetection
        resolved.timeoutInterval = timeoutInterval ?? resolved.timeoutInterval
        return resolved
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
        guard
            case .grok(
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
            ) = options
        else {
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
        guard
            case .openAI(
                let modelID,
                let language,
                let languages,
                let prompt,
                let keywords,
                let temperature,
                let includeLogprobs,
                let timestampGranularities,
                let diarizationChunkingStrategy,
                let knownSpeakers,
                let timeoutInterval
            ) = options
        else {
            return OpenAIFileTranscriptionOptions(
                modelID: config.fileTranscriptionModelID,
                language: config.language,
                languages: config.languages,
                prompt: config.prompt,
                keywords: config.keywords,
                temperature: config.temperature,
                diarizationChunkingStrategy: config.diarizationChunkingStrategy,
                knownSpeakers: config.knownSpeakers,
                timeoutInterval: config.timeoutInterval
            )
        }

        return OpenAIFileTranscriptionOptions(
            modelID: modelID ?? config.fileTranscriptionModelID,
            language: language ?? config.language,
            languages: languages ?? config.languages,
            prompt: prompt ?? config.prompt,
            keywords: keywords ?? config.keywords,
            temperature: temperature ?? config.temperature,
            includeLogprobs: includeLogprobs ?? false,
            timestampGranularities: timestampGranularities ?? [],
            diarizationChunkingStrategy: diarizationChunkingStrategy ?? config.diarizationChunkingStrategy,
            knownSpeakers: knownSpeakers ?? config.knownSpeakers,
            timeoutInterval: timeoutInterval ?? config.timeoutInterval
        )
    }

    func resolvedMetaOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: MetaConfiguration
    ) -> MetaFileTranscriptionOptions {
        guard
            case .meta(
                let modelID,
                let mode,
                let languageBias,
                let keywords,
                let sessionID,
                let timeoutInterval
            ) = options
        else {
            return MetaFileTranscriptionOptions(
                modelID: config.modelID,
                mode: config.mode,
                languageBias: config.languageBias,
                keywords: config.keywords,
                timeoutInterval: config.timeoutInterval
            )
        }

        return MetaFileTranscriptionOptions(
            modelID: modelID ?? config.modelID,
            mode: mode ?? config.mode,
            languageBias: languageBias ?? config.languageBias,
            keywords: keywords ?? config.keywords,
            sessionID: sessionID,
            timeoutInterval: timeoutInterval ?? config.timeoutInterval
        )
    }

    func resolvedGeminiOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: GeminiConfiguration
    ) -> GeminiFileTranscriptionOptions {
        guard
            case .gemini(
                let modelID,
                let languageCodes,
                let customVocabulary,
                let mode,
                let diarize,
                let timestampGranularities,
                let uploadStrategy,
                let processingMode,
                let timeoutInterval
            ) = options
        else {
            return GeminiFileTranscriptionOptions(
                modelID: config.fileTranscriptionModelID,
                languageCodes: config.languageCodes,
                customVocabulary: config.customVocabulary,
                mode: config.mode,
                diarize: config.diarize,
                timestampGranularities: config.timestampGranularities,
                uploadStrategy: config.uploadStrategy,
                processingMode: config.processingMode,
                timeoutInterval: config.timeoutInterval
            )
        }

        return GeminiFileTranscriptionOptions(
            modelID: modelID ?? config.fileTranscriptionModelID,
            languageCodes: languageCodes ?? config.languageCodes,
            customVocabulary: customVocabulary ?? config.customVocabulary,
            mode: mode ?? config.mode,
            diarize: diarize ?? config.diarize,
            timestampGranularities: timestampGranularities ?? config.timestampGranularities,
            uploadStrategy: uploadStrategy ?? config.uploadStrategy,
            processingMode: processingMode ?? config.processingMode,
            timeoutInterval: timeoutInterval ?? config.timeoutInterval
        )
    }

    func resolvedMistralOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: MistralConfiguration
    ) -> MistralFileTranscriptionOptions {
        guard
            case .mistral(
                let modelID,
                let language,
                let contextBias,
                let diarize,
                let timestampGranularities,
                let temperature,
                let timeoutInterval
            ) = options
        else {
            return MistralFileTranscriptionOptions(
                modelID: config.fileTranscriptionModelID,
                language: config.language,
                contextBias: config.contextBias,
                diarize: config.diarize,
                timestampGranularities: config.timestampGranularities,
                temperature: config.temperature,
                timeoutInterval: config.timeoutInterval
            )
        }

        return MistralFileTranscriptionOptions(
            modelID: modelID ?? config.fileTranscriptionModelID,
            language: language ?? config.language,
            contextBias: contextBias ?? config.contextBias,
            diarize: diarize ?? config.diarize,
            timestampGranularities: timestampGranularities ?? config.timestampGranularities,
            temperature: temperature ?? config.temperature,
            timeoutInterval: timeoutInterval ?? config.timeoutInterval
        )
    }

    func resolvedFishAudioOptions(
        from options: SpeechFileTranscriptionOptions?,
        config: FishAudioConfiguration
    ) -> FishAudioFileTranscriptionOptions {
        guard
            case .fishAudio(
                let modelID,
                let language,
                let timestamps,
                let diarize,
                let speakerCount,
                let tagAudioEvents,
                let timeoutInterval
            ) = options
        else {
            return FishAudioFileTranscriptionOptions(
                modelID: config.fileTranscriptionModelID,
                language: config.language,
                timestamps: config.timestamps,
                diarize: config.diarize,
                speakerCount: config.speakerCount,
                tagAudioEvents: config.tagAudioEvents,
                timeoutInterval: config.timeoutInterval
            )
        }

        return FishAudioFileTranscriptionOptions(
            modelID: modelID ?? config.fileTranscriptionModelID,
            language: language ?? config.language,
            timestamps: timestamps ?? config.timestamps,
            diarize: diarize ?? config.diarize,
            speakerCount: speakerCount ?? config.speakerCount,
            tagAudioEvents: tagAudioEvents ?? config.tagAudioEvents,
            timeoutInterval: timeoutInterval ?? config.timeoutInterval
        )
    }

    #if !os(watchOS)
        @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
        @available(watchOS, unavailable)
        func resolvedAppleOptions(
            from options: SpeechFileTranscriptionOptions?
        ) -> AppleSpeechFileTranscriptionOptions? {
            guard case .apple(let locale, let preparesAssetsAutomatically) = options else {
                return nil
            }

            return AppleSpeechFileTranscriptionOptions(
                locale: locale,
                preparesAssetsAutomatically: preparesAssetsAutomatically
            )
        }
    #endif

    func wrap(_ error: Error, for provider: SpeechFileTranscriptionProvider) -> Error {
        if error is CancellationError { return error }
        if let speechError = error as? SpeechError { return speechError }
        if let failure = error as? SpeechFailure {
            if failure.category != .server { return failure }
            if let status = failure.statusCode { return SpeechError.httpFailure(provider: provider, statusCode: status) }
            return failure
        }
        return SpeechError.providerFailure(provider: provider, reason: .requestFailed)
    }
}
