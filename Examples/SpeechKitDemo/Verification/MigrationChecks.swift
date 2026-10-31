import Foundation
import SpeechKit

@main
struct MigrationChecks {
    @MainActor
    static func main() async throws {
        let suite = "SpeechKitDemo.MigrationChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SyntheticCredentialStore()
        let configuration = DemoConfiguration(defaults: defaults, keychain: store)
        precondition(configuration.relayOptimizesUploads)
        let direct = SpeechService(credentialPolicy: .allowStaticKeys)

        for provider in DemoAPIKeyProvider.allCases {
            store.readAccounts = []
            try configuration.prepare(direct, for: provider)
            precondition(store.readAccounts == [provider.account])
            let metadata = credentialMetadata(in: direct, for: provider)
            precondition(metadata.kind == .apiKey && metadata.hasCredential)
            await configuration.resetAuthorization(in: direct)
            precondition(!credentialMetadata(in: direct, for: provider).hasCredential)
            precondition(direct.realtimeRecordingData == nil)
        }
        try checkURLs()
        checkSafeErrors()
        store.readAccounts = []
        try await configuration.enableRelay(url: "https://relay.example.invalid", authentication: .none,
                                            bearerToken: "", useVendorTokens: false, replacing: direct)
        let proxy = configuration.relayService!
        precondition(configuration.isRelayReady && proxy.credentialPolicy == .relayOnly)
        precondition(proxy.relay?.providers.count == DemoAPIKeyProvider.allCases.count)
        precondition(proxy.relay?.tokenStrategy == .proxyAll)
        precondition(proxy.relay?.optimizedUploads == .on)
        for provider in DemoAPIKeyProvider.allCases {
            try configuration.prepare(proxy, for: provider)
            let metadata = credentialMetadata(in: proxy, for: provider)
            precondition(metadata.kind == .apiKey && !metadata.hasCredential)
        }
        for provider in DemoFileProvider.allCases { precondition(configuration.hasAPIKey(for: provider)) }
        for provider in DemoRealtimeProvider.allCases { precondition(configuration.hasAPIKey(for: provider)) }
        precondition(store.readAccounts.isEmpty)
        await configuration.resetAuthorization(in: proxy)
        precondition(proxy.relay != nil && configuration.isRelayReady)

        let syntheticToken = "synthetic-demo-test-token"
        try await configuration.enableRelay(url: "https://relay.example.invalid", authentication: .bearer,
                                            bearerToken: syntheticToken, useVendorTokens: true,
                                            optimizeUploads: false, replacing: proxy)
        let bearer = configuration.relayService!
        precondition(proxy.relay == nil)
        precondition(bearer.credentialPolicy == .disallowStaticKeys)
        precondition(bearer.relay?.tokenStrategy == .vendorTokensWhenAvailable)
        precondition(bearer.relay?.optimizedUploads == .off)
        precondition(!configuration.relayOptimizesUploads)
        precondition(!DemoConfiguration(defaults: defaults, keychain: store).relayOptimizesUploads)
        precondition(configuration.relayExpiresAt!.timeIntervalSinceNow > 0)
        precondition(configuration.relayExpiresAt!.timeIntervalSinceNow <= 300)
        precondition(!defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains(syntheticToken) })
        precondition(store.savedValues.isEmpty && store.readAccounts.isEmpty)

        if !DemoConfiguration.supportsAppAttest {
            do {
                try await configuration.enableRelay(url: "https://relay.example.invalid", authentication: .appAttest,
                                                    bearerToken: "", useVendorTokens: false, replacing: bearer)
                preconditionFailure("Unsupported App Attest must not fall back.")
            } catch let failure as SpeechFailure {
                precondition(failure.category == .attestationUnsupported)
            }
            precondition(configuration.relayService === bearer && configuration.isRelayReady)
        }

