import DeviceCheck
import Foundation
import Observation
import SpeechKit

enum DemoRelayAuthentication: String, CaseIterable, Identifiable {
    case appAttest, bearer, none
    var id: Self { self }
    var title: String {
        switch self {
        case .appAttest: "App Attest"
        case .bearer: "Bearer token, test only"
        case .none: "None, development only"
        }
    }
}

/// Named latency/accuracy tiers exposed by the OpenAI realtime transcription demo.
enum DemoOpenAIRealtimeDelay: String, CaseIterable, Identifiable {
    case minimal
    case low
    case medium
    case high
    case xhigh

    var id: Self { self }

    var speechKitValue: OpenAIRealtimeDelay {
        switch self {
        case .minimal: .minimal
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .xhigh: .xhigh
        }
    }
}

/// Target streaming delays exposed by the Mistral realtime transcription demo.
///
/// Mistral accepts 80 to 1200 ms, or 2400 ms; these are a few useful stops.
enum DemoMistralStreamingDelay: String, CaseIterable, Identifiable {
    case providerDefault
    case ms240
    case ms480
    case ms960
    case ms2400

    var id: Self { self }

    var title: String {
        switch self {
        case .providerDefault: "Default"
        case .ms240: "240 ms"
        case .ms480: "480 ms"
        case .ms960: "960 ms"
        case .ms2400: "2400 ms"
        }
    }

    /// The delay sent to Mistral, or `nil` to keep Mistral's default.
    var milliseconds: Int? {
        switch self {
        case .providerDefault: nil
        case .ms240: 240
        case .ms480: 480
        case .ms960: 960
        case .ms2400: 2400
        }
    }
}

/// How Scribe v3 writes numbers, exposed by the ElevenLabs file settings.
enum DemoElevenLabsNumbersFormat: String, CaseIterable, Identifiable {
    case automatic
    case digits
    case words

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .digits: "Digits"
        case .words: "Words"
        }
    }

    /// The format sent to ElevenLabs, or `nil` to let the model choose.
    var speechKitValue: ElevenLabsNumbersFormat? {
        switch self {
        case .automatic: nil
        case .digits: .digits
        case .words: .words
        }
    }
}

/// Commit strategies exposed by the ElevenLabs realtime settings.
enum DemoElevenLabsCommitStrategy: String, CaseIterable, Identifiable {
    case automatic
    case turnPrediction
    case vad
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .turnPrediction: "Turn prediction"
        case .vad: "Voice activity"
        case .manual: "Manual"
        }
    }

    var speechKitValue: ElevenLabsCommitStrategy {
        switch self {
        case .automatic: .automatic
        case .turnPrediction: .turnPrediction
        case .vad: .vad
        case .manual: .manual
        }
    }
}

/// Apple's on-device `SpeechAnalyzer` needs iOS 26; the demo still runs on iOS 18.
enum DemoAppleSpeech {
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }
}

/// How long Apple's speech models stay loaded after analysis.
enum DemoAppleModelRetention: String, CaseIterable, Identifiable {
    case whileInUse
    case lingering
    case processLifetime

    var id: Self { self }

    var title: String {
        switch self {
        case .whileInUse: "While in use"
        case .lingering: "Linger briefly"
        case .processLifetime: "Until the app quits"
        }
    }

    @available(iOS 26.0, *)
    var speechKitValue: AppleSpeechModelRetention {
        switch self {
        case .whileInUse: .whileInUse
        case .lingering: .lingering
        case .processLifetime: .processLifetime
        }
    }
}

/// File-transcription providers exposed by the demo app.
enum DemoFileProvider: String, CaseIterable, Identifiable {
    case elevenLabs
    case aqua
    case cohere
    case grok
    case openAI
    case meta
    case gemini
    case mistral
    case fishAudio
    case voz
    case apple

    var id: Self { self }

    /// The providers callable on this OS; Apple needs iOS 26.
    static var allCases: [DemoFileProvider] {
        let providers: [DemoFileProvider] = [.elevenLabs, .aqua, .cohere, .grok, .openAI, .meta, .gemini, .mistral, .fishAudio, .voz, .apple]
        return DemoAppleSpeech.isAvailable ? providers : providers.filter { $0 != .apple }
    }

    /// Whether this provider transcribes on the device instead of uploading audio.
    var isOnDevice: Bool {
        self == .voz || self == .apple
    }

    /// The display name shown in menus and settings.
    var title: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .aqua: "Aqua"
        case .cohere: "Cohere"
        case .grok: "Grok"
        case .openAI: "OpenAI"
        case .meta: "Meta"
        case .gemini: "Gemini"
        case .mistral: "Mistral"
        case .fishAudio: "Fish Audio"
        case .voz: "VOZ (On Device)"
        case .apple: "Apple (On Device)"
        }
    }

    /// The SpeechKit provider value used when making a file-transcription request, or `nil` for
    /// VOZ, which transcribes through the SpeechKitVoz extension instead.
    var speechProvider: SpeechFileTranscriptionProvider? {
        switch self {
        case .elevenLabs: .elevenLabs
        case .aqua: .aqua
        case .cohere: .cohere
        case .grok: .grok
        case .openAI: .openAI
        case .meta: .meta
        case .gemini: .gemini
        case .mistral: .mistral
        case .fishAudio: .fishAudio
        case .voz: nil
        case .apple: .apple
        }
    }

    /// Whether this provider needs a remote-service API key.
    var requiresAPIKey: Bool {
        !isOnDevice
    }

    /// The API key namespace required for this file provider, when it uses one.
    var apiKeyProvider: DemoAPIKeyProvider? {
        switch self {
        case .elevenLabs: .elevenLabs
        case .aqua: .aqua
        case .cohere: .cohere
        case .grok: .grok
        case .openAI: .openAI
        case .meta: .meta
        case .gemini: .gemini
        case .mistral: .mistral
        case .fishAudio: .fishAudio
        case .voz, .apple: nil
        }
    }
}

/// Realtime transcription providers exposed by the demo app.
enum DemoRealtimeProvider: String, CaseIterable, Identifiable {
    case elevenLabs
    case openAI
    case grok
    case meta
    case gemini
    case mistral
    case fishAudio
    case apple

    var id: Self { self }

    /// The providers callable on this OS; Apple needs iOS 26.
    static var allCases: [DemoRealtimeProvider] {
        let providers: [DemoRealtimeProvider] = [.elevenLabs, .openAI, .grok, .meta, .gemini, .mistral, .fishAudio, .apple]
        return DemoAppleSpeech.isAvailable ? providers : providers.filter { $0 != .apple }
    }

