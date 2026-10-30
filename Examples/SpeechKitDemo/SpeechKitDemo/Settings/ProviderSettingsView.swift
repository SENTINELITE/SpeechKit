import SpeechKit
import SwiftUI

/// One cloud provider's API key, realtime-only options, and transcription options.
struct ProviderSettingsView: View {
    @Bindable var configuration: DemoConfiguration
    let provider: DemoAPIKeyProvider
    @State private var keyDraft = ""

    var body: some View {
        Form {
            apiKeySection

            if let realtimeProvider = provider.realtimeProvider {
                Section("Realtime") {
                    RealtimeOnlyOptionsView(configuration: configuration, provider: realtimeProvider)
                }
            }

            if let fileProvider = provider.fileProvider {
                Section {
                    FileProviderOptionsView(configuration: configuration, provider: fileProvider)
                } header: {
                    Text("Transcription")
                } footer: {
                    if let sharedSettingsNote = provider.sharedSettingsNote {
                        Text(sharedSettingsNote)
                    }
                }
            }
        }
        .navigationTitle(provider.title)
        .onAppear {
            keyDraft = configuration.apiKey(for: provider)
        }
    }

    /// Edits the provider's keychain-backed API key.
    private var apiKeySection: some View {
        Section {
            SecureField("\(provider.title) API Key", text: $keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Text(hasKey ? "Saved" : "Not configured")
                    .font(.caption)
                    .foregroundStyle(hasKey ? .green : .secondary)

                Spacer()

                Button("Save") {
                    configuration.setAPIKey(keyDraft, for: provider)
                }
                .buttonStyle(.bordered)
                .disabled(keyDraft == configuration.apiKey(for: provider))
            }

            if hasKey {
                Button("Remove Key", role: .destructive) {
                    keyDraft = ""
                    configuration.setAPIKey("", for: provider)
                }
            }
        } header: {
            Text("API Key")
        } footer: {
            Text("Stored in this device's keychain.")
        }
    }

    private var hasKey: Bool {
        configuration.hasAPIKey(for: provider)
    }
}

extension DemoAPIKeyProvider {
    /// The realtime provider that uses this key, if the service offers realtime transcription.
    var realtimeProvider: DemoRealtimeProvider? {
        DemoRealtimeProvider.allCases.first { $0.apiKeyProvider == self }
    }

    /// The file provider that uses this key.
    var fileProvider: DemoFileProvider? {
        DemoFileProvider.allCases.first { $0.apiKeyProvider == self }
    }

    /// The workflows this key unlocks, shown under the provider name.
    var capabilities: String {
        [
            realtimeProvider == nil ? nil : "Realtime",
            fileProvider == nil ? nil : "File & Dictation",
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    /// Explains which transcription settings also shape realtime sessions.
    var sharedSettingsNote: String? {
        switch self {
        case .grok: "Language and diarization also apply to realtime sessions."
        case .meta: "Model, mode, language bias, and keywords also apply to realtime sessions."
        case .gemini: "Mode, language codes, and custom vocabulary also apply to Gemini Live. Gemini Live does not support diarization or word timestamps."
        case .mistral: "Language, context bias, and diarization also apply to realtime sessions. Diarized realtime sessions skip turn detection and start a new entry when the speaker changes."
        case .fishAudio: "File settings do not apply to realtime sessions, which have their own turn detection, speaker label, and terms settings. Realtime is in preview and is billed while the session is open."
        case .elevenLabs, .openAI, .cohere, .aqua: nil
        }
    }
}
