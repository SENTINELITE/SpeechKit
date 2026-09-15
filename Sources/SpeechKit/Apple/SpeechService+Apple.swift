import Foundation

#if !os(watchOS)
/// Apple local Speech convenience APIs.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension SpeechService {
    var appleSpeechService: AppleSpeechService {
        if let service = appleRealtimeServiceStorage as? AppleSpeechService {
            return service
        }
        let service = AppleSpeechService()
        appleRealtimeServiceStorage = service
        return service
    }

    /// Prepares Apple's local speech assets for the configured or supplied locale.
    ///
    /// Call this ahead of a user-visible transcription flow when you want to
    /// separate model download time from recording or file analysis.
    ///
    /// - Parameter locale: An optional locale override. When omitted, SpeechKit
    ///   uses ``AppleSpeechConfiguration/locale`` from ``apple``.
    /// - Throws: ``SpeechError/appleSpeechUnavailable``,
    ///   ``SpeechError/appleSpeechUnsupportedLocale(localeIdentifier:)``, or
    ///   ``SpeechError/appleSpeechAssetsUnavailable(localeIdentifier:)`` when
    ///   Apple Speech cannot be prepared.
    public func prepareAppleSpeechAssets(locale: Locale? = nil) async throws {
        guard var configuration = apple else {
            throw SpeechError.providerNotConfigured(.apple)
        }
        if let locale {
            configuration.locale = locale
        }
        _ = try await AppleSpeechSupport.makeRealtimeTranscriber(configuration: configuration)
    }

    /// Transcribes an audio file with Apple's local Speech framework and returns detailed metadata.
    ///
    /// - Parameters:
    ///   - file: A local audio file URL.
    ///   - options: Per-request locale and asset handling overrides.
    /// - Returns: The transcript text and final entries normalized into
    ///   SpeechKit's shared transcript model.
    /// - Throws: ``SpeechError/providerNotConfigured(_:)`` when Apple Speech is
    ///   not configured, plus Apple Speech availability, locale, asset, and
    ///   file-reading errors.
    public func transcribeAppleAudioFile(
        file: URL,
        options: AppleSpeechFileTranscriptionOptions? = nil
    ) async throws -> AppleSpeechFileTranscriptionResponse {
        guard let apple else {
            throw SpeechError.providerNotConfigured(.apple)
        }
        let client = AppleSpeechFileTranscriptionClient()
        do {
            return try await client.transcribeAudioFileDetailed(
                file: file,
                configuration: apple,
                options: options
            )
        } catch {
            throw wrap(error, for: .apple)
        }
    }

    /// Transcribes a security-scoped audio file URL with Apple Speech and returns detailed metadata.
    ///
    /// - Parameters:
    ///   - securityScopedURL: A security-scoped file URL from an open panel,
    ///     document picker, or drag/drop handoff.
    ///   - options: Per-request locale and asset handling overrides.
    /// - Returns: The transcript text and final entries normalized into
    ///   SpeechKit's shared transcript model.
    public func transcribeAppleAudioFile(
        securityScopedURL: URL,
        options: AppleSpeechFileTranscriptionOptions? = nil
    ) async throws -> AppleSpeechFileTranscriptionResponse {
        let didStartAccess = securityScopedURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw SpeechError.providerFailure(provider: .apple, reason: "Failed to access security-scoped resource.")
        }
        defer { securityScopedURL.stopAccessingSecurityScopedResource() }
        return try await transcribeAppleAudioFile(file: securityScopedURL, options: options)
    }

    func startAppleListening() async {
        guard let apple else {
            fallbackConnectionState = .error("Apple Speech is not configured")
            fallbackLastError = SpeechError.realtimeProviderNotConfigured(.apple)
            return
        }

        fallbackConnectionState = nil
        fallbackLastError = nil
        await appleSpeechService.startListening(configuration: apple)
    }
}
#endif
