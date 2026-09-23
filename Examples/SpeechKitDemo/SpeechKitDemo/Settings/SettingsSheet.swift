import SpeechKit
import SwiftUI

/// Provider keys and default option controls shared by all demo workflows.
struct SettingsSheet: View {
    @Bindable var configuration: DemoConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var keyDrafts: [DemoAPIKeyProvider: String]
    @State private var liveKeyDraft: String

    /// Seeds editable key drafts from the current keychain-backed configuration.
    init(configuration: DemoConfiguration) {
        self.configuration = configuration
        _keyDrafts = State(initialValue: Dictionary(uniqueKeysWithValues: DemoAPIKeyProvider.allCases.map {
            ($0, configuration.apiKey(for: $0))
        }))
        _liveKeyDraft = State(initialValue: configuration.openAILiveAPIKey)
    }

    var body: some View {
        NavigationStack {
            Form {
                apiKeysSection
                realtimeDefaultsSection
                conversationDefaultsSection
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

            Picker("OpenAI live delay", selection: $configuration.openAIRealtimeDelay) {
                ForEach(DemoOpenAIRealtimeDelay.allCases) { delay in
                    Text(delay.rawValue).tag(delay)
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

            metaRealtimeControls
            geminiRealtimeControls
        }
    }

    /// Controls the Meta realtime session defaults.
    @ViewBuilder
    private var metaRealtimeControls: some View {
        Picker("Meta mode", selection: $configuration.metaMode) {
            ForEach(MetaTranscriptionMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }

        Picker("Meta partials", selection: $configuration.metaRealtimePartialMode) {
            ForEach(MetaPartialMode.allCases, id: \.self) { partialMode in
                Text(partialMode.rawValue).tag(partialMode)
            }
        }

        Picker("Meta language bias", selection: $configuration.metaLanguage) {
            Text("Default").tag(MetaLanguage?.none)
            ForEach(MetaLanguage.allCases, id: \.self) { language in
                Text(language.displayName).tag(MetaLanguage?.some(language))
            }
        }
    }

    /// Controls the Gemini Live session defaults.
    @ViewBuilder
    private var geminiRealtimeControls: some View {
        Picker("Gemini live model", selection: $configuration.geminiRealtimeModel) {
            ForEach(GeminiRealtimeModelID.allCases, id: \.self) { model in
                Text(model.rawValue).tag(model)
            }
        }

        Picker("Gemini mode", selection: $configuration.geminiMode) {
            ForEach(GeminiTranscriptionMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }

        TextField("Gemini language codes", text: $configuration.geminiLanguageCodes)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        Text("Gemini Live does not support diarization or word timestamps.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// Controls defaults used when the conversation sample opens a GPT-Live session.
    private var conversationDefaultsSection: some View {
        Section("OpenAI GPT-Live") {
            Picker("Voice", selection: $configuration.openAILiveVoice) {
                ForEach(OpenAILiveVoice.knownVoices, id: \.rawValue) { voice in
                    Text(voice.rawValue).tag(voice.rawValue)
                }
            }

            TextField("Voice override", text: $configuration.openAILiveVoiceOverride)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField(
                "Instructions",
                text: $configuration.openAILiveInstructions,
                axis: .vertical
            )
            .lineLimit(2...6)

            Picker("Delegation", selection: $configuration.openAILiveDelegationMode) {
                ForEach(DemoLiveDelegationMode.allCases) { delegation in
                    Text(delegation.title).tag(delegation)
                }
            }

            if configuration.openAILiveDelegationMode == .responses {
                TextField("Backend model", text: $configuration.openAILiveBackendModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Toggle("Use a separate GPT-Live API key", isOn: $configuration.openAILiveUsesSeparateKey)

            if configuration.openAILiveUsesSeparateKey {
                liveKeyEditor
            }

            Text("GPT-Live bills per second of streamed audio. The demo ends the session when you leave the screen or background the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Edits the optional conversation-only secret without touching the shared OpenAI key.
    private var liveKeyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("GPT-Live API Key", text: $liveKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Text(configuration.openAILiveAPIKey.isEmpty ? "Not configured" : "Saved")
                    .font(.caption)
                    .foregroundStyle(configuration.openAILiveAPIKey.isEmpty ? Color.secondary : Color.green)

                Spacer()

                Button("Save") {
                    configuration.setOpenAILiveAPIKey(liveKeyDraft)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
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
