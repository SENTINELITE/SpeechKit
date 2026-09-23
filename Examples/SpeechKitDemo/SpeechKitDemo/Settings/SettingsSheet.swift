import SpeechKit
import SpeechKitVoz
import SwiftUI

/// Provider keys and default option controls shared by all demo workflows.
struct SettingsSheet: View {
    @Bindable var configuration: DemoConfiguration
    @Environment(\.dismiss) private var dismiss
    @Environment(\.speechService) private var speech
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
                VozModelManagementSection(speech: speech)
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

    /// Controls defaults used by both file import and recorded-upload samples.
    private var fileDefaultsSection: some View {
        Section("File and Dictation Defaults") {
            Picker("Provider", selection: $configuration.fileProvider) {
                ForEach(DemoFileProvider.allCases) { provider in
                    Text(provider.title)
                        .tag(provider)
                        .disabled(provider.requiresAPIKey && !configuration.hasAPIKey(for: provider))
                }
            }

            if configuration.fileProvider.requiresAPIKey && !configuration.hasAPIKey(for: configuration.fileProvider) {
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

/// Controls the optional VOZ model that performs file transcription entirely on this device.
private struct VozModelManagementSection: View {
    let speech: SpeechService
    /// Whether verified model files are on disk, so preparing skips the download.
    @State private var isModelCached = false

    private var isPreparing: Bool {
        switch speech.vozModelState {
        case .checkingCache, .downloading, .loading:
            true
        case .unprepared, .ready, .failed:
            false
        }
    }

    private var stateTitle: String {
        switch speech.vozModelState {
        case .unprepared:
            isModelCached ? "Downloaded, not loaded" : "Not downloaded"
        case .checkingCache:
            "Checking model cache"
        case .downloading:
            "Downloading"
        case .loading:
            "Loading"
        case .ready:
            "Ready for local transcription"
        case .failed:
            "Preparation failed"
        }
    }

    var body: some View {
        Section("VOZ On-Device Model") {
            Label(stateTitle, systemImage: statusImageName)
                .foregroundStyle(statusColor)

            if case .downloading = speech.vozModelState {
                ProgressView(value: speech.vozModelDownloadProgress)
                LabeledContent(
                    "Download",
                    value: speech.vozModelDownloadProgress,
                    format: .percent.precision(.fractionLength(0))
                )
            } else if case .loading = speech.vozModelState {
                ProgressView("Loading model…")
            }

            if case .unprepared = speech.vozModelState, isModelCached {
                Text("The model files are on this device. Loading them takes a moment and does not download anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .checkingCache = speech.vozModelState {
                Text("Checking the existing model cache before starting a network download…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(message) = speech.vozModelState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if isPreparing {
                Button("Cancel preparation", role: .cancel, action: speech.releaseVozModel)
            } else if !isReady {
                Button(preparationActionTitle, action: speech.prepareVozModelInBackground)
            }

            Button("Unload model", role: .destructive, action: speech.releaseVozModel)
                .disabled(isPreparing || isUnprepared)

            Text("VOZ transcribes selected and recorded audio locally after its model is available on this device. Downloaded files remain available for the next launch.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("The first VOZ download is about 467 MB when model files are not already cached.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Link("Powered by Desert Ant Labs", destination: URL(string: "https://desertant.com")!)
                Link("VOZ license", destination: URL(string: "https://license.desertant.com/1.0")!)
            }
            .font(.caption)
        }
        .task(id: isReady) {
            // `isModelCached()` verifies every cached file's digest, so keep it off
            // the main actor and only re-check when the model finishes loading.
            guard let voz = speech.voz else { return }
            isModelCached = await Task.detached { voz.isModelCached() }.value
        }
    }

    private var isReady: Bool {
        if case .ready = speech.vozModelState { return true }
        return false
    }

    private var isUnprepared: Bool {
        if case .unprepared = speech.vozModelState { return true }
        return false
    }

    private var preparationActionTitle: String {
        if case .failed = speech.vozModelState { return "Retry download and preparation" }
        return isModelCached ? "Load model" : "Download and prepare"
    }

    private var statusImageName: String {
        switch speech.vozModelState {
        case .unprepared: isModelCached ? "internaldrive" : "arrow.down.circle"
        case .checkingCache: "magnifyingglass.circle"
        case .downloading: "arrow.down.circle.fill"
        case .loading: "gearshape.2"
        case .ready: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch speech.vozModelState {
        case .ready: .green
        case .failed: .red
        case .unprepared, .checkingCache, .downloading, .loading: .secondary
        }
    }
}