    /// The display name shown in menus and settings.
    var title: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .openAI: "OpenAI"
        case .grok: "Grok"
        case .meta: "Meta"
        case .gemini: "Gemini"
        case .mistral: "Mistral"
        case .fishAudio: "Fish Audio"
        case .apple: "Apple (On Device)"
        }
    }

    /// The SpeechKit provider value used when opening a realtime session.
    var speechProvider: SpeechRealtimeProvider {
        switch self {
        case .elevenLabs: .elevenLabs
        case .openAI: .openAI
        case .grok: .grok
        case .meta: .meta
        case .gemini: .gemini
        case .mistral: .mistral
        case .fishAudio: .fishAudio
        case .apple: .apple
        }
    }

    /// The API key namespace required for this realtime provider, or `nil` for on-device Apple Speech.
    var apiKeyProvider: DemoAPIKeyProvider? {
        switch self {
        case .elevenLabs: .elevenLabs
        case .openAI: .openAI
        case .grok: .grok
        case .meta: .meta
        case .gemini: .gemini
        case .mistral: .mistral
        case .fishAudio: .fishAudio
        case .apple: nil
        }
    }
}

/// API key namespaces saved by the demo keychain wrapper.
enum DemoAPIKeyProvider: String, CaseIterable, Identifiable {
    case elevenLabs
    case openAI
    case grok
    case cohere
    case aqua
    case meta
    case gemini
    case mistral
    case fishAudio

    var id: Self { self }

    /// The display name shown beside key entry fields.
    var title: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .openAI: "OpenAI"
        case .grok: "Grok"
        case .cohere: "Cohere"
        case .aqua: "Aqua"
        case .meta: "Meta"
        case .gemini: "Gemini"
        case .mistral: "Mistral"
        case .fishAudio: "Fish Audio"
        }
    }

    /// The keychain account used for this provider's secret.
    var account: String { rawValue }
}

/// Observable demo settings that turn user selections into SpeechKit configurations.
@Observable
@MainActor
final class DemoConfiguration {
    private let defaults: UserDefaults
    private let keychain: any DemoCredentialStore

    /// Presence metadata only. Secret values are loaded when preparing one operation.
    private(set) var savedKeyProviders: Set<DemoAPIKeyProvider> = []
    private(set) var keychainError: String?
    private(set) var credentialRevision = 0
    private var authorizationResetsInProgress = 0
    var isResettingAuthorization: Bool { authorizationResetsInProgress > 0 }
    private(set) var relayService: SpeechService?
    private(set) var isRelayEnabled = false
    private(set) var relayExpiresAt: Date?
    private var relayExpiryTask: Task<Void, Never>?

    var relayURL: String { defaults.string(forKey: "relayURL") ?? "" }
    var relayAuthentication: DemoRelayAuthentication {
        Self.enumValue(for: "relayAuthentication", default: .appAttest, defaults: defaults)
    }
    var relayUsesVendorTokens: Bool { defaults.bool(forKey: "relayUsesVendorTokens") }
    var relayOptimizesUploads: Bool { defaults.object(forKey: "relayOptimizesUploads") as? Bool ?? true }
    var isRelayReady: Bool {
        !isResettingAuthorization && relayService?.relay != nil && (relayExpiresAt.map { $0 > Date() } ?? true)
    }

    static var supportsAppAttest: Bool { DCAppAttestService.shared.isSupported }

