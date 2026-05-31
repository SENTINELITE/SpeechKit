import SpeechKit
import SwiftUI

/// Provider keys and default option controls shared by all demo workflows.
struct SettingsSheet: View {
    @Bindable var configuration: DemoConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var keyDrafts: [DemoAPIKeyProvider: String]

    /// Seeds editable key drafts from the current keychain-backed configuration.
    init(configuration: DemoConfiguration) {
        self.configuration = configuration
        _keyDrafts = State(initialValue: Dictionary(uniqueKeysWithValues: DemoAPIKeyProvider.allCases.map {
            ($0, configuration.apiKey(for: $0))
        }))
    }

    var body: some View {
        NavigationStack {
            Form {
                apiKeysSection
                realtimeDefaultsSection
                fileDefaultsSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    /// Stores provider API keys without exposing them to `UserDefaults`.
    private var apiKeysSection: some View {
        Section("API Keys") {
            ForEach(DemoAPIKeyProvider.allCases) { provider in
                APIKeyEditorRow(
                    provider: provider,
                    text: binding(for: provider),
                    isSaved: configuration.hasAPIKey(for: provider),
                    save: {
                        configuration.setAPIKey(keyDrafts[provider] ?? "", for: provider)
                    }
                )
            }
        }
    }

    /// Controls defaults used when the realtime sample opens a provider session.
    private var realtimeDefaultsSection: some View {
        Section("Realtime Defaults") {
            Picker("Provider", selection: $configuration.realtimeProvider) {
                ForEach(DemoRealtimeProvider.allCases) { provider in
                    Text(provider.title)
                        .tag(provider)
                        .disabled(!configuration.hasAPIKey(for: provider))
                }
            }

            if !configuration.hasAPIKey(for: configuration.realtimeProvider) {
                Label(configuration.missingAPIKeyMessage(for: configuration.realtimeProvider), systemImage: "key.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("ElevenLabs model", selection: $configuration.elevenLabsRealtimeModel) {
                Text(ElevenLabsModelID.scribeV2Realtime.rawValue).tag(ElevenLabsModelID.scribeV2Realtime)
            }

            Picker("OpenAI session", selection: $configuration.openAIRealtimeSessionModel) {
                ForEach(OpenAIRealtimeSessionModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Picker("OpenAI transcription", selection: $configuration.openAIRealtimeTranscriptionModel) {
                ForEach(OpenAIRealtimeTranscriptionModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Picker("Grok language", selection: $configuration.grokLanguage) {
                Text("Default").tag(GrokLanguage?.none)
                ForEach(GrokLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(GrokLanguage?.some(language))
                }
            }

            Toggle("Grok diarization", isOn: $configuration.grokDiarize)
            Toggle("Grok filler words", isOn: $configuration.grokRealtimeFillerWords)
        }
    }

    /// Controls defaults used by both file import and recorded-upload samples.
    private var fileDefaultsSection: some View {
        Section("File and Dictation Defaults") {
            Picker("Provider", selection: $configuration.fileProvider) {
                ForEach(DemoFileProvider.allCases) { provider in
                    Text(provider.title)
                        .tag(provider)
                        .disabled(!configuration.hasAPIKey(for: provider))
                }
            }

            if !configuration.hasAPIKey(for: configuration.fileProvider) {
                Label(configuration.missingAPIKeyMessage(for: configuration.fileProvider), systemImage: "key.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FileProviderOptionsView(configuration: configuration)
        }
    }

    /// Creates a dictionary-backed binding for a provider key draft.
    private func binding(for provider: DemoAPIKeyProvider) -> Binding<String> {
        Binding(
            get: { keyDrafts[provider] ?? "" },
            set: { keyDrafts[provider] = $0 }
        )
    }
}

/// A single API key editor row used by the settings sheet.
private struct APIKeyEditorRow: View {
    let provider: DemoAPIKeyProvider
    @Binding var text: String
    let isSaved: Bool
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("\(provider.title) API Key", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Text(isSaved ? "Saved" : "Not configured")
                    .font(.caption)
                    .foregroundStyle(isSaved ? .green : .secondary)

                Spacer()

                Button("Save", action: save)
                    .buttonStyle(.bordered)
            }
        }
    }
}
