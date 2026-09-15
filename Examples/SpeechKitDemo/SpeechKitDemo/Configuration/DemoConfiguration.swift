import Foundation
import Observation
import Security
import SpeechKit

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

/// File-transcription providers exposed by the demo app.
enum DemoFileProvider: String, CaseIterable, Identifiable {
    case elevenLabs
    case aqua
    case cohere
    case grok
    case openAI
    case meta
    case gemini

    var id: Self { self }

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
        }
    }

    /// The SpeechKit provider value used when making a file-transcription request.
    var speechProvider: SpeechFileTranscriptionProvider {
        switch self {
        case .elevenLabs: .elevenLabs
        case .aqua: .aqua
        case .cohere: .cohere
        case .grok: .grok
        case .openAI: .openAI
        case .meta: .meta
        case .gemini: .gemini
        }
    }

    /// The API key namespace required for this file provider.
    var apiKeyProvider: DemoAPIKeyProvider {
        switch self {
        case .elevenLabs: .elevenLabs
        case .aqua: .aqua
        case .cohere: .cohere
        case .grok: .grok
        case .openAI: .openAI
        case .meta: .meta
        case .gemini: .gemini
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

    var id: Self { self }

    /// The display name shown in menus and settings.
    var title: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .openAI: "OpenAI"
        case .grok: "Grok"
        case .meta: "Meta"
        case .gemini: "Gemini"
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
        }
    }

    /// The API key namespace required for this realtime provider.
    var apiKeyProvider: DemoAPIKeyProvider {
        switch self {
        case .elevenLabs: .elevenLabs
        case .openAI: .openAI
        case .grok: .grok
        case .meta: .meta
        case .gemini: .gemini
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
    private let keychain = DemoKeychainStore(service: "com.sentinelite.SpeechKitDemo.api-keys")

    /// Provider keys loaded from the keychain for the current demo session.
    var apiKeys: [DemoAPIKeyProvider: String] = [:]

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

    var openAIPrompt: String {
        didSet { set(openAIPrompt, for: "openAIPrompt") }
    }

    var openAIKeywords: String {
        didSet { set(openAIKeywords, for: "openAIKeywords") }
    }

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

    var metaKeywords: String {
        didSet { set(metaKeywords, for: "metaKeywords") }
    }

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

    var geminiCustomVocabulary: String {
        didSet { set(geminiCustomVocabulary, for: "geminiCustomVocabulary") }
    }

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

    /// Loads persisted provider defaults and keychain-backed secrets.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        realtimeProvider = Self.enumValue(for: "realtimeProvider", default: .elevenLabs, defaults: defaults)
        fileProvider = Self.enumValue(for: "fileProvider", default: .openAI, defaults: defaults)
        elevenLabsRealtimeModel = Self.enumValue(for: "elevenLabsRealtimeModel", default: .scribeV2Realtime, defaults: defaults)
        elevenLabsFileModel = Self.enumValue(for: "elevenLabsFileModel", default: .scribeV2, defaults: defaults)
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
        openAIPrompt = defaults.string(forKey: "openAIPrompt") ?? ""
        openAIKeywords = defaults.string(forKey: "openAIKeywords") ?? ""
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
        metaKeywords = defaults.string(forKey: "metaKeywords") ?? ""
        metaRealtimePartialMode = Self.enumValue(for: "metaRealtimePartialMode", default: .cumulative, defaults: defaults)
        geminiFileModel = Self.enumValue(for: "geminiFileModel", default: .transcribe35, defaults: defaults)
        geminiRealtimeModel = Self.enumValue(for: "geminiRealtimeModel", default: .transcribeLive35, defaults: defaults)
        geminiLanguageCodes = defaults.string(forKey: "geminiLanguageCodes") ?? ""
        geminiCustomVocabulary = defaults.string(forKey: "geminiCustomVocabulary") ?? ""
        geminiMode = Self.enumValue(for: "geminiMode", default: .verbatim, defaults: defaults)
        geminiDiarize = defaults.object(forKey: "geminiDiarize") as? Bool ?? false
        geminiWordTimestamps = defaults.object(forKey: "geminiWordTimestamps") as? Bool ?? false
        geminiBackgroundProcessing = defaults.object(forKey: "geminiBackgroundProcessing") as? Bool ?? false
        loadAPIKeys()
    }

    /// Reads the current secret for a provider, returning an empty string when none is saved.
    func apiKey(for provider: DemoAPIKeyProvider) -> String {
        apiKeys[provider] ?? ""
    }

    /// Saves or clears a provider secret in the keychain.
    func setAPIKey(_ value: String, for provider: DemoAPIKeyProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? keychain.delete(account: provider.account)
            apiKeys[provider] = ""
        } else {
            try? keychain.save(trimmed, account: provider.account)
            apiKeys[provider] = trimmed
        }
    }

    /// Returns whether a provider namespace currently has a non-empty key.
    func hasAPIKey(for provider: DemoAPIKeyProvider) -> Bool {
        !apiKey(for: provider).isEmpty
    }

    /// Returns whether a file provider can be used with the current keychain state.
    func hasAPIKey(for provider: DemoFileProvider) -> Bool {
        hasAPIKey(for: provider.apiKeyProvider)
    }

    /// Returns whether a realtime provider can be used with the current keychain state.
    func hasAPIKey(for provider: DemoRealtimeProvider) -> Bool {
        hasAPIKey(for: provider.apiKeyProvider)
    }

    /// Builds the missing-key message for file workflows.
    func missingAPIKeyMessage(for provider: DemoFileProvider) -> String {
        "Add a \(provider.title) API key in Settings."
    }

    /// Builds the missing-key message for realtime workflows.
    func missingAPIKeyMessage(for provider: DemoRealtimeProvider) -> String {
        "Add a \(provider.title) API key in Settings."
    }

    /// Applies the current demo defaults to the shared `SpeechService`.
    func apply(to speech: SpeechService) {
        let elevenLabsKey = apiKey(for: .elevenLabs)
        speech.elevenLabs = elevenLabsKey.isEmpty ? nil : ElevenLabsConfiguration(
            apiKey: elevenLabsKey,
            realtimeModelID: elevenLabsRealtimeModel,
            fileTranscriptionModelID: elevenLabsFileModel
        )

        let openAIKey = apiKey(for: .openAI)
        speech.openAI = openAIKey.isEmpty ? nil : OpenAIConfiguration(
            apiKey: openAIKey,
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

        let grokKey = apiKey(for: .grok)
        speech.grok = grokKey.isEmpty ? nil : GrokConfiguration(
            apiKey: grokKey,
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

        let cohereKey = apiKey(for: .cohere)
        speech.cohere = cohereKey.isEmpty ? nil : CohereConfiguration(
            apiKey: cohereKey,
            modelID: cohereModel,
            language: cohereLanguage,
            temperature: Double(cohereTemperature)
        )

        let aquaKey = apiKey(for: .aqua)
        speech.aqua = aquaKey.isEmpty ? nil : AquaConfiguration(
            apiKey: aquaKey,
            modelID: aquaModel,
            language: aquaLanguage
        )

        let metaKey = apiKey(for: .meta)
        speech.meta = metaKey.isEmpty ? nil : MetaConfiguration(
            apiKey: metaKey,
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

        let geminiKey = apiKey(for: .gemini)
        speech.gemini = geminiKey.isEmpty ? nil : GeminiConfiguration(
            apiKey: geminiKey,
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

    /// Converts the current provider-specific controls into SpeechKit file transcription options.
    func fileOptions(for provider: DemoFileProvider) -> SpeechFileTranscriptionOptions {
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
        }
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
        case .elevenLabs, .aqua, .cohere, .meta, .gemini:
            return nil
        }
    }

    /// Loads provider secrets into observable state for the current run.
    private func loadAPIKeys() {
        for provider in DemoAPIKeyProvider.allCases {
            apiKeys[provider] = (try? keychain.read(account: provider.account)) ?? ""
        }
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

/// Minimal keychain storage used to keep demo API keys out of `UserDefaults`.
struct DemoKeychainStore {
    let service: String

    /// Saves a secret for a provider account.
    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DemoKeychainError.unhandledStatus(status)
        }
    }

    /// Reads a secret for a provider account.
    func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DemoKeychainError.unhandledStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes a secret for a provider account.
    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DemoKeychainError.unhandledStatus(status)
        }
    }

    /// Builds the shared keychain query attributes for a provider account.
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// Keychain failures surfaced by the demo configuration layer.
enum DemoKeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