        try configuration.setAPIKey("", for: .openAI)
        await configuration.clearAuthorization(in: bearer)
        precondition(bearer.relay == nil && !configuration.isRelayReady && configuration.isRelayEnabled)
        precondition(!configuration.hasAPIKey(for: DemoFileProvider.openAI))
        do {
            try configuration.prepare(direct, for: .elevenLabs)
            preconditionFailure("An expired or cleared Relay must not fall back to saved keys.")
        } catch let failure as SpeechFailure {
            precondition(failure.category == .invalidCredential)
        }
        precondition(store.readAccounts.isEmpty)
        await configuration.disableRelay(in: bearer)
        precondition(configuration.relayService == nil && !configuration.isRelayEnabled)
        precondition(configuration.relayExpiresAt == nil)
        try configuration.prepare(direct, for: .elevenLabs)
        precondition(store.readAccounts == [DemoAPIKeyProvider.elevenLabs.account])
        let relaunched = DemoConfiguration(defaults: defaults, keychain: store)
        precondition(!relaunched.isRelayEnabled && relaunched.relayService == nil)
        precondition(relaunched.relayURL == "https://relay.example.invalid")
        await configuration.resetAuthorization(in: direct)
        print("Demo 3.0 migration checks passed. No network or real Keychain access.")
    }

    static func checkURLs() throws {
        for value in ["https://relay.example.invalid", "http://localhost:8787", "http://127.0.0.1:8787", "http://[::1]:8787"] {
            _ = try DemoConfiguration.validatedRelayURL(value)
        }
        for value in ["", "http://relay.example.invalid", "https://user:pass@relay.example.invalid",
                      "https://relay.example.invalid/path", "https://relay.example.invalid?token=synthetic",
                      "https://relay.example.invalid#fragment", "file:///tmp/relay"] {
            do {
                _ = try DemoConfiguration.validatedRelayURL(value)
                preconditionFailure("Unsafe Relay URL accepted.")
            } catch let failure as SpeechFailure {
                precondition(failure.category == .invalidEndpoint)
            }
        }
    }

    static func checkSafeErrors() {
        let sentinel = "synthetic-private-error-text"
        let errors: [Error] = [
            NSError(domain: sentinel, code: 1, userInfo: [NSLocalizedDescriptionKey: sentinel]),
            SpeechError.unsupportedCapability(provider: .openAI, capability: sentinel),
            SpeechError.appleSpeechUnsupportedLocale(localeIdentifier: sentinel),
            SpeechError.uploadFailed(provider: .gemini, reason: .uploadFailed),
            SpeechError.decodingFailed(provider: .meta, reason: .decodingFailed),
            SpeechError.providerFailure(provider: .fishAudio, reason: .timedOut),
            FishAudioRealtimeError.serverError(code: 401),
            FishAudioRealtimeError.sessionClosed(code: 4500),
            SpeechAudioCaptureError.audioEngineError(.requestFailed), CancellationError()
        ]
        for error in errors {
            let message = DemoFailure.message(for: error)
            precondition(!message.isEmpty && !message.contains(sentinel))
        }
        precondition(DemoFailure.message(for: SpeechFailure(.attestationUnsupported)).contains("Simulator"))
        precondition(DemoFailure.message(for: SpeechFailure(.server, statusCode: 401)).contains("Reauthenticate"))
        precondition(DemoFailure.message(for: SpeechFailure(.server, statusCode: 429)).contains("limit"))
    }

    @MainActor
    static func credentialMetadata(in speech: SpeechService, for provider: DemoAPIKeyProvider) -> (kind: SpeechCredential.Kind?, hasCredential: Bool) {
        switch provider {
        case .elevenLabs: (speech.elevenLabs?.credentialKind, speech.elevenLabs?.hasCredential ?? false)
        case .openAI: (speech.openAI?.credentialKind, speech.openAI?.hasCredential ?? false)
        case .grok: (speech.grok?.credentialKind, speech.grok?.hasCredential ?? false)
        case .meta: (speech.meta?.credentialKind, speech.meta?.hasCredential ?? false)
        case .gemini: (speech.gemini?.credentialKind, speech.gemini?.hasCredential ?? false)
        case .mistral: (speech.mistral?.credentialKind, speech.mistral?.hasCredential ?? false)
        case .fishAudio: (speech.fishAudio?.credentialKind, speech.fishAudio?.hasCredential ?? false)
        case .cohere: (speech.cohere?.credentialKind, speech.cohere?.hasCredential ?? false)
        case .aqua: (speech.aqua?.credentialKind, speech.aqua?.hasCredential ?? false)
        }
    }
}

private final class SyntheticCredentialStore: DemoCredentialStore {
    var readAccounts: [String] = []
    var savedValues: [String] = []
    func contains(account: String) throws -> Bool { true }
    func read(account: String) throws -> String? {
        readAccounts.append(account)
        return "synthetic-demo-vendor-key"
    }
    func save(_ value: String, account: String) throws { savedValues.append(value) }
    func delete(account: String) throws {}
}
