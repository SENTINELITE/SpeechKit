import Foundation
import Observation
import Security
import SpeechKit

/// File-transcription providers exposed by the demo app.
enum DemoFileProvider: String, CaseIterable, Identifiable {
    case elevenLabs
    case aqua
    case cohere
    case grok
    case openAI

    var id: Self { self }

    /// The display name shown in menus and settings.
    var title: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .aqua: "Aqua"
        case .cohere: "Cohere"
        case .grok: "Grok"
        case .openAI: "OpenAI"
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
        }
    }
}

/// Realtime transcription providers exposed by the demo app.
enum DemoRealtimeProvider: String, CaseIterable, Identifiable {
    case elevenLabs
    case openAI
    case grok

    var id: Self { self }

    /// The display name shown in menus and settings.
    var title: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .openAI: "OpenAI"
        case .grok: "Grok"
        }
    }

    /// The SpeechKit provider value used when opening a realtime session.
    var speechProvider: SpeechRealtimeProvider {
        switch self {
        case .elevenLabs: .elevenLabs
        case .openAI: .openAI
        case .grok: .grok
        }
    }

    /// The API key namespace required for this realtime provider.
    var apiKeyProvider: DemoAPIKeyProvider {
        switch self {
        case .elevenLabs: .elevenLabs
        case .openAI: .openAI
        case .grok: .grok
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

    var id: Self { self }

    /// The display name shown beside key entry fields.
    var title: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .openAI: "OpenAI"
        case .grok: "Grok"
        case .cohere: "Cohere"
        case .aqua: "Aqua"
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

    var openAIPrompt: String {
        didSet { set(openAIPrompt, for: "openAIPrompt") }
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
        openAIFileModel = Self.enumValue(for: "openAIFileModel", default: .gpt4oTranscribe, defaults: defaults)
        openAIRealtimeSessionModel = Self.enumValue(for: "openAIRealtimeSessionModel", default: .gptRealtime, defaults: defaults)
        openAIRealtimeTranscriptionModel = Self.enumValue(for: "openAIRealtimeTranscriptionModel", default: .gpt4oTranscribe, defaults: defaults)
        openAILanguage = defaults.string(forKey: "openAILanguage") ?? ""
        openAIPrompt = defaults.string(forKey: "openAIPrompt") ?? ""
        openAITemperature = defaults.string(forKey: "openAITemperature") ?? ""
        openAIIncludeLogprobs = defaults.object(forKey: "openAIIncludeLogprobs") as? Bool ?? false
        openAIWordTimestamps = defaults.object(forKey: "openAIWordTimestamps") as? Bool ?? false
        openAISegmentTimestamps = defaults.object(forKey: "openAISegmentTimestamps") as? Bool ?? false
        openAIDiarization = defaults.object(forKey: "openAIDiarization") as? Bool ?? false
        openAITimeoutMinutes = defaults.object(forKey: "openAITimeoutMinutes") as? Double ?? 10
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
            prompt: nilIfBlank(openAIPrompt),
            temperature: Double(openAITemperature),
            diarizationChunkingStrategy: openAIDiarization ? .auto : nil,
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
                prompt: nilIfBlank(openAIPrompt),
                temperature: Double(openAITemperature),
                includeLogprobs: openAIIncludeLogprobs,
                timestampGranularities: granularities,
                diarizationChunkingStrategy: openAIDiarization ? .auto : nil,
                timeoutInterval: openAITimeoutMinutes * 60
            )
        }
    }

    /// Returns the provider timeout shown by upload progress UI when SpeechKit has a timeout for that provider.
    func timeoutInterval(for provider: DemoFileProvider) -> TimeInterval? {
        switch provider {
        case .grok:
            return grokTimeoutMinutes * 60
        case .openAI:
            return openAITimeoutMinutes * 60
        case .elevenLabs, .aqua, .cohere:
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