    func enableRelay(url: String, authentication: DemoRelayAuthentication, bearerToken: String,
                     useVendorTokens: Bool, optimizeUploads: Bool = true, replacing speech: SpeechService) async throws {
        guard !isResettingAuthorization else { throw CancellationError() }
        let relayURL = try Self.validatedRelayURL(url)
        let auth: SpeechRelay.Authentication
        let expiresAt: Date?
        switch authentication {
        case .appAttest:
            guard Self.supportsAppAttest else { throw SpeechFailure(.attestationUnsupported) }
            auth = .appAttest
            expiresAt = nil
        case .bearer:
            let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SpeechFailure(.invalidCredential)
            }
            let deadline = Date().addingTimeInterval(5 * 60)
            auth = .bearer(SpeechTokenResolver { _ -> SpeechAccessToken in
                guard Date() < deadline else { throw SpeechFailure(.invalidCredential) }
                return SpeechAccessToken(value: token, expiresAt: deadline, isReusable: true)
            })
            expiresAt = deadline
        case .none:
            auth = .none
            expiresAt = nil
        }
        authorizationResetsInProgress += 1
        defer { authorizationResetsInProgress -= 1 }
        relayExpiryTask?.cancel()
        await speech.clearCredentials()
        try Task.checkCancellation()
        let service = SpeechService(
            relay: SpeechRelay(url: relayURL, authentication: auth,
                               providers: Set(SpeechFileTranscriptionProvider.allCases.filter { $0 != .apple }),
                               tokenStrategy: useVendorTokens ? .vendorTokensWhenAvailable : .proxyAll,
                               pinnedPublicKeyHashes: [], optimizedUploads: optimizeUploads ? .on : .off),
            credentialPolicy: useVendorTokens ? .disallowStaticKeys : .relayOnly
        )
        relayService = service
        isRelayEnabled = true
        relayExpiresAt = expiresAt
        set(relayURL.absoluteString, for: "relayURL")
        set(authentication.rawValue, for: "relayAuthentication")
        set(useVendorTokens, for: "relayUsesVendorTokens")
        set(optimizeUploads, for: "relayOptimizesUploads")
        credentialRevision += 1
        if let expiresAt {
            relayExpiryTask = Task { [weak self, weak service] in
                do { try await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow))) } catch { return }
                guard let self, let service, self.relayService === service else { return }
                await self.clearAuthorization(in: service)
            }
        }
    }

    func disableRelay(in speech: SpeechService) async {
        guard !isResettingAuthorization else { return }
        relayExpiryTask?.cancel()
        relayExpiryTask = nil
        await clearAuthorization(in: speech)
        relayService = nil
        relayExpiresAt = nil
        isRelayEnabled = false
        credentialRevision += 1
    }

    nonisolated static func validatedRelayURL(_ value: String) throws -> URL {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.scheme?.lowercased() == "https" ||
                (components.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())),
              let url = components.url else { throw SpeechFailure(.invalidEndpoint) }
        return url
    }

    /// The provider used by the realtime sample.
    var realtimeProvider: DemoRealtimeProvider {
        didSet { set(realtimeProvider.rawValue, for: "realtimeProvider") }
    }

    /// The provider used by file import and recorded-upload samples.
    var fileProvider: DemoFileProvider {
        didSet { set(fileProvider.rawValue, for: "fileProvider") }
    }

    var elevenLabsRealtimeModel: ElevenLabsModelID {
        didSet { set(elevenLabsRealtimeModel.rawValue, for: "elevenLabsRealtimeModel") }
    }

    var elevenLabsFileModel: ElevenLabsModelID {
        didSet { set(elevenLabsFileModel.rawValue, for: "elevenLabsFileModel") }
    }

    /// Labels speakers in ElevenLabs file transcripts.
    var elevenLabsDiarize: Bool {
        didSet { set(elevenLabsDiarize, for: "elevenLabsDiarize") }
    }

    /// Whether ElevenLabs file transcription caps the detected speaker count.
    var elevenLabsSpeakerLimit: Bool {
        didSet { set(elevenLabsSpeakerLimit, for: "elevenLabsSpeakerLimit") }
    }

    /// The maximum speaker count sent to ElevenLabs when the limit is on.
    var elevenLabsSpeakerCount: Int {
        didSet { set(elevenLabsSpeakerCount, for: "elevenLabsSpeakerCount") }
    }

    /// How Scribe v3 writes numbers; automatic lets the model choose.
    var elevenLabsNumbersFormat: DemoElevenLabsNumbersFormat {
        didSet { set(elevenLabsNumbersFormat.rawValue, for: "elevenLabsNumbersFormat") }
    }

    /// Additional ISO 639 language codes Scribe v3 expects in the audio.
    var elevenLabsSecondaryLanguages: String {
        didSet { set(elevenLabsSecondaryLanguages, for: "elevenLabsSecondaryLanguages") }
    }

    /// Terms that bias ElevenLabs file transcription; session-only private text.
    var elevenLabsKeyterms: String

    /// Keeps sound cues such as laughter in ElevenLabs file transcripts.
    var elevenLabsTagAudioEvents: Bool {
        didSet { set(elevenLabsTagAudioEvents, for: "elevenLabsTagAudioEvents") }
    }

    /// Removes filler words and false starts from ElevenLabs transcripts.
    var elevenLabsNoVerbatim: Bool {
        didSet { set(elevenLabsNoVerbatim, for: "elevenLabsNoVerbatim") }
    }

    /// Labels speakers in Scribe v3 Live sessions.
    var elevenLabsRealtimeDiarize: Bool {
        didSet { set(elevenLabsRealtimeDiarize, for: "elevenLabsRealtimeDiarize") }
    }

    /// Lets Scribe v3 Live follow language switches mid-sentence.
    var elevenLabsRealtimeMultilingual: Bool {
        didSet { set(elevenLabsRealtimeMultilingual, for: "elevenLabsRealtimeMultilingual") }
    }

    var elevenLabsRealtimeCommitStrategy: DemoElevenLabsCommitStrategy {
        didSet { set(elevenLabsRealtimeCommitStrategy.rawValue, for: "elevenLabsRealtimeCommitStrategy") }
    }

    /// Terms that bias ElevenLabs realtime sessions; session-only private text.
    var elevenLabsRealtimeKeyterms: String

    var aquaModel: AquaModelID {
        didSet { set(aquaModel.rawValue, for: "aquaModel") }
    }

    var aquaLanguage: AquaLanguage? {
        didSet { set(aquaLanguage?.rawValue ?? "", for: "aquaLanguage") }
    }

    var cohereModel: CohereModelID {
        didSet { set(cohereModel.rawValue, for: "cohereModel") }
    }

    var cohereLanguage: CohereLanguage {
        didSet { set(cohereLanguage.rawValue, for: "cohereLanguage") }
    }

    var cohereTemperature: String {
        didSet { set(cohereTemperature, for: "cohereTemperature") }
    }

    var grokModel: GrokModelID {
        didSet { set(grokModel.rawValue, for: "grokModel") }
    }

    var grokLanguage: GrokLanguage? {
        didSet { set(grokLanguage?.rawValue ?? "", for: "grokLanguage") }
    }

    var grokFormat: Bool {
        didSet { set(grokFormat, for: "grokFormat") }
    }

    var grokDiarize: Bool {
        didSet { set(grokDiarize, for: "grokDiarize") }
    }

    var grokMultichannel: Bool {
        didSet { set(grokMultichannel, for: "grokMultichannel") }
    }

    var grokRealtimeFillerWords: Bool {
        didSet { set(grokRealtimeFillerWords, for: "grokRealtimeFillerWords") }
    }

    var grokTimeoutMinutes: Double {
        didSet { set(grokTimeoutMinutes, for: "grokTimeoutMinutes") }
    }

    var openAIFileModel: OpenAIFileTranscriptionModelID {
        didSet { set(openAIFileModel.rawValue, for: "openAIFileModel") }
    }

    var openAIRealtimeSessionModel: OpenAIRealtimeSessionModelID {
        didSet { set(openAIRealtimeSessionModel.rawValue, for: "openAIRealtimeSessionModel") }
    }

    var openAIRealtimeTranscriptionModel: OpenAIRealtimeTranscriptionModelID {
        didSet { set(openAIRealtimeTranscriptionModel.rawValue, for: "openAIRealtimeTranscriptionModel") }
    }

    var openAILanguage: String {
        didSet { set(openAILanguage, for: "openAILanguage") }
    }

    var openAILanguages: String {
        didSet { set(openAILanguages, for: "openAILanguages") }
    }

    var openAIPrompt: String

    var openAIKeywords: String

    var openAIRealtimeDelay: DemoOpenAIRealtimeDelay {
        didSet { set(openAIRealtimeDelay.rawValue, for: "openAIRealtimeDelay") }
    }

    var openAITemperature: String {
        didSet { set(openAITemperature, for: "openAITemperature") }
    }

    var openAIIncludeLogprobs: Bool {
        didSet { set(openAIIncludeLogprobs, for: "openAIIncludeLogprobs") }
    }

    var openAIWordTimestamps: Bool {
        didSet { set(openAIWordTimestamps, for: "openAIWordTimestamps") }
    }

    var openAISegmentTimestamps: Bool {
        didSet { set(openAISegmentTimestamps, for: "openAISegmentTimestamps") }
    }

    var openAIDiarization: Bool {
        didSet { set(openAIDiarization, for: "openAIDiarization") }
    }

    var openAITimeoutMinutes: Double {
        didSet { set(openAITimeoutMinutes, for: "openAITimeoutMinutes") }
    }

    var metaModel: MetaModelID {
        didSet { set(metaModel.rawValue, for: "metaModel") }
    }

    var metaMode: MetaTranscriptionMode {
        didSet { set(metaMode.rawValue, for: "metaMode") }
    }

    var metaLanguage: MetaLanguage? {
        didSet { set(metaLanguage?.rawValue ?? "", for: "metaLanguage") }
    }

    var metaKeywords: String

    var metaRealtimePartialMode: MetaPartialMode {
        didSet { set(metaRealtimePartialMode.rawValue, for: "metaRealtimePartialMode") }
    }

    var geminiFileModel: GeminiFileTranscriptionModelID {
        didSet { set(geminiFileModel.rawValue, for: "geminiFileModel") }
    }

    var geminiRealtimeModel: GeminiRealtimeModelID {
        didSet { set(geminiRealtimeModel.rawValue, for: "geminiRealtimeModel") }
    }

    var geminiLanguageCodes: String {
        didSet { set(geminiLanguageCodes, for: "geminiLanguageCodes") }
    }

    var geminiCustomVocabulary: String

    var geminiMode: GeminiTranscriptionMode {
        didSet { set(geminiMode.rawValue, for: "geminiMode") }
    }

    var geminiDiarize: Bool {
        didSet { set(geminiDiarize, for: "geminiDiarize") }
    }

    var geminiWordTimestamps: Bool {
        didSet { set(geminiWordTimestamps, for: "geminiWordTimestamps") }
    }

    var geminiBackgroundProcessing: Bool {
        didSet { set(geminiBackgroundProcessing, for: "geminiBackgroundProcessing") }
    }

    var mistralFileModel: MistralFileTranscriptionModelID {
        didSet { set(mistralFileModel.rawValue, for: "mistralFileModel") }
    }

    /// A two-letter ISO 639-1 code for Mistral; empty lets Mistral detect the language.
    var mistralLanguage: String {
        didSet { set(mistralLanguage, for: "mistralLanguage") }
    }

    var mistralContextBias: String

    /// Labels speakers in both Mistral file transcripts and realtime sessions.
    var mistralDiarize: Bool {
        didSet { set(mistralDiarize, for: "mistralDiarize") }
    }

    var mistralRealtimeDelay: DemoMistralStreamingDelay {
        didSet { set(mistralRealtimeDelay.rawValue, for: "mistralRealtimeDelay") }
    }

    /// A lowercase two-letter ISO 639-1 hint for Fish Audio files; empty lets Fish Audio detect the language.
    var fishAudioLanguage: String {
        didSet { set(fishAudioLanguage, for: "fishAudioLanguage") }
    }

    var fishAudioDiarize: FishAudioDiarization {
        didSet { set(fishAudioDiarize.rawValue, for: "fishAudioDiarize") }
    }

    /// Word segments and speaker turns; off is faster but returns plain text only.
    var fishAudioTimestamps: Bool {
        didSet { set(fishAudioTimestamps, for: "fishAudioTimestamps") }
    }

    /// Keeps sound cues such as `[laughter]` in file transcripts.
    var fishAudioTagAudioEvents: Bool {
        didSet { set(fishAudioTagAudioEvents, for: "fishAudioTagAudioEvents") }
    }

    var fishAudioRealtimeMode: FishAudioTurnDetectionMode {
        didSet { set(fishAudioRealtimeMode.rawValue, for: "fishAudioRealtimeMode") }
    }

    var fishAudioRealtimeDiarize: Bool {
        didSet { set(fishAudioRealtimeDiarize, for: "fishAudioRealtimeDiarize") }
    }

    /// Recognition terms for Fish Audio realtime sessions.
    var fishAudioRealtimeTerms: String

    /// A locale identifier for Apple Speech; empty uses the device's current locale.
    var appleLocaleIdentifier: String {
        didSet { set(appleLocaleIdentifier, for: "appleLocaleIdentifier") }
    }

    var appleContextualStrings: String

    var appleModelRetention: DemoAppleModelRetention {
        didSet { set(appleModelRetention.rawValue, for: "appleModelRetention") }
    }

    /// Loads nonsecret defaults and removes legacy persisted private text.
    init(defaults: UserDefaults = .standard, keychain: any DemoCredentialStore = DemoKeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        // A saved Apple selection is unusable on an OS without SpeechAnalyzer, so fall back.
        let savedRealtimeProvider: DemoRealtimeProvider = Self.enumValue(for: "realtimeProvider", default: .elevenLabs, defaults: defaults)
        realtimeProvider = DemoRealtimeProvider.allCases.contains(savedRealtimeProvider) ? savedRealtimeProvider : .elevenLabs
        let savedFileProvider: DemoFileProvider = Self.enumValue(for: "fileProvider", default: .openAI, defaults: defaults)
        fileProvider = DemoFileProvider.allCases.contains(savedFileProvider) ? savedFileProvider : .openAI
        elevenLabsRealtimeModel = Self.enumValue(for: "elevenLabsRealtimeModel", default: .scribeV3Live, defaults: defaults)
        elevenLabsFileModel = Self.enumValue(for: "elevenLabsFileModel", default: .scribeV3, defaults: defaults)
        elevenLabsDiarize = defaults.object(forKey: "elevenLabsDiarize") as? Bool ?? false
        elevenLabsSpeakerLimit = defaults.object(forKey: "elevenLabsSpeakerLimit") as? Bool ?? false
        elevenLabsSpeakerCount = defaults.object(forKey: "elevenLabsSpeakerCount") as? Int ?? 2
        elevenLabsNumbersFormat = Self.enumValue(for: "elevenLabsNumbersFormat", default: .automatic, defaults: defaults)
        elevenLabsSecondaryLanguages = defaults.string(forKey: "elevenLabsSecondaryLanguages") ?? ""
        elevenLabsKeyterms = ""
        elevenLabsTagAudioEvents = defaults.object(forKey: "elevenLabsTagAudioEvents") as? Bool ?? false
        elevenLabsNoVerbatim = defaults.object(forKey: "elevenLabsNoVerbatim") as? Bool ?? false
        elevenLabsRealtimeDiarize = defaults.object(forKey: "elevenLabsRealtimeDiarize") as? Bool ?? false
        elevenLabsRealtimeMultilingual = defaults.object(forKey: "elevenLabsRealtimeMultilingual") as? Bool ?? false
        elevenLabsRealtimeCommitStrategy = Self.enumValue(for: "elevenLabsRealtimeCommitStrategy", default: .automatic, defaults: defaults)
        elevenLabsRealtimeKeyterms = ""
        aquaModel = Self.enumValue(for: "aquaModel", default: .avalonV15, defaults: defaults)
        aquaLanguage = Self.optionalEnumValue(for: "aquaLanguage", defaults: defaults)
        cohereModel = Self.enumValue(for: "cohereModel", default: .transcribe032026, defaults: defaults)
        cohereLanguage = Self.enumValue(for: "cohereLanguage", default: .english, defaults: defaults)
        cohereTemperature = defaults.string(forKey: "cohereTemperature") ?? "0.2"
        grokModel = Self.enumValue(for: "grokModel", default: .stt, defaults: defaults)
        grokLanguage = Self.optionalEnumValue(for: "grokLanguage", defaults: defaults) ?? .english
        grokFormat = defaults.object(forKey: "grokFormat") as? Bool ?? true
        grokDiarize = defaults.object(forKey: "grokDiarize") as? Bool ?? false
        grokMultichannel = defaults.object(forKey: "grokMultichannel") as? Bool ?? false
        grokRealtimeFillerWords = defaults.object(forKey: "grokRealtimeFillerWords") as? Bool ?? false
        grokTimeoutMinutes = defaults.object(forKey: "grokTimeoutMinutes") as? Double ?? 15
        openAIFileModel = Self.enumValue(for: "openAIFileModel", default: .gptTranscribe, defaults: defaults)
        openAIRealtimeSessionModel = Self.enumValue(for: "openAIRealtimeSessionModel", default: .gptRealtime, defaults: defaults)
        openAIRealtimeTranscriptionModel = Self.enumValue(for: "openAIRealtimeTranscriptionModel", default: .gptLiveTranscribe, defaults: defaults)
        openAILanguage = defaults.string(forKey: "openAILanguage") ?? ""
        openAILanguages = defaults.string(forKey: "openAILanguages") ?? ""
        openAIPrompt = ""
        openAIKeywords = ""
        openAIRealtimeDelay = Self.enumValue(for: "openAIRealtimeDelay", default: .low, defaults: defaults)
        openAITemperature = defaults.string(forKey: "openAITemperature") ?? ""
        openAIIncludeLogprobs = defaults.object(forKey: "openAIIncludeLogprobs") as? Bool ?? false
        openAIWordTimestamps = defaults.object(forKey: "openAIWordTimestamps") as? Bool ?? false
        openAISegmentTimestamps = defaults.object(forKey: "openAISegmentTimestamps") as? Bool ?? false
        openAIDiarization = defaults.object(forKey: "openAIDiarization") as? Bool ?? false
        openAITimeoutMinutes = defaults.object(forKey: "openAITimeoutMinutes") as? Double ?? 10
        metaModel = Self.enumValue(for: "metaModel", default: .museVoiceTranscribe1, defaults: defaults)
        metaMode = Self.enumValue(for: "metaMode", default: .endpointing, defaults: defaults)
        metaLanguage = Self.optionalEnumValue(for: "metaLanguage", defaults: defaults)
        metaKeywords = ""
        metaRealtimePartialMode = Self.enumValue(for: "metaRealtimePartialMode", default: .cumulative, defaults: defaults)
        geminiFileModel = Self.enumValue(for: "geminiFileModel", default: .transcribe35, defaults: defaults)
        geminiRealtimeModel = Self.enumValue(for: "geminiRealtimeModel", default: .transcribeLive35, defaults: defaults)
        geminiLanguageCodes = defaults.string(forKey: "geminiLanguageCodes") ?? ""
        geminiCustomVocabulary = ""
        geminiMode = Self.enumValue(for: "geminiMode", default: .verbatim, defaults: defaults)
        geminiDiarize = defaults.object(forKey: "geminiDiarize") as? Bool ?? false
        geminiWordTimestamps = defaults.object(forKey: "geminiWordTimestamps") as? Bool ?? false
        geminiBackgroundProcessing = defaults.object(forKey: "geminiBackgroundProcessing") as? Bool ?? false
        mistralFileModel = Self.enumValue(for: "mistralFileModel", default: .voxtralMiniTranscribe3, defaults: defaults)
        mistralLanguage = defaults.string(forKey: "mistralLanguage") ?? ""
        mistralContextBias = ""
        mistralDiarize = defaults.object(forKey: "mistralDiarize") as? Bool ?? false
        mistralRealtimeDelay = Self.enumValue(for: "mistralRealtimeDelay", default: .providerDefault, defaults: defaults)
        fishAudioLanguage = defaults.string(forKey: "fishAudioLanguage") ?? ""
        fishAudioDiarize = Self.enumValue(for: "fishAudioDiarize", default: .auto, defaults: defaults)
        fishAudioTimestamps = defaults.object(forKey: "fishAudioTimestamps") as? Bool ?? true
        fishAudioTagAudioEvents = defaults.object(forKey: "fishAudioTagAudioEvents") as? Bool ?? true
        fishAudioRealtimeMode = Self.enumValue(for: "fishAudioRealtimeMode", default: .auto, defaults: defaults)
        fishAudioRealtimeDiarize = defaults.object(forKey: "fishAudioRealtimeDiarize") as? Bool ?? true
        fishAudioRealtimeTerms = ""
        appleLocaleIdentifier = defaults.string(forKey: "appleLocaleIdentifier") ?? ""
        appleContextualStrings = ""
        appleModelRetention = Self.enumValue(for: "appleModelRetention", default: .whileInUse, defaults: defaults)
        resetPrivateText()
        refreshKeyStatus()
    }

    /// Changes observable status only after Keychain confirms persistence.
    func setAPIKey(_ value: String, for provider: DemoAPIKeyProvider) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.delete(account: provider.account)
            savedKeyProviders.remove(provider)
        } else {
            try keychain.save(trimmed, account: provider.account)
            savedKeyProviders.insert(provider)
        }
        keychainError = nil
        credentialRevision += 1
    }

    /// Checks attributes only, including migration of existing accessibility attributes.
    func refreshKeyStatus() {
        var present: Set<DemoAPIKeyProvider> = []
        keychainError = nil
        for provider in DemoAPIKeyProvider.allCases {
            do {
                if try keychain.contains(account: provider.account) { present.insert(provider) }
            } catch {
                keychainError = "Keychain status is unavailable. Unlock the device and try again."
            }
        }
        savedKeyProviders = present
    }

    func hasAPIKey(for provider: DemoAPIKeyProvider) -> Bool {
        savedKeyProviders.contains(provider) && !isResettingAuthorization
    }

    /// Private prompts and vocabulary last for this app session only.
    func resetPrivateText() {
        openAIPrompt = ""
        openAIKeywords = ""
        metaKeywords = ""
        geminiCustomVocabulary = ""
        mistralContextBias = ""
        fishAudioRealtimeTerms = ""
        elevenLabsKeyterms = ""
        elevenLabsRealtimeKeyterms = ""
        appleContextualStrings = ""
        DemoPrivateTextPreferences.clearSavedValues(in: defaults)
    }

    /// Returns whether a file provider can be used with the current keychain state.
    func hasAPIKey(for provider: DemoFileProvider) -> Bool {
        guard let apiKeyProvider = provider.apiKeyProvider else { return true }
        if isRelayEnabled { return isRelayReady }
        return hasAPIKey(for: apiKeyProvider)
    }

    /// Returns whether a realtime provider can be used with the current keychain state.
    func hasAPIKey(for provider: DemoRealtimeProvider) -> Bool {
        guard let apiKeyProvider = provider.apiKeyProvider else { return true }
        if isRelayEnabled { return isRelayReady }
        return hasAPIKey(for: apiKeyProvider)
    }

    /// Builds the missing-key message for file workflows.
    func missingAPIKeyMessage(for provider: DemoFileProvider) -> String {
        if isRelayEnabled { return "Relay authorization is unavailable or expired. Reapply Relay settings with fresh authentication." }
        return "Add a \(provider.title) API key in Settings."
    }

    /// Builds the missing-key message for realtime workflows.
    func missingAPIKeyMessage(for provider: DemoRealtimeProvider) -> String {
        if isRelayEnabled { return "Relay authorization is unavailable or expired. Reapply Relay settings with fresh authentication." }
        return "Add a \(provider.title) API key in Settings."
    }

    /// The only Keychain value read and SDK key construction point. Keep static-key auth.
    func prepare(_ speech: SpeechService, for provider: DemoAPIKeyProvider?) throws {
        guard !isResettingAuthorization else { throw CancellationError() }
        releaseAuthorization(from: speech)
        let key: String
        if provider != nil, isRelayEnabled {
            guard isRelayReady, speech === relayService else { throw SpeechFailure(.invalidCredential) }
            key = ""
        } else if let provider {
            guard let value = try keychain.read(account: provider.account), !value.isEmpty else {
                throw DemoKeychainError.missingKey
            }
            key = value
        } else {
            key = ""
        }
        if provider == .elevenLabs {
            speech.elevenLabs = ElevenLabsConfiguration(
                credential: .apiKey(key),
                realtimeModelID: elevenLabsRealtimeModel,
                fileTranscriptionModelID: elevenLabsFileModel,
                fileOptions: elevenLabsFileOptions,
                realtimeOptions: ElevenLabsRealtimeOptions(
                    multilingual: elevenLabsRealtimeMultilingual,
                    commitStrategy: elevenLabsRealtimeCommitStrategy.speechKitValue,
                    diarize: elevenLabsRealtimeDiarize,
                    keyterms: termList(elevenLabsRealtimeKeyterms)
                )
            )
        }

        if provider == .openAI {
            speech.openAI = OpenAIConfiguration(
                credential: .apiKey(key),
                fileTranscriptionModelID: openAIFileModel,
                realtimeSessionModelID: openAIRealtimeSessionModel,
                realtimeTranscriptionModelID: openAIRealtimeTranscriptionModel,
                language: nilIfBlank(openAILanguage),
                languages: commaSeparatedValues(openAILanguages),
                prompt: nilIfBlank(openAIPrompt),
                keywords: commaSeparatedValues(openAIKeywords),
                temperature: Double(openAITemperature),
                diarizationChunkingStrategy: openAIDiarization ? .auto : nil,
                realtimeDelay: openAIRealtimeDelay.speechKitValue,
                realtimeCommitInterval: 1,
                timeoutInterval: openAITimeoutMinutes * 60
            )
        }

        if provider == .grok {
            speech.grok = GrokConfiguration(
                credential: .apiKey(key),
                modelID: grokModel,
                language: grokLanguage,
                format: grokFormat,
                multichannel: grokMultichannel,
                diarize: grokDiarize,
                realtimeOptions: GrokRealtimeOptions(
                    language: grokLanguage,
                    interimResults: true,
                    multichannel: false,
                    channels: 1,
                    diarize: grokDiarize,
                    fillerWords: grokRealtimeFillerWords
                ),
                timeoutInterval: grokTimeoutMinutes * 60
            )
        }

        if provider == .cohere {
            speech.cohere = CohereConfiguration(
                credential: .apiKey(key),
                modelID: cohereModel,
                language: cohereLanguage,
                temperature: Double(cohereTemperature)
            )
        }

        if provider == .aqua {
            speech.aqua = AquaConfiguration(
                credential: .apiKey(key),
                modelID: aquaModel,
                language: aquaLanguage
            )
        }

        if provider == .meta {
            speech.meta = MetaConfiguration(
                credential: .apiKey(key),
                modelID: metaModel,
                mode: metaMode,
                languageBias: metaLanguageBias,
                keywords: commaSeparatedValues(metaKeywords),
                realtimeOptions: MetaRealtimeOptions(
                    modelID: metaModel,
                    mode: metaMode,
                    partialMode: metaRealtimePartialMode,
                    languageBias: metaLanguageBias,
                    keywords: commaSeparatedValues(metaKeywords)
                )
            )
        }

        if provider == .gemini {
            speech.gemini = GeminiConfiguration(
                credential: .apiKey(key),
                fileTranscriptionModelID: geminiFileModel,
                realtimeModelID: geminiRealtimeModel,
                languageCodes: commaSeparatedValues(geminiLanguageCodes),
                customVocabulary: commaSeparatedValues(geminiCustomVocabulary),
                mode: geminiMode,
                diarize: geminiDiarize,
                timestampGranularities: geminiTimestampGranularities,
                processingMode: geminiProcessingMode,
                // `realtimeModelID` above is the source of truth for the Live model;
                // SpeechService applies it on top of these options.
                realtimeOptions: GeminiRealtimeOptions(
                    languageCodes: commaSeparatedValues(geminiLanguageCodes),
                    customVocabulary: commaSeparatedValues(geminiCustomVocabulary),
                    mode: geminiMode
                )
            )
        }

        if provider == .mistral {
            speech.mistral = MistralConfiguration(
                credential: .apiKey(key),
                fileTranscriptionModelID: mistralFileModel,
                language: nilIfBlank(mistralLanguage),
                contextBias: commaSeparatedValues(mistralContextBias),
                diarize: mistralDiarize,
                // Diarized sessions drop turn detection and split entries on speaker change.
                realtimeOptions: MistralRealtimeOptions(
                    targetStreamingDelayMilliseconds: mistralRealtimeDelay.milliseconds,
                    language: nilIfBlank(mistralLanguage),
                    contextBias: commaSeparatedValues(mistralContextBias),
                    diarize: mistralDiarize
                )
            )
        }

        if provider == .fishAudio {
            speech.fishAudio = FishAudioConfiguration(
                credential: .apiKey(key),
                language: nilIfBlank(fishAudioLanguage),
                timestamps: fishAudioTimestamps,
                diarize: fishAudioDiarize,
                tagAudioEvents: fishAudioTagAudioEvents,
                // Fish Audio bills realtime sessions while the socket is open, idle time included.
                realtimeOptions: FishAudioRealtimeOptions(
                    mode: fishAudioRealtimeMode,
                    diarize: fishAudioRealtimeDiarize,
                    terms: commaSeparatedValues(fishAudioRealtimeTerms)
                )
            )
        }

        if provider == nil, #available(iOS 26.0, *) {
            speech.apple = AppleSpeechConfiguration(
                locale: appleLocale,
                contextualStrings: commaSeparatedValues(appleContextualStrings),
                modelRetention: appleModelRetention.speechKitValue
            )
        }
    }

    /// The locale Apple Speech transcribes, from the saved identifier or the device locale.
    var appleLocale: Locale {
        appleLocaleIdentifier.isEmpty ? .current : Locale(identifier: appleLocaleIdentifier)
    }

    /// Converts the current provider-specific controls into SpeechKit file transcription options.
    func fileOptions(for provider: DemoFileProvider) -> SpeechFileTranscriptionOptions? {
        switch provider {
        case .elevenLabs:
            return .elevenLabs(modelID: elevenLabsFileModel)
        case .aqua:
            return .aqua(modelID: aquaModel, language: aquaLanguage)
        case .cohere:
            return .cohere(modelID: cohereModel, language: cohereLanguage, temperature: Double(cohereTemperature))
        case .grok:
            return .grok(
                modelID: grokModel,
                language: grokLanguage,
                format: grokFormat,
                multichannel: grokMultichannel,
                diarize: grokDiarize,
                timeoutInterval: grokTimeoutMinutes * 60
            )
        case .openAI:
            var granularities: [OpenAITimestampGranularity] = []
            if openAIWordTimestamps {
                granularities.append(.word)
            }
            if openAISegmentTimestamps {
                granularities.append(.segment)
            }
            return .openAI(
                modelID: openAIFileModel,
                language: nilIfBlank(openAILanguage),
                languages: commaSeparatedValues(openAILanguages),
                prompt: nilIfBlank(openAIPrompt),
                keywords: commaSeparatedValues(openAIKeywords),
                temperature: Double(openAITemperature),
                includeLogprobs: openAIIncludeLogprobs,
                timestampGranularities: granularities,
                diarizationChunkingStrategy: openAIDiarization ? .auto : nil,
                timeoutInterval: openAITimeoutMinutes * 60
            )
        case .meta:
            return .meta(
                modelID: metaModel,
                mode: metaMode,
                languageBias: metaLanguageBias,
                keywords: commaSeparatedValues(metaKeywords)
            )
        case .gemini:
            return .gemini(
                modelID: geminiFileModel,
                languageCodes: commaSeparatedValues(geminiLanguageCodes),
                customVocabulary: commaSeparatedValues(geminiCustomVocabulary),
                mode: geminiMode,
                diarize: geminiDiarize,
                timestampGranularities: geminiTimestampGranularities,
                processingMode: geminiProcessingMode
            )
        case .mistral:
            return .mistral(
                modelID: mistralFileModel,
                language: nilIfBlank(mistralLanguage),
                contextBias: commaSeparatedValues(mistralContextBias),
                diarize: mistralDiarize
            )
        case .fishAudio:
            return .fishAudio(
                language: nilIfBlank(fishAudioLanguage),
                timestamps: fishAudioTimestamps,
                diarize: fishAudioDiarize,
                tagAudioEvents: fishAudioTagAudioEvents
            )
        case .voz, .apple:
            return nil
        }
    }

    /// ElevenLabs file options for the detailed request the demo makes when diarization is
    /// on, so the transcript can show who said what.
    var elevenLabsFileOptions: ElevenLabsFileTranscriptionOptions {
        ElevenLabsFileTranscriptionOptions(
            modelID: elevenLabsFileModel,
            secondaryLanguages: commaSeparatedValues(elevenLabsSecondaryLanguages),
            numbersFormat: elevenLabsNumbersFormat.speechKitValue,
            diarize: elevenLabsDiarize,
            speakerCount: elevenLabsDiarize && elevenLabsSpeakerLimit ? elevenLabsSpeakerCount : nil,
            keyterms: termList(elevenLabsKeyterms),
            tagAudioEvents: elevenLabsTagAudioEvents,
            noVerbatim: elevenLabsNoVerbatim
        )
    }

    /// Whether an ElevenLabs file request returns speaker labels worth showing.
    var elevenLabsReturnsSpeakers: Bool {
        elevenLabsDiarize
    }

    /// Mistral file options for the detailed request the demo makes when diarization is on,
    /// so the transcript can show who said what.
    var mistralFileOptions: MistralFileTranscriptionOptions {
        MistralFileTranscriptionOptions(
            modelID: mistralFileModel,
            language: nilIfBlank(mistralLanguage),
            contextBias: commaSeparatedValues(mistralContextBias),
            diarize: mistralDiarize
        )
    }

    /// Fish Audio file options for the detailed request the demo makes when speaker
    /// turns are available, so the transcript can show who said what.
    var fishAudioFileOptions: FishAudioFileTranscriptionOptions {
        FishAudioFileTranscriptionOptions(
            language: nilIfBlank(fishAudioLanguage),
            timestamps: fishAudioTimestamps,
            diarize: fishAudioDiarize,
            tagAudioEvents: fishAudioTagAudioEvents
        )
    }

    /// Whether a Fish Audio file request returns speaker turns worth showing.
    var fishAudioReturnsSpeakers: Bool {
        fishAudioTimestamps && fishAudioDiarize != .off
    }

    /// The Meta language bias list built from the single-language demo picker.
    private var metaLanguageBias: [MetaLanguage] {
        metaLanguage.map { [$0] } ?? []
    }

    /// The Gemini timestamp granularities implied by the demo word-timestamp toggle.
    private var geminiTimestampGranularities: [GeminiTimestampGranularity] {
        geminiWordTimestamps ? [.word] : []
    }

    /// The Gemini processing mode implied by the demo background-processing toggle.
    private var geminiProcessingMode: GeminiProcessingMode {
        geminiBackgroundProcessing ? .background(pollInterval: 5) : .synchronous
    }

    /// Returns the provider timeout shown by upload progress UI when SpeechKit has a timeout for that provider.
    func timeoutInterval(for provider: DemoFileProvider) -> TimeInterval? {
        switch provider {
        case .grok:
            return grokTimeoutMinutes * 60
        case .openAI:
            return openAITimeoutMinutes * 60
        case .fishAudio:
            return fishAudioFileOptions.timeoutInterval
        case .elevenLabs, .aqua, .cohere, .meta, .gemini, .mistral, .voz, .apple:
            return nil
        }
    }

    /// Drops SDK configuration copies without reading credentials back.
    func releaseAuthorization(from speech: SpeechService) {
        speech.elevenLabs = nil
        speech.openAI = nil
        speech.grok = nil
        speech.cohere = nil
        speech.aqua = nil
        speech.meta = nil
        speech.gemini = nil
        speech.mistral = nil
        speech.fishAudio = nil
        if #available(iOS 26.0, *) { speech.apple = nil }
    }

    func resetAuthorization(in speech: SpeechService) async {
        authorizationResetsInProgress += 1
        defer { authorizationResetsInProgress -= 1 }
        releaseAuthorization(from: speech)
        if speech.relay != nil {
            await speech.resetSession()
        } else {
            await speech.clearCredentials()
        }
        releaseAuthorization(from: speech)
    }

    func clearAuthorization(in speech: SpeechService) async {
        authorizationResetsInProgress += 1
        defer { authorizationResetsInProgress -= 1 }
        await speech.clearCredentials()
        credentialRevision += 1
    }

    /// Writes a persisted demo option value.
    private func set(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
    }

    /// Converts empty text fields into `nil` before passing optional provider settings to SpeechKit.
    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parses comma-separated language or keyword values without persisting empty entries.
    private func commaSeparatedValues(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Parses comma- or newline-separated keyterm text without persisting empty entries.
    private func termList(_ value: String) -> [String] {
        commaSeparatedValues(value.replacingOccurrences(of: "\n", with: ","))
    }

    /// Reads a persisted raw-representable value or returns a default.
    private static func enumValue<T: RawRepresentable>(for key: String, default defaultValue: T, defaults: UserDefaults) -> T where T.RawValue == String {
        guard let rawValue = defaults.string(forKey: key), let value = T(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    /// Reads a persisted optional raw-representable value.
    private static func optionalEnumValue<T: RawRepresentable>(for key: String, defaults: UserDefaults) -> T? where T.RawValue == String {
        guard let rawValue = defaults.string(forKey: key), !rawValue.isEmpty else {
            return nil
        }
        return T(rawValue: rawValue)
    }
}

enum DemoFailure {
    static func message(for error: Error) -> String {
        if error is CancellationError { return "The operation was cancelled." }
        if let failure = error as? SpeechFailure {
            switch failure.category {
            case .attestationUnsupported:
                return "App Attest is unavailable on this device or Simulator. Use a supported device, or explicitly select Bearer test authentication."
            case .invalidCredential, .credentialResolution:
                return "Authorization is unavailable or expired. Enter fresh credentials in Settings. Relay test tokens last at most five minutes in this app."
            case .server:
                return statusMessage(failure.statusCode)
            default:
                return failure.errorDescription ?? "The speech request failed."
            }
        }
        if let failure = error as? SpeechError {
            switch failure {
            case .uploadFailed(_, let reason), .decodingFailed(_, let reason), .providerFailure(_, let reason):
                return reasonMessage(reason)
            case .httpFailure(_, let status): return statusMessage(status)
            case .providerNotConfigured, .realtimeProviderNotConfigured: return "Configure this provider or Relay in Settings."
            case .unsupportedCapability, .invalidOptionsForProvider: return "These options are not supported by the selected provider."
            case .invalidResponse: return "The provider returned an invalid response."
            case .appleSpeechUnavailable, .appleSpeechNotSupportedOnWatch: return "Apple Speech is unavailable on this device."
            case .appleSpeechUnsupportedLocale: return "Apple Speech does not support the selected language."
            case .appleSpeechAssetsUnavailable: return "Prepare Apple Speech language assets in Settings."
            }
        }
        if let failure = error as? FishAudioRealtimeError {
            switch failure {
            case .connectionRefused(let status): return statusMessage(status)
            case .serverError(let code): return statusMessage(code)
            case .sessionClosed: return "Fish Audio closed the session. Start a new session."
            case .serverRestarting: return "Fish Audio is restarting. Start a new session."
            case .handshakeTimedOut: return "Fish Audio did not start the session in time."
            case .apiKeyMissing: return "Configure Fish Audio or Relay in Settings."
            case .invalidURL: return "The Fish Audio endpoint is invalid."
            case .disconnected: return "Fish Audio is disconnected."
            }
        }
        if let failure = error as? SpeechAudioCaptureError {
            switch failure {
            case .permissionDenied: return "Microphone permission is required. Enable it in system Settings."
            case .audioEngineError(let reason): return reasonMessage(reason)
            }
        }
        if let failure = error as? DemoKeychainError { return failure.localizedDescription }
        if (error as? URLError)?.code == .cancelled { return "The operation was cancelled." }
        return "The operation failed. Check permissions, connection, and provider settings, then try again."
    }

    private static func statusMessage(_ status: Int?) -> String {
        switch status {
        case 401, 403: "Authorization was rejected. Reauthenticate in Settings; Relay test tokens may have expired."
        case 402: "The provider requires billing or available credit."
        case 429: "The request limit was reached. Wait before starting a new request."
        case 503: "The provider is unavailable or is not configured on the Relay."
        default: "The server rejected the speech request."
        }
    }

    private static func reasonMessage(_ reason: SpeechFailureReason) -> String {
        switch reason {
        case .requestFailed: "The speech request failed. Check authentication and connection."
        case .invalidOptions: "Check the selected provider options."
        case .invalidResponse, .decodingFailed: "The provider returned an invalid response."
        case .uploadFailed: "The audio upload failed."
        case .timedOut: "The speech request timed out."
        case .sessionEnding: "The speech session is ending. Start a new session."
        }
    }
}
